#include <metal_stdlib>
using namespace metal;

// ==========================
// SHA-256 SECTION
// ==========================

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

struct SHA256Constants {
    uint numMessages;
    uint messageSize;
};


inline void sha256(
    const device uchar* messages,
    uint offset,
    uint msgLen,
    thread uint outState[8]
)
{
    // compute number of 512-bit blocks after padding
    uint64_t bitLen = (uint64_t)msgLen * 8ull;
    uint paddedLen  = (uint)((((msgLen + 9) + 63) / 64) * 64);
    uint numBlocks  = paddedLen / 64;

    // initial hash values
    uint a0 = 0x6a09e667u;
    uint b0 = 0xbb67ae85u;
    uint c0 = 0x3c6ef372u;
    uint d0 = 0xa54ff53au;
    uint e0 = 0x510e527fu;
    uint f0 = 0x9b05688cu;
    uint g0 = 0x1f83d9abu;
    uint h0 = 0x5be0cd19u;

    uint W[64];

    for (uint blockIdx = 0; blockIdx < numBlocks; ++blockIdx)
    {
        uint baseByteIndex = blockIdx * 64;

        // Build W[0..15]
        for (uint t = 0; t < 16; ++t) {
            uint w = 0u;

            for (uint j = 0; j < 4; ++j) {
                uint globalByteIndex = baseByteIndex + t*4 + j;
                uchar b = 0u;

                if (globalByteIndex < msgLen) {
                    b = messages[offset + globalByteIndex];
                }
                else if (globalByteIndex == msgLen) {
                    b = 0x80u;
                }
                else if (globalByteIndex >= (paddedLen - 8)) {
                    uint idxFromEnd = globalByteIndex - (paddedLen - 8);
                    uint shift = (7u - idxFromEnd) * 8u;
                    b = (uchar)((bitLen >> shift) & 0xFFu);
                }
                else {
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

        // Working variables
        uint a = a0;
        uint b = b0;
        uint c_ = c0;
        uint d = d0;
        uint e = e0;
        uint f = f0;
        uint g = g0;
        uint h = h0;

        // Compression
        for (uint t = 0; t < 64; ++t) {
            uint T1 = h + Sigma1(e) + Ch(e,f,g) + K[t] + W[t];
            uint T2 = Sigma0(a) + Maj(a,b,c_);
            h = g;
            g = f;
            f = e;
            e = d + T1;
            d = c_;
            c_ = b;
            b = a;
            a = T1 + T2;
        }

        // Add to state
        a0 += a;
        b0 += b;
        c0 += c_;
        d0 += d;
        e0 += e;
        f0 += f;
        g0 += g;
        h0 += h;
    }

    // Output 8 final words (still big-endian word values)
    outState[0] = a0;
    outState[1] = b0;
    outState[2] = c0;
    outState[3] = d0;
    outState[4] = e0;
    outState[5] = f0;
    outState[6] = g0;
    outState[7] = h0;
}
