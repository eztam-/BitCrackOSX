#include <metal_stdlib>
using namespace metal;

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

#define ROTR(x,n) ((x >> n) | (x << (32 - n)))
#define Ch(x,y,z) (((x) & (y)) ^ (~(x) & (z)))
#define Maj(x,y,z) (((x) & (y)) ^ ((x) & (z)) ^ ((y) & (z)))

#define SIGMA0(x) (ROTR(x,2) ^ ROTR(x,13) ^ ROTR(x,22))
#define SIGMA1(x) (ROTR(x,6) ^ ROTR(x,11) ^ ROTR(x,25))
#define sigma0(x) (ROTR(x,7) ^ ROTR(x,18) ^ (x >> 3))
#define sigma1(x) (ROTR(x,17) ^ ROTR(x,19) ^ (x >> 10))

#define ROUND(a,b,c,d,e,f,g,h,w,k) \
    { uint T = Ch(e,f,g) + SIGMA1(e) + (k) + (w); \
      d += T + h; \
      h += T + Maj(a,b,c) + SIGMA0(a); }


// ====================================================================
//  SHA-256 for Compressed Public Key — 33 bytes
//  Input: x[8] limbs of X coordinate, yParity = 0/1
//  Output: digest[8] = SHA-256(X||prefix)
// ====================================================================


inline void sha256PublicKeyCompressed(
    thread const uint x[8],   // x[0] = LSW, x[7] = MSW
    uint yParity,
    thread uint digest[8]
)
{
    uint a = 0x6a09e667u;
    uint b = 0xbb67ae85u;
    uint c = 0x3c6ef372u;
    uint d = 0xa54ff53au;
    uint e = 0x510e527fu;
    uint f = 0x9b05688cu;
    uint g = 0x1f83d9abu;
    uint h = 0x5be0cd19u;

    uint w[16];

    // ----------------------------------------------------------------
    // Build first block for compressed pubkey:
    //   0x02/0x03 || X (big-endian)
    //
    // X is little-endian in limbs: x[0] = LSW ... x[7] = MSW.
    // This is the same mapping you *used* to get by pre-reversing
    // (xBE[i] = x[7 - i]). Now we just index that way directly.
    // ----------------------------------------------------------------

    // These are exactly your old formulas, but with x[7-i] instead of x[i].
    w[0] = (0x02000000u | ((yParity & 1u) << 24) | (x[7] >> 8));
    w[1] = (x[6] >> 8) | (x[7] << 24);
    w[2] = (x[5] >> 8) | (x[6] << 24);
    w[3] = (x[4] >> 8) | (x[5] << 24);
    w[4] = (x[3] >> 8) | (x[4] << 24);
    w[5] = (x[2] >> 8) | (x[3] << 24);
    w[6] = (x[1] >> 8) | (x[2] << 24);
    w[7] = (x[0] >> 8) | (x[1] << 24);

    // final byte of X (from LSW) + padding start
    w[8]  = (x[0] << 24) | 0x00800000u;

    // zeros except final length
    w[9]  = 0u;
    w[10] = 0u;
    w[11] = 0u;
    w[12] = 0u;
    w[13] = 0u;
    w[14] = 0u;
    w[15] = 264u; // 33 bytes × 8

    // ===================================================================
    // The rest of your function stays exactly the same:
    // Rounds, SCHED macro, digest add, etc.
    // ===================================================================

    // FIRST 16 ROUNDS
    ROUND(a,b,c,d,e,f,g,h, w[0], K[0]);
    ROUND(h,a,b,c,d,e,f,g, w[1], K[1]);
    ROUND(g,h,a,b,c,d,e,f, w[2], K[2]);
    ROUND(f,g,h,a,b,c,d,e, w[3], K[3]);
    ROUND(e,f,g,h,a,b,c,d, w[4], K[4]);
    ROUND(d,e,f,g,h,a,b,c, w[5], K[5]);
    ROUND(c,d,e,f,g,h,a,b, w[6], K[6]);
    ROUND(b,c,d,e,f,g,h,a, w[7], K[7]);
    ROUND(a,b,c,d,e,f,g,h, w[8], K[8]);
    ROUND(h,a,b,c,d,e,f,g, 0u,   K[9]);
    ROUND(g,h,a,b,c,d,e,f, 0u,   K[10]);
    ROUND(f,g,h,a,b,c,d,e, 0u,   K[11]);
    ROUND(e,f,g,h,a,b,c,d, 0u,   K[12]);
    ROUND(d,e,f,g,h,a,b,c, 0u,   K[13]);
    ROUND(c,d,e,f,g,h,a,b, 0u,   K[14]);
    ROUND(b,c,d,e,f,g,h,a, w[15],K[15]);

    // ===================================================================
    // MESSAGE SCHEDULE ROUNDS (rolling w[16])
    // BitCrack recurrence:
    //     w[i] = w[i] + sigma0(w[i+1]) + w[i+9] + sigma1(w[i+14])
    // ===================================================================
#define SCHED(i) w[i] = w[i] + sigma0(w[(i+1)&15]) + w[(i+9)&15] + sigma1(w[(i+14)&15]);

    // Round 16..31 schedule updates
    SCHED(0);  SCHED(1);  SCHED(2);  SCHED(3);
    SCHED(4);  SCHED(5);  SCHED(6);  SCHED(7);
    SCHED(8);  SCHED(9);  SCHED(10); SCHED(11);
    SCHED(12); SCHED(13); SCHED(14); SCHED(15);

    // ===================================================================
    // ROUNDS 16..31
    // ===================================================================
    ROUND(a,b,c,d,e,f,g,h, w[0], K[16]);
    ROUND(h,a,b,c,d,e,f,g, w[1], K[17]);
    ROUND(g,h,a,b,c,d,e,f, w[2], K[18]);
    ROUND(f,g,h,a,b,c,d,e, w[3], K[19]);
    ROUND(e,f,g,h,a,b,c,d, w[4], K[20]);
    ROUND(d,e,f,g,h,a,b,c, w[5], K[21]);
    ROUND(c,d,e,f,g,h,a,b, w[6], K[22]);
    ROUND(b,c,d,e,f,g,h,a, w[7], K[23]);
    ROUND(a,b,c,d,e,f,g,h, w[8], K[24]);
    ROUND(h,a,b,c,d,e,f,g, w[9], K[25]);
    ROUND(g,h,a,b,c,d,e,f, w[10], K[26]);
    ROUND(f,g,h,a,b,c,d,e, w[11], K[27]);
    ROUND(e,f,g,h,a,b,c,d, w[12], K[28]);
    ROUND(d,e,f,g,h,a,b,c, w[13], K[29]);
    ROUND(c,d,e,f,g,h,a,b, w[14], K[30]);
    ROUND(b,c,d,e,f,g,h,a, w[15], K[31]);

    // ===================================================================
    // MORE SCHEDULE EXPANSION (32..47)
    // ===================================================================
    SCHED(0);  SCHED(1);  SCHED(2);  SCHED(3);
    SCHED(4);  SCHED(5);  SCHED(6);  SCHED(7);
    SCHED(8);  SCHED(9);  SCHED(10); SCHED(11);
    SCHED(12); SCHED(13); SCHED(14); SCHED(15);

    // ===================================================================
    // ROUNDS 32..47
    // ===================================================================
    ROUND(a,b,c,d,e,f,g,h, w[0], K[32]);
    ROUND(h,a,b,c,d,e,f,g, w[1], K[33]);
    ROUND(g,h,a,b,c,d,e,f, w[2], K[34]);
    ROUND(f,g,h,a,b,c,d,e, w[3], K[35]);
    ROUND(e,f,g,h,a,b,c,d, w[4], K[36]);
    ROUND(d,e,f,g,h,a,b,c, w[5], K[37]);
    ROUND(c,d,e,f,g,h,a,b, w[6], K[38]);
    ROUND(b,c,d,e,f,g,h,a, w[7], K[39]);
    ROUND(a,b,c,d,e,f,g,h, w[8], K[40]);
    ROUND(h,a,b,c,d,e,f,g, w[9], K[41]);
    ROUND(g,h,a,b,c,d,e,f, w[10], K[42]);
    ROUND(f,g,h,a,b,c,d,e, w[11], K[43]);
    ROUND(e,f,g,h,a,b,c,d, w[12], K[44]);
    ROUND(d,e,f,g,h,a,b,c, w[13], K[45]);
    ROUND(c,d,e,f,g,h,a,b, w[14], K[46]);
    ROUND(b,c,d,e,f,g,h,a, w[15], K[47]);

    // ===================================================================
    // FINAL SCHEDULE (48..63)
    // ===================================================================
    SCHED(0);  SCHED(1);  SCHED(2);  SCHED(3);
    SCHED(4);  SCHED(5);  SCHED(6);  SCHED(7);
    SCHED(8);  SCHED(9);  SCHED(10); SCHED(11);
    SCHED(12); SCHED(13); SCHED(14); SCHED(15);

    // ===================================================================
    // FINAL ROUNDS 48..63
    // ===================================================================
    ROUND(a,b,c,d,e,f,g,h, w[0], K[48]);
    ROUND(h,a,b,c,d,e,f,g, w[1], K[49]);
    ROUND(g,h,a,b,c,d,e,f, w[2], K[50]);
    ROUND(f,g,h,a,b,c,d,e, w[3], K[51]);
    ROUND(e,f,g,h,a,b,c,d, w[4], K[52]);
    ROUND(d,e,f,g,h,a,b,c, w[5], K[53]);
    ROUND(c,d,e,f,g,h,a,b, w[6], K[54]);
    ROUND(b,c,d,e,f,g,h,a, w[7], K[55]);
    ROUND(a,b,c,d,e,f,g,h, w[8], K[56]);
    ROUND(h,a,b,c,d,e,f,g, w[9], K[57]);
    ROUND(g,h,a,b,c,d,e,f, w[10], K[58]);
    ROUND(f,g,h,a,b,c,d,e, w[11], K[59]);
    ROUND(e,f,g,h,a,b,c,d, w[12], K[60]);
    ROUND(d,e,f,g,h,a,b,c, w[13], K[61]);
    ROUND(c,d,e,f,g,h,a,b, w[14], K[62]);
    ROUND(b,c,d,e,f,g,h,a, w[15], K[63]);

    // ===================================================================
    // Add initial hash state
    // ===================================================================
    digest[0] = a + 0x6a09e667u;
       digest[1] = b + 0xbb67ae85u;
       digest[2] = c + 0x3c6ef372u;
       digest[3] = d + 0xa54ff53au;
       digest[4] = e + 0x510e527fu;
       digest[5] = f + 0x9b05688cu;
       digest[6] = g + 0x1f83d9abu;
       digest[7] = h + 0x5be0cd19u;
}
