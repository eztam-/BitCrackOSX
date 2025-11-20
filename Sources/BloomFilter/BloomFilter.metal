
#include <metal_stdlib>
using namespace metal;

// Insertions are thread safe and could be done in parallell.
// Queries are also thread safe.
// The only scenario which wouldn't be thread safe is, if there are insertions happening at the same time when we query (which we don't do in this app)


// Load 32-bit value (assumes aligned access)
inline uint load32(const device uchar *p, uint idx) {
    return ((const device uint*)p)[idx];
}
/*
// Hash pair generation using FNV-1a 
inline void hash_pair_fnv(const device uchar *data,
                          uint len_u32,
                          thread uint &h1, 
                          thread uint &h2) {
    h1 = 0x811C9DC5u;
    h2 = 0xABC98388u;
    
    const device uint *p = (const device uint*)data;
    
    for (uint i = 0; i < len_u32; i++) {
        uint val = p[i];
        // FNV-1a for h1
        h1 = (h1 ^ val) * 0x01000193u;
        // Custom mix for h2
        h2 = (h2 + (val * 0x9E3779B1u)) ^ (h2 >> 13);
    }
}*/


// Murmur3 finalizer for better avalanche and uniformity
inline uint fmix32(uint x) {
    x ^= x >> 16;
    x *= 0x85EBCA6Bu;
    x ^= x >> 13;
    x *= 0xC2B2AE35u;
    x ^= x >> 16;
    return x;
}

// Improved FNV-1a hash pair with proper mixing
inline void hash_pair_fnv(const device uchar *data,
                          uint len_u32,
                          thread uint &h1,
                          thread uint &h2)
{
    // Initialize differently to reduce correlation
    uint x1 = 0x811C9DC5u;  // standard FNV offset
    uint x2 = 0xABC98388u;  // arbitrary distinct seed

    const device uint *p = (const device uint*)data;

    // process data 32-bit word-wise
    for (uint i = 0; i < len_u32; i++) {
        uint val = p[i];
        // FNV-1a mix for x1
        x1 = (x1 ^ val) * 0x01000193u;
        // A different nonlinear mix for x2
        x2 ^= val + 0x9E3779B9u + (x2 << 6) + (x2 >> 2);
    }

    // Finalize with strong avalanche
    h1 = fmix32(x1);
    h2 = fmix32(x2) | 1u;   // ensure h2 is odd to cover full bit range
}




// INSERT KERNEL
kernel void bloom_insert(
    const device uchar *items      [[buffer(0)]],
    constant uint &item_count      [[buffer(1)]],
    device atomic_uint *bits       [[buffer(2)]],
    constant uint &m_bits          [[buffer(3)]],
    constant uint &k_hashes        [[buffer(4)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= item_count) return;
    
    const device uchar *key = items + (gid * 20); // RIPEMD160 hash is 20 bytes long
    
    uint h1, h2;
    hash_pair_fnv(key, 5, h1, h2); // RIPEMD160 hash is 5 UInt32 long
    
    for (uint i = 0; i < k_hashes; i++) {
        // Matching Swift: (h1 + i * h2) % m_bits
        ulong combined = (ulong)h1 + (ulong)i * (ulong)h2;
        uint bit_idx = (uint)(combined % (ulong)m_bits);
        
        uint word_idx = bit_idx >> 5;
        uint bit_mask = 1u << (bit_idx & 31u);
        atomic_fetch_or_explicit(&bits[word_idx], bit_mask, memory_order_relaxed);
    }
}

// QUERY KERNEL
kernel void bloom_query(
    const device uchar *items      [[buffer(0)]],
    constant uint &item_count      [[buffer(1)]],
    const device uint *bits        [[buffer(2)]],
    constant uint &m_bits          [[buffer(3)]],
    constant uint &k_hashes        [[buffer(4)]],
    device uint *results           [[buffer(5)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= item_count) return;
    
    const device uchar *key = items + (gid * 20); // RIPEMD160 hash is 20 bytes long
    
    uint h1, h2;
    hash_pair_fnv(key, 5, h1, h2); // RIPEMD160 hash is 5 UInt32 long
    
    for (uint i = 0; i < k_hashes; i++) {
        ulong combined = (ulong)h1 + (ulong)i * (ulong)h2;
        uint bit_idx = (uint)(combined % (ulong)m_bits);
        
        uint word_idx = bit_idx >> 5;
        uint bit_mask = 1u << (bit_idx & 31u);
        
        if ((bits[word_idx] & bit_mask) == 0u) {
            results[gid] = 0u;
            return;
        }
    }
    results[gid] = 1u;
}
