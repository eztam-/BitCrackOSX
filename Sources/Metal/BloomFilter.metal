
#include <metal_stdlib>
using namespace metal;

// Queries are thread safe.
// The only scenario which wouldn't be thread safe is, if there are insertions happening at the same time when we query (which we don't do in this app)


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
