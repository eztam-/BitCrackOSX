//
//  SHA256_RIPEMD160.metal
//  OsxBitCrack
//
//  Combined SHA-256 + RIPEMD-160 (hash160)
//

#include <metal_stdlib>
using namespace metal;

// Maximum allowed message length in bytes per-message
// Keep reasonable; increase if you need longer messages.
#define MAX_MSG_BYTES 1024  // TODO: Better remove this check?

// For conversion to little-endian
#define BYTESWAP32(x) (((x & 0x000000FFu) << 24u) | \
                       ((x & 0x0000FF00u) << 8u)  | \
                       ((x & 0x00FF0000u) >> 8u)  | \
                       ((x & 0xFF000000u) >> 24u))

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

// ==========================
// RIPEMD-160 SECTION
// (adapted to work on an in-register 32-byte message: 8 uint words)
// ==========================

inline uint rol(uint x, uint n) {
    return (x << n) | (x >> (32u - n));
}

// RIPEMD-160 primitive functions
inline uint F1(uint x, uint y, uint z) { return x ^ y ^ z; }
inline uint F2(uint x, uint y, uint z) { return (z ^ (x & (y ^ z))); }
inline uint F3(uint x, uint y, uint z) { return ((x | ~y) ^ z); }
inline uint F4(uint x, uint y, uint z) { return (y ^ (z & (x ^ y))); }
inline uint F5(uint x, uint y, uint z) { return (x ^ (y | ~z)); }

// Rotation counts for left / right lines
constant uint LEFT_ROT[80] = {
    11,14,15,12,5,8,7,9,11,13,14,15,6,7,9,8,
    7,6,8,13,11,9,7,15,7,12,15,9,11,7,13,12,
    11,13,6,7,14,9,13,15,14,8,13,6,5,12,7,5,
    11,12,14,15,14,15,9,8,9,14,5,6,8,6,5,12,
    9,15,5,11,6,8,13,12,5,12,13,14,11,8,5,6
};

constant uint RIGHT_ROT[80] = {
    8,9,9,11,13,15,15,5,7,7,8,11,14,14,12,6,
    9,13,15,7,12,8,9,11,7,7,12,7,6,15,13,11,
    9,7,15,11,8,6,6,14,12,13,5,14,13,13,7,5,
    15,5,8,11,14,14,6,14,6,9,12,9,12,5,15,8,
    8,5,12,9,12,5,14,6,8,13,6,5,15,13,11,11
};

constant uint LEFT_IDX[80] = {
    0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,
    7,4,13,1,10,6,15,3,12,0,9,5,2,14,11,8,
    3,10,14,4,9,15,8,1,2,7,0,6,13,11,5,12,
    1,9,11,10,0,8,12,4,13,3,7,15,14,5,6,2,
    4,0,5,9,7,12,2,10,14,1,3,8,11,6,15,13
};

constant uint RIGHT_IDX[80] = {
    5,14,7,0,9,2,11,4,13,6,15,8,1,10,3,12,
    6,11,3,7,0,13,5,10,14,15,8,12,4,9,1,2,
    15,5,1,3,7,14,6,9,11,8,12,2,10,0,4,13,
    8,6,4,1,3,11,15,0,5,12,2,13,9,7,10,14,
    12,15,10,4,1,5,8,7,6,2,13,14,0,3,9,11
};

// Left-side additive constants per round
constant uint K_LEFT[5]  = { 0x00000000u, 0x5A827999u, 0x6ED9EBA1u, 0x8F1BBCDCu, 0xA953FD4Eu };
// Right-side additive constants per round
constant uint K_RIGHT[5] = { 0x50A28BE6u, 0x5C4DD124u, 0x6D703EF3u, 0x7A6D76E9u, 0x00000000u };

// Compute RIPEMD-160 for a fixed 32-byte message provided as 8 little-endian uints.
//
// inWords[0..7] : 8 little-endian words (e.g. BYTESWAP32 of SHA-256 state words)
// outWords[0..4]: RIPEMD-160 output words (little-endian, standard RIPEMD ordering)
inline void ripemd160(const thread uint inWords[8],
                             thread uint outWords[5])
{
    // Build X[0..15] for a single padded block:
    //  - X[0..7]  = message words (32-byte msg)
    //  - X[8]     = 0x00000080
    //  - X[9..13] = 0
    //  - X[14]    = 32 * 8 = 256
    //  - X[15]    = 0
    uint X[16];

    for (uint w = 0; w < 8u; ++w) {
        // SHA256 produces big-endian words.
        // RIPEMD expects little-endian words.
        // Convert here, ONCE, automatically:
        X[w] = ((inWords[w] >> 24) & 0x000000FFu) |
               ((inWords[w] >> 8)  & 0x0000FF00u) |
               ((inWords[w] << 8)  & 0x00FF0000u) |
               ((inWords[w] << 24) & 0xFF000000u);
    }
    X[8]  = 0x00000080u;
    X[9]  = 0u;
    X[10] = 0u;
    X[11] = 0u;
    X[12] = 0u;
    X[13] = 0u;
    X[14] = 256u; // 32 bytes * 8 = 256
    X[15] = 0u;

    // Initialize working variables (RIPEMD-160 initial state)
    uint h0 = 0x67452301u;
    uint h1 = 0xEFCDAB89u;
    uint h2 = 0x98BADCFEu;
    uint h3 = 0x10325476u;
    uint h4 = 0xC3D2E1F0u;

    uint a = h0, b = h1, c = h2, d = h3, e = h4;
    uint aa = h0, bb = h1, cc = h2, dd = h3, ee = h4;

    #define LSTEP(i, f, Kidx) \
        do { \
            uint tmp = a + f(b,c,d) + X[LEFT_IDX[i]] + K_LEFT[Kidx]; \
            tmp = rol(tmp, LEFT_ROT[i]); \
            tmp += e; \
            a = e; \
            e = d; \
            d = rol(c, 10u); \
            c = b; \
            b = tmp; \
        } while (0)

    #define RSTEP(i, f, Kidx) \
        do { \
            uint tmp2 = aa + f(bb,cc,dd) + X[RIGHT_IDX[i]] + K_RIGHT[Kidx]; \
            tmp2 = rol(tmp2, RIGHT_ROT[i]); \
            tmp2 += ee; \
            aa = ee; \
            ee = dd; \
            dd = rol(cc, 10u); \
            cc = bb; \
            bb = tmp2; \
        } while (0)

    // 80 rounds, grouped as in your original code

    // Round 1 (0..15)
    LSTEP(0,  F1, 0);  LSTEP(1,  F1, 0);  LSTEP(2,  F1, 0);  LSTEP(3,  F1, 0);
    LSTEP(4,  F1, 0);  LSTEP(5,  F1, 0);  LSTEP(6,  F1, 0);  LSTEP(7,  F1, 0);
    LSTEP(8,  F1, 0);  LSTEP(9,  F1, 0);  LSTEP(10, F1, 0);  LSTEP(11, F1, 0);
    LSTEP(12, F1, 0);  LSTEP(13, F1, 0);  LSTEP(14, F1, 0);  LSTEP(15, F1, 0);

    RSTEP(0, F5, 0);   RSTEP(1, F5, 0);   RSTEP(2, F5, 0);   RSTEP(3, F5, 0);
    RSTEP(4, F5, 0);   RSTEP(5, F5, 0);   RSTEP(6, F5, 0);   RSTEP(7, F5, 0);
    RSTEP(8, F5, 0);   RSTEP(9, F5, 0);   RSTEP(10,F5, 0);   RSTEP(11,F5, 0);
    RSTEP(12,F5, 0);   RSTEP(13,F5, 0);   RSTEP(14,F5, 0);   RSTEP(15,F5, 0);

    // Round 2 (16..31)
    LSTEP(16, F2, 1);  LSTEP(17, F2, 1);  LSTEP(18, F2, 1);  LSTEP(19, F2, 1);
    LSTEP(20, F2, 1);  LSTEP(21, F2, 1);  LSTEP(22, F2, 1);  LSTEP(23, F2, 1);
    LSTEP(24, F2, 1);  LSTEP(25, F2, 1);  LSTEP(26, F2, 1);  LSTEP(27, F2, 1);
    LSTEP(28, F2, 1);  LSTEP(29, F2, 1);  LSTEP(30, F2, 1);  LSTEP(31, F2, 1);

    RSTEP(16, F4, 1);  RSTEP(17, F4, 1);  RSTEP(18, F4, 1);  RSTEP(19, F4, 1);
    RSTEP(20, F4, 1);  RSTEP(21, F4, 1);  RSTEP(22, F4, 1);  RSTEP(23, F4, 1);
    RSTEP(24, F4, 1);  RSTEP(25, F4, 1);  RSTEP(26, F4, 1);  RSTEP(27, F4, 1);
    RSTEP(28, F4, 1);  RSTEP(29, F4, 1);  RSTEP(30, F4, 1);  RSTEP(31, F4, 1);

    // Round 3 (32..47)
    LSTEP(32, F3, 2);  LSTEP(33, F3, 2);  LSTEP(34, F3, 2);  LSTEP(35, F3, 2);
    LSTEP(36, F3, 2);  LSTEP(37, F3, 2);  LSTEP(38, F3, 2);  LSTEP(39, F3, 2);
    LSTEP(40, F3, 2);  LSTEP(41, F3, 2);  LSTEP(42, F3, 2);  LSTEP(43, F3, 2);
    LSTEP(44, F3, 2);  LSTEP(45, F3, 2);  LSTEP(46, F3, 2);  LSTEP(47, F3, 2);

    RSTEP(32, F3, 2);  RSTEP(33, F3, 2);  RSTEP(34, F3, 2);  RSTEP(35, F3, 2);
    RSTEP(36, F3, 2);  RSTEP(37, F3, 2);  RSTEP(38, F3, 2);  RSTEP(39, F3, 2);
    RSTEP(40, F3, 2);  RSTEP(41, F3, 2);  RSTEP(42, F3, 2);  RSTEP(43, F3, 2);
    RSTEP(44, F3, 2);  RSTEP(45, F3, 2);  RSTEP(46, F3, 2);  RSTEP(47, F3, 2);

    // Round 4 (48..63)
    LSTEP(48, F4, 3);  LSTEP(49, F4, 3);  LSTEP(50, F4, 3);  LSTEP(51, F4, 3);
    LSTEP(52, F4, 3);  LSTEP(53, F4, 3);  LSTEP(54, F4, 3);  LSTEP(55, F4, 3);
    LSTEP(56, F4, 3);  LSTEP(57, F4, 3);  LSTEP(58, F4, 3);  LSTEP(59, F4, 3);
    LSTEP(60, F4, 3);  LSTEP(61, F4, 3);  LSTEP(62, F4, 3);  LSTEP(63, F4, 3);

    RSTEP(48, F2, 3);  RSTEP(49, F2, 3);  RSTEP(50, F2, 3);  RSTEP(51, F2, 3);
    RSTEP(52, F2, 3);  RSTEP(53, F2, 3);  RSTEP(54, F2, 3);  RSTEP(55, F2, 3);
    RSTEP(56, F2, 3);  RSTEP(57, F2, 3);  RSTEP(58, F2, 3);  RSTEP(59, F2, 3);
    RSTEP(60, F2, 3);  RSTEP(61, F2, 3);  RSTEP(62, F2, 3);  RSTEP(63, F2, 3);

    // Round 5 (64..79)
    LSTEP(64, F5, 4);  LSTEP(65, F5, 4);  LSTEP(66, F5, 4);  LSTEP(67, F5, 4);
    LSTEP(68, F5, 4);  LSTEP(69, F5, 4);  LSTEP(70, F5, 4);  LSTEP(71, F5, 4);
    LSTEP(72, F5, 4);  LSTEP(73, F5, 4);  LSTEP(74, F5, 4);  LSTEP(75, F5, 4);
    LSTEP(76, F5, 4);  LSTEP(77, F5, 4);  LSTEP(78, F5, 4);  LSTEP(79, F5, 4);

    RSTEP(64, F1, 4);  RSTEP(65, F1, 4);  RSTEP(66, F1, 4);  RSTEP(67, F1, 4);
    RSTEP(68, F1, 4);  RSTEP(69, F1, 4);  RSTEP(70, F1, 4);  RSTEP(71, F1, 4);
    RSTEP(72, F1, 4);  RSTEP(73, F1, 4);  RSTEP(74, F1, 4);  RSTEP(75, F1, 4);
    RSTEP(76, F1, 4);  RSTEP(77, F1, 4);  RSTEP(78, F1, 4);  RSTEP(79, F1, 4);

    // Final combination
    uint t = h1 + c + dd;
    h1 = h2 + d + ee;
    h2 = h3 + e + aa;
    h3 = h4 + a + bb;
    h4 = h0 + b + cc;
    h0 = t;

    outWords[0] = h0;
    outWords[1] = h1;
    outWords[2] = h2;
    outWords[3] = h3;
    outWords[4] = h4;

    #undef LSTEP
    #undef RSTEP
}



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


// ==========================
// Combined Kernel: SHA-256 -> RIPEMD-160
// ==========================
//
// Input:
//   buffer(0): messages (uchar*), numMessages * messageSize bytes
//   buffer(2): SHA256Constants { numMessages, messageSize }
//
// Output:
//   buffer(1): outHashes — 5 uint per message = RIPEMD-160(SHA256(msg))
//
kernel void sha256_ripemd160_batch_kernel(
    const device uchar*         messages       [[ buffer(0) ]],
    device uint*                outHashes      [[ buffer(1) ]],
    constant SHA256Constants&   c              [[ buffer(2) ]],
    uint                        gid            [[ thread_position_in_grid ]]
)
{
    if (gid >= c.numMessages) return;

    uint offset = gid * c.messageSize;

    // ---- SHA-256 ----
    uint shaState[8];
    sha256(messages, offset, c.messageSize, shaState);

    // ---- RIPEMD-160(SHA256(msg)) ----
    uint ripemdOut[5];
    ripemd160(shaState, ripemdOut);

    // ---- store output ----
    uint dst = gid * 5u;
    outHashes[dst + 0] = ripemdOut[0];
    outHashes[dst + 1] = ripemdOut[1];
    outHashes[dst + 2] = ripemdOut[2];
    outHashes[dst + 3] = ripemdOut[3];
    outHashes[dst + 4] = ripemdOut[4];
}

