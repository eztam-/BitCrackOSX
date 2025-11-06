#include <metal_stdlib>
using namespace metal;

// ================= Hashing for fixed 20-byte keys =================

// Load 32-bit little-endian from a byte pointer
inline uint load_u32_le(const device uchar *p)
{
    return ((uint)p[0]) |
           ((uint)p[1] << 8) |
           ((uint)p[2] << 16) |
           ((uint)p[3] << 24);
}

inline uint rotl32(uint x, uint r) { return (x << r) | (x >> (32 - r)); }

// Murmur3-ish mix for 20-byte inputs (5x u32). Fast & well-distributed.
inline uint hash32_20(const device uchar *data, uint seed)
{
    constexpr uint c1 = 0xcc9e2d51u;
    constexpr uint c2 = 0x1b873593u;

    uint h = seed;

    // 5 words (20 bytes total)
    uint k0 = load_u32_le(data +  0);
    uint k1 = load_u32_le(data +  4);
    uint k2 = load_u32_le(data +  8);
    uint k3 = load_u32_le(data + 12);
    uint k4 = load_u32_le(data + 16);

    uint ks[5] = {k0,k1,k2,k3,k4};

    // body
    for (uint i = 0; i < 5; i++) {
        uint k = ks[i];
        k *= c1; k = rotl32(k,15); k *= c2;
        h ^= k;
        h = rotl32(h,13);
        h = h * 5u + 0xe6546b64u;
    }

    // tail length = 20
    h ^= 20u;

    // fmix
    h ^= h >> 16;
    h *= 0x85ebca6bu;
    h ^= h >> 13;
    h *= 0xc2b2ae35u;
    h ^= h >> 16;
    return h;
}

// Produce two 32-bit hashes for Kirsch-Mitzenmacher
inline void hash_pair_20(const device uchar *data, thread uint &h1, thread uint &h2)
{
    h1 = hash32_20(data, 0x9747b28cu);
    h2 = hash32_20(data, 0x12345678u);
}

// Compute k indices via h(i) = h1 + i*h2 mod m
inline uint bit_index(uint h1, uint h2, uint i, uint m_bits)
{
    // Use 64-bit to avoid overflow in the multiply/add path
    ulong v = (ulong)h1 + (ulong)i * (ulong)h2;
    // Fast modulo: if m_bits is power of two, use mask; else fallback %
    // We'll do both and let host select a power-of-two size if desired.
    return (uint)(v % (ulong)m_bits);
}

// ================ Insert Kernel ================
//
// items:   array of 20-byte keys
// count:   number of items
// bits:    bloom bitset as 32-bit atomics
// m_bits:  number of bits in bloom (>= count * scaling)
// k:       number of hashes (typically ~ ln(2) * m/n)

kernel void bloom_insert(device const uchar        *items      [[buffer(0)]],
                         constant uint             &count      [[buffer(1)]],
                         device atomic_uint        *bits       [[buffer(2)]],
                         constant uint             &m_bits     [[buffer(3)]],
                         constant uint             &k_hashes   [[buffer(4)]],
                         uint tid [[thread_position_in_grid]])
{
    if (tid >= count) return;

    const device uchar *key = items + (tid * 20);

    uint h1, h2;
    hash_pair_20(key, h1, h2);

    for (uint i = 0; i < k_hashes; i++) {
        uint idx = bit_index(h1, h2, i, m_bits);
        uint word = idx >> 5;           // /32
        uint mask = 1u << (idx & 31u);
        // atomic OR into device memory (relaxed is fine for a Bloom filter)
        atomic_fetch_or_explicit(&bits[word], mask, memory_order_relaxed);
    }
}

// ================ Query Kernel ================
//
// items:   array of 20-byte keys to check
// count:   number of queries
// bits:    bloom bitset as plain uints (reads only)
// m_bits:  number of bits in bloom
// k:       number of hashes
// out:     per-query result (1 = maybe in set, 0 = definitely not)

kernel void bloom_query(device const uchar *items      [[buffer(0)]],
                        constant uint      &count      [[buffer(1)]],
                        const device uint  *bits       [[buffer(2)]],
                        constant uint      &m_bits     [[buffer(3)]],
                        constant uint      &k_hashes   [[buffer(4)]],
                        device uint        *out        [[buffer(5)]],
                        uint tid [[thread_position_in_grid]])
{
    if (tid >= count) return;

    const device uchar *key = items + (tid * 20);

    uint h1, h2;
    hash_pair_20(key, h1, h2);

    // Early-out as soon as any bit is clear
    for (uint i = 0; i < k_hashes; i++) {
        uint idx  = bit_index(h1, h2, i, m_bits);
        uint word = idx >> 5;
        uint mask = 1u << (idx & 31u);
        uint v    = bits[word];
        if ((v & mask) == 0u) {
            out[tid] = 0u;
            return;
        }
    }
    out[tid] = 1u;
}
