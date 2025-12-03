//  Combined SHA-256 + RIPEMD-160 (hash160)
#include <metal_stdlib>
using namespace metal;

#include "SHA256.metal"
#include "RIPEMD160.metal"
#include "BloomFilter.metal"   // or wherever you put fmix32 + hash_pair_fnv_words


constant const uint NUMBER_HASHES = 20;

// Fused: SHA-256 -> RIPEMD-160 -> Bloom query
//
// Inputs:
//   buffer(0): messages          (uchar*)   numMessages * messageSize bytes
//   buffer(1): bits              (uint*)    bloom filter bit array
//   buffer(2): SHA256Constants   { numMessages, messageSize }
//   buffer(3): m_bits            (uint)     bloom bit count
//
// Outputs:
//   buffer(4): bloomResults      (uint*)    0 or 1 per message
//   buffer(5): outRipemd160      (uint*)    5 uints per message
//
kernel void sha256_ripemd160_bloom_query_kernel(
    const device uchar*         messages       [[ buffer(0) ]],
    const device uint*          bits           [[ buffer(1) ]],
    constant SHA256Constants&   c              [[ buffer(2) ]],
    constant uint&              m_bits         [[ buffer(3) ]],
    device uint*                bloomResults   [[ buffer(4) ]],
    device uint*                outRipemd160   [[ buffer(5) ]],
    uint                        gid            [[ thread_position_in_grid ]]
)
{
    if (gid >= c.numMessages) return;

    uint offset = gid * c.messageSize;

    // ---- SHA-256(message) ----
    uint shaState[8];
    sha256(messages, offset, c.messageSize, shaState);

    // ---- RIPEMD-160(SHA-256(message)) ----
    uint ripemdOut[5];
    ripemd160(shaState, ripemdOut);
    // ripemdOut now contains the 20-byte hash as 5×uint32

    // ---- Store RIPEMD-160 to output buffer ----
    {
        uint base = gid * 5u;
        outRipemd160[base + 0u] = ripemdOut[0];
        outRipemd160[base + 1u] = ripemdOut[1];
        outRipemd160[base + 2u] = ripemdOut[2];
        outRipemd160[base + 3u] = ripemdOut[3];
        outRipemd160[base + 4u] = ripemdOut[4];
    }

    // ---- Bloom query on ripemdOut ----
    uint h1, h2;
    hash_pair_fnv_words(ripemdOut, 5u, h1, h2);  // 5x uint32 = 20 bytes

    for (uint i = 0; i < NUMBER_HASHES; i++) {
        ulong combined = (ulong)h1 + (ulong)i * (ulong)h2;
        uint bit_idx = (uint)(combined % (ulong)m_bits);

        uint word_idx = bit_idx >> 5;
        uint bit_mask = 1u << (bit_idx & 31u);

        if ((bits[word_idx] & bit_mask) == 0u) {
            bloomResults[gid] = 0u;
            return;
        }
    }

    // If all bloom bits were set → mark as probable hit
    bloomResults[gid] = 1u;
}



// INSERT KERNEL
kernel void bloom_insert(
    const device uchar *items      [[buffer(0)]],
    constant uint &item_count      [[buffer(1)]],
    device atomic_uint *bits       [[buffer(2)]],
    constant uint &m_bits          [[buffer(3)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= item_count) return;
    
    const device uchar *key = items + (gid * 20); // RIPEMD160 hash is 20 bytes long
    
    uint h1, h2;
    hash_pair_fnv(key, 5, h1, h2); // RIPEMD160 hash is 5 UInt32 long
    
    for (uint i = 0; i < NUMBER_HASHES; i++) {
        // Matching Swift: (h1 + i * h2) % m_bits
        ulong combined = (ulong)h1 + (ulong)i * (ulong)h2;
        uint bit_idx = (uint)(combined % (ulong)m_bits);
        
        uint word_idx = bit_idx >> 5;
        uint bit_mask = 1u << (bit_idx & 31u);
        atomic_fetch_or_explicit(&bits[word_idx], bit_mask, memory_order_relaxed);
    }
}
