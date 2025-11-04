#include <metal_stdlib>
using namespace metal;

/*
  RIPEMD-160 (single-block, fixed-32-byte messages) — Metal kernel.

  - Each message is exactly 32 bytes long (little-endian) (no variable-length support).
    The kernel pads each message into one 64-byte block (32 bytes message +
    0x80 padding byte + zeros + 8-byte little-endian bit-length). For 32 bytes,
    bit-length = 32 * 8 = 256 (0x00000100).
  - Because each padded message fits in a single 512-bit block, the kernel
    processes exactly one block per thread and executes a fully-unrolled
    RIPEMD-160 compression function for maximum throughput.
  - One thread per message. The message memory layout on the host is
    contiguous 32-byte messages (no per-message metadata needed).
  - The kernel uses threadgroup memory to store a few constant arrays copied
    once per threadgroup (first thread) to reduce constant fetch pressure.
  - Output: 5 uint32 words per message (in host endian). The host should
    convert to bytes / hex as appropriate (RIPEMD uses little-endian word order).
*/

inline uint rol(uint x, uint n) {
    return (x << n) | (x >> (32u - n));
}

// RIPEMD-160 primitive functions
inline uint F1(uint x, uint y, uint z) { return x ^ y ^ z; }
inline uint F2(uint x, uint y, uint z) { return (z ^ (x & (y ^ z))); }
inline uint F3(uint x, uint y, uint z) { return ((x | ~y) ^ z); }
inline uint F4(uint x, uint y, uint z) { return (y ^ (z & (x ^ y))); }
inline uint F5(uint x, uint y, uint z) { return (x ^ (y | ~z)); }

// We'll provide rotation counts & order constants in 'constant' arrays,
// then copy them to threadgroup memory once per threadgroup.

constant uint LEFT_ROT[80] = {
    // rotation counts for left line (rounds 1..5; 16 each)
    11,14,15,12,5,8,7,9,11,13,14,15,6,7,9,8, // r1
    7,6,8,13,11,9,7,15,7,12,15,9,11,7,13,12, // r2
    11,13,6,7,14,9,13,15,14,8,13,6,5,12,7,5, // r3
    11,12,14,15,14,15,9,8,9,14,5,6,8,6,5,12, // r4
    9,15,5,11,6,8,13,12,5,12,13,14,11,8,5,6  // r5
};

constant uint RIGHT_ROT[80] = {
    // rotation counts for right line (rounds 1..5)
    8,9,9,11,13,15,15,5,7,7,8,11,14,14,12,6,
    9,13,15,7,12,8,9,11,7,7,12,7,6,15,13,11,
    9,7,15,11,8,6,6,14,12,13,5,14,13,13,7,5,
    15,5,8,11,14,14,6,14,6,9,12,9,12,5,15,8,
    8,5,12,9,12,5,14,6,8,13,6,5,15,13,11,11
};

// Orderings: message word indices for left and right lines
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


// Kernel: one thread per fixed-32-byte message.
// Input buffer layout: messages are contiguous blocks of exactly 32 bytes each in big-endian
// Output: outWords[gid*5 + 0..4] = resulting 5 uint words for that message.
kernel void ripemd160_fixed32_kernel(
    const device uchar *       messages        [[ buffer(0) ]],
    device uint *              outWords        [[ buffer(1) ]],
    uint                       gid             [[ thread_position_in_grid ]],
    uint                       tid_in_tg       [[ thread_index_in_threadgroup ]],
    uint                       tg_size         [[ threads_per_threadgroup ]])
{

    // Copy constant arrays into threadgroup memory once per threadgroup
    threadgroup uint tgLeftRot[80];
    threadgroup uint tgRightRot[80];
    threadgroup uint tgLeftIdx[80];
    threadgroup uint tgRightIdx[80];
    threadgroup uint tgKLeft[5];
    threadgroup uint tgKRight[5];

    // first thread in threadgroup copies constants
    if (tid_in_tg == 0u) {
        // rotations
        for (uint i = 0; i < 80; ++i) {
            tgLeftRot[i] = LEFT_ROT[i];
            tgRightRot[i] = RIGHT_ROT[i];
            tgLeftIdx[i] = LEFT_IDX[i];
            tgRightIdx[i] = RIGHT_IDX[i];
        }
        // Ks
        for (uint r = 0; r < 5; ++r) {
            tgKLeft[r] = K_LEFT[r];
            tgKRight[r] = K_RIGHT[r];
        }
    }
    // ensure all threads see the copied data
    threadgroup_barrier(mem_flags::mem_threadgroup);

    // Build X[0..15] for a single padded block:
    // For fixed 32-byte message m[0..31]:
    // - X[0..7] = little-endian words from m[0..31]
    // - X[8] = 0x00000080  (first padding byte 0x80 at byte index 32 => LSB of word 8)
    // - X[9..13] = 0
    // - X[14] = 32*8 = 256 (little-endian low 4 bytes)
    // - X[15] = 0
    uint X[16];

    // compute message base offset (32 bytes per message)
    uint base = gid * 32u;

    // Read 8 words (big-endian pack)
    for (uint w = 0; w < 8u; ++w) {
        uint b0 = (uint)messages[base + w*4u + 0u];
        uint b1 = (uint)messages[base + w*4u + 1u];
        uint b2 = (uint)messages[base + w*4u + 2u];
        uint b3 = (uint)messages[base + w*4u + 3u];
        //X[w] = (b0 << 24u) | (b1 << 16u) | (b2 << 8u) | (b3); // big-endian
        X[w] = (b0) | (b1 << 8u) | (b2 << 16u) | (b3 << 24u); // little-endian
    }
     
    // padding and length (fixed for 32-byte messages)
    X[8]  = 0x00000080u;
    X[9]  = 0u;
    X[10] = 0u;
    X[11] = 0u;
    X[12] = 0u;
    X[13] = 0u;
    X[14] = 256u; // 32 bytes * 8 = 256 -> little-endian first word is 256
    X[15] = 0u;

    // Initialize working variables (RIPEMD-160 initial state)
    uint h0 = 0x67452301u;
    uint h1 = 0xEFCDAB89u;
    uint h2 = 0x98BADCFEu;
    uint h3 = 0x10325476u;
    uint h4 = 0xC3D2E1F0u;

    // local working vars (left and right lines)
    uint a = h0, b = h1, c = h2, d = h3, e = h4;
    uint aa = h0, bb = h1, cc = h2, dd = h3, ee = h4;

    // Because we want maximum throughput, and to follow your request,
    // we unroll the 80 steps and fetch rotation/index constants from tg memory.

    // Step macro-like inline expansion: compute step for left line
    #define LSTEP(i, f, Kidx) \
        do { \
            uint tmp = a + f(b,c,d) + X[tgLeftIdx[i]] + tgKLeft[Kidx]; \
            tmp = rol(tmp, tgLeftRot[i]); \
            tmp += e; \
            a = e; \
            e = d; \
            d = rol(c, 10u); \
            c = b; \
            b = tmp; \
        } while (0)

    // Step macro-like inline expansion: compute step for right line
    #define RSTEP(i, f, Kidx) \
        do { \
            uint tmp2 = aa + f(bb,cc,dd) + X[tgRightIdx[i]] + tgKRight[Kidx]; \
            tmp2 = rol(tmp2, tgRightRot[i]); \
            tmp2 += ee; \
            aa = ee; \
            ee = dd; \
            dd = rol(cc, 10u); \
            cc = bb; \
            bb = tmp2; \
        } while (0)

    // Now execute 80 steps (explicit grouping by round for clarity).
    // Round 1 (i 0..15) - functions: F1 / F5 on right etc.
    // Left uses F1 with K_LEFT[0] (which is 0)
    LSTEP(0,  F1, 0);  LSTEP(1,  F1, 0);  LSTEP(2,  F1, 0);  LSTEP(3,  F1, 0);
    LSTEP(4,  F1, 0);  LSTEP(5,  F1, 0);  LSTEP(6,  F1, 0);  LSTEP(7,  F1, 0);
    LSTEP(8,  F1, 0);  LSTEP(9,  F1, 0);  LSTEP(10, F1, 0);  LSTEP(11, F1, 0);
    LSTEP(12, F1, 0);  LSTEP(13, F1, 0);  LSTEP(14, F1, 0);  LSTEP(15, F1, 0);

    // Right round 1 uses F5 and K_RIGHT[0]
    RSTEP(0, F5, 0);  RSTEP(1, F5, 0);  RSTEP(2, F5, 0);  RSTEP(3, F5, 0);
    RSTEP(4, F5, 0);  RSTEP(5, F5, 0);  RSTEP(6, F5, 0);  RSTEP(7, F5, 0);
    RSTEP(8, F5, 0);  RSTEP(9, F5, 0);  RSTEP(10,F5, 0);  RSTEP(11,F5, 0);
    RSTEP(12,F5, 0);  RSTEP(13,F5, 0);  RSTEP(14,F5, 0);  RSTEP(15,F5, 0);

    // Round 2 (i 16..31)
    // Left uses F2 and K_LEFT[1]
    LSTEP(16, F2, 1); LSTEP(17, F2, 1); LSTEP(18, F2, 1); LSTEP(19, F2, 1);
    LSTEP(20, F2, 1); LSTEP(21, F2, 1); LSTEP(22, F2, 1); LSTEP(23, F2, 1);
    LSTEP(24, F2, 1); LSTEP(25, F2, 1); LSTEP(26, F2, 1); LSTEP(27, F2, 1);
    LSTEP(28, F2, 1); LSTEP(29, F2, 1); LSTEP(30, F2, 1); LSTEP(31, F2, 1);

    // Right round 2 uses F4 and K_RIGHT[1]
    RSTEP(16, F4, 1); RSTEP(17, F4, 1); RSTEP(18, F4, 1); RSTEP(19, F4, 1);
    RSTEP(20, F4, 1); RSTEP(21, F4, 1); RSTEP(22, F4, 1); RSTEP(23, F4, 1);
    RSTEP(24, F4, 1); RSTEP(25, F4, 1); RSTEP(26, F4, 1); RSTEP(27, F4, 1);
    RSTEP(28, F4, 1); RSTEP(29, F4, 1); RSTEP(30, F4, 1); RSTEP(31, F4, 1);

    // Round 3 (i 32..47)
    LSTEP(32, F3, 2); LSTEP(33, F3, 2); LSTEP(34, F3, 2); LSTEP(35, F3, 2);
    LSTEP(36, F3, 2); LSTEP(37, F3, 2); LSTEP(38, F3, 2); LSTEP(39, F3, 2);
    LSTEP(40, F3, 2); LSTEP(41, F3, 2); LSTEP(42, F3, 2); LSTEP(43, F3, 2);
    LSTEP(44, F3, 2); LSTEP(45, F3, 2); LSTEP(46, F3, 2); LSTEP(47, F3, 2);

    RSTEP(32, F3, 2); RSTEP(33, F3, 2); RSTEP(34, F3, 2); RSTEP(35, F3, 2);
    RSTEP(36, F3, 2); RSTEP(37, F3, 2); RSTEP(38, F3, 2); RSTEP(39, F3, 2);
    RSTEP(40, F3, 2); RSTEP(41, F3, 2); RSTEP(42, F3, 2); RSTEP(43, F3, 2);
    RSTEP(44, F3, 2); RSTEP(45, F3, 2); RSTEP(46, F3, 2); RSTEP(47, F3, 2);

    // Round 4 (i 48..63)
    LSTEP(48, F4, 3); LSTEP(49, F4, 3); LSTEP(50, F4, 3); LSTEP(51, F4, 3);
    LSTEP(52, F4, 3); LSTEP(53, F4, 3); LSTEP(54, F4, 3); LSTEP(55, F4, 3);
    LSTEP(56, F4, 3); LSTEP(57, F4, 3); LSTEP(58, F4, 3); LSTEP(59, F4, 3);
    LSTEP(60, F4, 3); LSTEP(61, F4, 3); LSTEP(62, F4, 3); LSTEP(63, F4, 3);

    RSTEP(48, F2, 3); RSTEP(49, F2, 3); RSTEP(50, F2, 3); RSTEP(51, F2, 3);
    RSTEP(52, F2, 3); RSTEP(53, F2, 3); RSTEP(54, F2, 3); RSTEP(55, F2, 3);
    RSTEP(56, F2, 3); RSTEP(57, F2, 3); RSTEP(58, F2, 3); RSTEP(59, F2, 3);
    RSTEP(60, F2, 3); RSTEP(61, F2, 3); RSTEP(62, F2, 3); RSTEP(63, F2, 3);

    // Round 5 (i 64..79)
    LSTEP(64, F5, 4); LSTEP(65, F5, 4); LSTEP(66, F5, 4); LSTEP(67, F5, 4);
    LSTEP(68, F5, 4); LSTEP(69, F5, 4); LSTEP(70, F5, 4); LSTEP(71, F5, 4);
    LSTEP(72, F5, 4); LSTEP(73, F5, 4); LSTEP(74, F5, 4); LSTEP(75, F5, 4);
    LSTEP(76, F5, 4); LSTEP(77, F5, 4); LSTEP(78, F5, 4); LSTEP(79, F5, 4);

    RSTEP(64, F1, 4); RSTEP(65, F1, 4); RSTEP(66, F1, 4); RSTEP(67, F1, 4);
    RSTEP(68, F1, 4); RSTEP(69, F1, 4); RSTEP(70, F1, 4); RSTEP(71, F1, 4);
    RSTEP(72, F1, 4); RSTEP(73, F1, 4); RSTEP(74, F1, 4); RSTEP(75, F1, 4);
    RSTEP(76, F1, 4); RSTEP(77, F1, 4); RSTEP(78, F1, 4); RSTEP(79, F1, 4);

    // Final combination (as per RIPEMD-160 spec)
    uint t = h1 + c + dd;
    h1 = h2 + d + ee;
    h2 = h3 + e + aa;
    h3 = h4 + a + bb;
    h4 = h0 + b + cc;
    h0 = t;

    // Write output words (host can convert to bytes / hex).
    uint dst = gid * 5u;
    
    outWords[dst + 0u] = h0;
    outWords[dst + 1u] = h1;
    outWords[dst + 2u] = h2;
    outWords[dst + 3u] = h3;
    outWords[dst + 4u] = h4;
    

    

    // Undef macros
    #undef LSTEP
    #undef RSTEP
}
