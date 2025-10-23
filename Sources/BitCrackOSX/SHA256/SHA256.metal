//
//  SHA256.metal
//  OsxBitCrack
//
//  Created by Mat on 18.10.2025.
//

#include <metal_stdlib>
using namespace metal;


// Maximum allowed message length in bytes per-message
// Keep reasonable; increase if you need longer messages.
#define MAX_MSG_BYTES 1024  // TODO: reduce this to the exact number of bytes but be aware this includes the meta

// SHA-256 constants
constant uint K[64] = {
    0x428a2f98u,0x71374491u,0xb5c0fbcfu,0xe9b5dba5u,0x3956c25bu,0x59f111f1u,0x923f82a4u,0xab1c5ed5u,
    0xd807aa98u,0x12835b01u,0x243185beu,0x550c7dc3u,0x72be5d74u,0x80deb1feu,0x9bdc06a7u,0xc19bf174u,
    0xe49b69c1u,0xefbe4786u,0x0fc19dc6u,0x240ca1ccu,0x2de92c6fu,0x4a7484aau,0x5cb0a9dcu,0x76f988dau,
    0x983e5152u,0xa831c66du,0xb00327c8u,0xbf597fc7u,0xc6e00bf3u,0xd5a79147u,0x06ca6351u,0x14292967u,
    0x27b70a85u,0x2e1b2138u,0x4d2c6dfcu,0x53380d13u,0x650a7354u,0x766a0abbu,0x81c2c92eu,0x92722c85u,
    0xa2bfe8a1u,0xa81a664bu,0xc24b8b70u,0xc76c51a3u,0xd192e819u,0xd6990624u,0xf40e3585u,0x106aa070u,
    0x19a4c116u,0x1e376c08u,0x2748774cu,0x34b0bcb5u,0x391c0cb3u,0x4ed8aa4au,0x5b9cca4fu,0x682e6ff3u,
    0x748f82eeu,0x78a5636fu,0x84c87814u,0x8cc70208u,0x90befffau,0xa4506cebu,0xbef9a3f7u,0xc67178f2u
};

inline uint rotr(uint x, uint n) {
    return (x >> n) | (x << (32 - n));
}

inline uint Ch(uint x, uint y, uint z) {
    return (x & y) ^ ((~x) & z);
}
inline uint Maj(uint x, uint y, uint z) {
    return (x & y) ^ (x & z) ^ (y & z);
}
inline uint Sigma0(uint x) {
    return rotr(x, 2) ^ rotr(x,13) ^ rotr(x,22);
}
inline uint Sigma1(uint x) {
    return rotr(x, 6) ^ rotr(x,11) ^ rotr(x,25);
}
inline uint sigma0(uint x) {
    return rotr(x, 7) ^ rotr(x,18) ^ (x >> 3);
}
inline uint sigma1(uint x) {
    return rotr(x,17) ^ rotr(x,19) ^ (x >> 10);
}

// meta format: struct { uint offset; uint length; }
struct MsgMeta {
    uint offset;
    uint length;
};

struct NumMessages {
    uint value;
};

kernel void sha256_batch_kernel(
    const device uchar*         messages       [[ buffer(0) ]],
    const device MsgMeta*       metas          [[ buffer(1) ]],
    device uint*                outHashes      [[ buffer(2) ]],
    const device NumMessages*   numMsgPtr      [[ buffer(3) ]],
    uint                        gid            [[ thread_position_in_grid ]]
)
{
    uint numMessages = numMsgPtr->value;
    if (gid >= numMessages) return;

    // read offset and length
    MsgMeta m = metas[gid];
    uint offset = m.offset;
    uint length = m.length;
    if (length > MAX_MSG_BYTES) {
        // clamp length if too long (should be prevented by host)
        length = MAX_MSG_BYTES;
    }

    // compute number of 512-bit blocks after padding
    // padding: 1 byte 0x80, then zeroes, then 8-byte big-endian length (bits)
    uint64_t bitLen = (uint64_t)length * 8ull;
    uint paddedLen = (uint)((((length + 9) + 63) / 64) * 64); // in bytes
    uint numBlocks = paddedLen / 64;

    // initial hash values
    uint a0 = 0x6a09e667u;
    uint b0 = 0xbb67ae85u;
    uint c0 = 0x3c6ef372u;
    uint d0 = 0xa54ff53au;
    uint e0 = 0x510e527fu;
    uint f0 = 0x9b05688cu;
    uint g0 = 0x1f83d9abu;
    uint h0 = 0x5be0cd19u;

    // Work buffer
    uint W[64];

    for (uint blockIdx = 0; blockIdx < numBlocks; ++blockIdx) {
        // Build W[0..15] from 64 bytes (big-endian)
        uint baseByteIndex = blockIdx * 64;
        for (uint t = 0; t < 16; ++t) {
            uint w = 0u;
            for (uint j = 0; j < 4; ++j) {
                uint globalByteIndex = baseByteIndex + t*4 + j;
                uchar b = 0u;
                if (globalByteIndex < length) {
                    b = messages[offset + globalByteIndex];
                } else if (globalByteIndex == length) {
                    b = 0x80u;
                } else if (globalByteIndex >= (paddedLen - 8)) {
                    // last 8 bytes: big-endian bit length
                    uint idxFromEnd = globalByteIndex - (paddedLen - 8); // 0..7
                    uint shift = (7 - idxFromEnd) * 8;
                    b = (uchar)((bitLen >> shift) & 0xFFu);
                } else {
                    b = 0u;
                }
                w = (w << 8) | (uint)b;
            }
            W[t] = w;
        }

        // Extend W
        for (uint t = 16; t < 64; ++t) {
            uint s0 = sigma0(W[t-15]);
            uint s1 = sigma1(W[t-2]);
            W[t] = W[t-16] + s0 + W[t-7] + s1;
        }

        // Initialize working vars
        uint a = a0;
        uint b = b0;
        uint c = c0;
        uint d = d0;
        uint e = e0;
        uint f = f0;
        uint g = g0;
        uint h = h0;

        // Main compression
        for (uint t = 0; t < 64; ++t) {
            uint T1 = h + Sigma1(e) + Ch(e,f,g) + K[t] + W[t];
            uint T2 = Sigma0(a) + Maj(a,b,c);
            h = g;
            g = f;
            f = e;
            e = d + T1;
            d = c;
            c = b;
            b = a;
            a = T1 + T2;
        }

        // Add this chunk's hash to result so far:
        a0 += a;
        b0 += b;
        c0 += c;
        d0 += d;
        e0 += e;
        f0 += f;
        g0 += g;
        h0 += h;
    }

    // write final hash to out buffer: 8 uints per message
    uint dstIndex = gid * 8u;
    outHashes[dstIndex + 0u] = a0;
    outHashes[dstIndex + 1u] = b0;
    outHashes[dstIndex + 2u] = c0;
    outHashes[dstIndex + 3u] = d0;
    outHashes[dstIndex + 4u] = e0;
    outHashes[dstIndex + 5u] = f0;
    outHashes[dstIndex + 6u] = g0;
    outHashes[dstIndex + 7u] = h0;
}
