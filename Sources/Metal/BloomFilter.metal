
#include <metal_stdlib>
using namespace metal;

// Insertions are thread safe and could be done in parallell.
// Queries are also thread safe.
// The only scenario which wouldn't be thread safe is, if there are insertions happening at the same time when we query (which we don't do in this app)


// Load 32-bit value (assumes aligned access)
inline uint load32(const device uchar *p, uint idx) {
    return ((const device uint*)p)[idx];
}


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








// NEW: same logic, but works directly on thread-local uint[5] (RIPEMD output)
inline void hash_pair_fnv_words(const thread uint *words,
                                uint len_u32,
                                thread uint &h1,
                                thread uint &h2)
{
    uint x1 = 0x811C9DC5u;  // standard FNV offset
    uint x2 = 0xABC98388u;  // distinct seed

    for (uint i = 0; i < len_u32; i++) {
        uint val = words[i];
        x1 = (x1 ^ val) * 0x01000193u;
        x2 ^= val + 0x9E3779B9u + (x2 << 6) + (x2 >> 2);
    }

    h1 = fmix32(x1);
    h2 = fmix32(x2) | 1u;   // ensure odd
}



// Index computation from pre-final RIPEMD160[5]
inline void bloom_indices(const thread uint hash[5],
                                   constant uint &mask,
                                   thread uint idx[5])
{
    uint h5 = hash[0] + hash[1] + hash[2] + hash[3] + hash[4];

    idx[0] = ((hash[0] << 6u) | (h5 & 0x3fu))        & mask;
    idx[1] = ((hash[1] << 6u) | ((h5 >> 6u) & 0x3fu))  & mask;
    idx[2] = ((hash[2] << 6u) | ((h5 >> 12u) & 0x3fu)) & mask;
    idx[3] = ((hash[3] << 6u) | ((h5 >> 18u) & 0x3fu)) & mask;
    idx[4] = ((hash[4] << 6u) | ((h5 >> 24u) & 0x3fu)) & mask;
}

// Insert (set) 5 bits for this hash into the bloom bit-array
inline void bloom_insert(const thread uint hash[5],
                                  device atomic_uint *bits,
                                  constant uint &mask)
{
    uint idx[5];
    bloom_indices(hash, mask, idx);

    for (uint i = 0; i < 5; ++i) {
        uint bit = idx[i];
        uint word_idx = bit >> 5;
        uint bit_mask = 1u << (bit & 31u);
        atomic_fetch_or_explicit(&bits[word_idx], bit_mask, memory_order_relaxed);
    }
}

// Query: return true if ALL 5 bits are set
inline bool bloom_contains(const thread uint hash[5],
                                    const device uint *bits,
                                    constant uint &mask)
{
    uint idx[5];
    bloom_indices(hash, mask, idx);

    for (uint i = 0; i < 5; ++i) {
        uint bit = idx[i];
        uint word_idx = bit >> 5;
        uint bit_mask = 1u << (bit & 31u);

        if ((bits[word_idx] & bit_mask) == 0u) {
            return false;
        }
    }
    return true;
}
