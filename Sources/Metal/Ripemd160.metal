#include <metal_stdlib>
using namespace metal;

constant uint RIPEMD160_IV[5] = {
    0x67452301u, 0xefcdab89u, 0x98badcfeu, 0x10325476u, 0xc3d2e1f0u
};

constant uint K_RMD[8] = {
    0x5a827999u, 0x6ed9eba1u, 0x8f1bbcdcu, 0xa953fd4eu,
    0x7a6d76e9u, 0x6d703ef3u, 0x5c4dd124u, 0x50a28be6u
};

inline uint rotl(uint x, uint n) { return (x << n) | (x >> (32u - n)); }

// Primitive functions
#define F(x,y,z) ((x) ^ (y) ^ (z))
#define G(x,y,z) (((x)&(y)) | (~(x)&(z)))
#define H(x,y,z) (((x)|~(y)) ^ (z))
#define I(x,y,z) (((x)&(z)) | ((y)&~(z)))
#define J(x,y,z) ((x) ^ ((y)|~(z)))

#define FF(a,b,c,d,e,m,s) { a += F(b,c,d) + (m); a = rotl(a,s) + (e); c = rotl(c,10u); }
#define GG(a,b,c,d,e,m,s) { a += G(b,c,d) + (m) + K_RMD[0]; a = rotl(a,s) + (e); c = rotl(c,10u); }
#define HH(a,b,c,d,e,m,s) { a += H(b,c,d) + (m) + K_RMD[1]; a = rotl(a,s) + (e); c = rotl(c,10u); }
#define II(a,b,c,d,e,m,s) { a += I(b,c,d) + (m) + K_RMD[2]; a = rotl(a,s) + (e); c = rotl(c,10u); }
#define JJ(a,b,c,d,e,m,s) { a += J(b,c,d) + (m) + K_RMD[3]; a = rotl(a,s) + (e); c = rotl(c,10u); }

#define FFF(a,b,c,d,e,m,s) { a += F(b,c,d) + (m); a = rotl(a,s) + (e); c = rotl(c,10u); }
#define GGG(a,b,c,d,e,m,s) { a += G(b,c,d) + (m) + K_RMD[4]; a = rotl(a,s) + (e); c = rotl(c,10u); }
#define HHH(a,b,c,d,e,m,s) { a += H(b,c,d) + (m) + K_RMD[5]; a = rotl(a,s) + (e); c = rotl(c,10u); }
#define III(a,b,c,d,e,m,s) { a += I(b,c,d) + (m) + K_RMD[6]; a = rotl(a,s) + (e); c = rotl(c,10u); }
#define JJJ(a,b,c,d,e,m,s) { a += J(b,c,d) + (m) + K_RMD[7]; a = rotl(a,s) + (e); c = rotl(c,10u); }

// TODO: We are doing BE to LE conversions many times at differetn places (swap32) !! This is slow
// Convert SHA256 output word from big-endian to little-endian
inline uint swap32(uint x)
{
    return (x << 24) |
           ((x << 8)  & 0x00ff0000u) |
           ((x >> 8)  & 0x0000ff00u) |
           (x >> 24);
}


inline void ripemd160p1(thread const uint xIn[8], thread uint digest[5])
{
    uint a = RIPEMD160_IV[0];
    uint b = RIPEMD160_IV[1];
    uint c = RIPEMD160_IV[2];
    uint d = RIPEMD160_IV[3];
    uint e = RIPEMD160_IV[4];

    uint x[16];

    for (uint i = 0; i < 8; i++)
        x[i] = xIn[i];

    x[8]  = 128u;
    x[9]  = 0u;
    x[10] = 0u;
    x[11] = 0u;
    x[12] = 0u;
    x[13] = 0u;
    x[14] = 256u;   // 32 bytes * 8
    x[15] = 0u;

    // ---- Round 1 ----
    FF(a,b,c,d,e,x[0],11);  FF(e,a,b,c,d,x[1],14);
    FF(d,e,a,b,c,x[2],15);  FF(c,d,e,a,b,x[3],12);
    FF(b,c,d,e,a,x[4],5);   FF(a,b,c,d,e,x[5],8);
    FF(e,a,b,c,d,x[6],7);   FF(d,e,a,b,c,x[7],9);
    FF(c,d,e,a,b,128u,11);  FF(b,c,d,e,a,0u,13);
    FF(a,b,c,d,e,0u,14);    FF(e,a,b,c,d,0u,15);
    FF(d,e,a,b,c,0u,6);     FF(c,d,e,a,b,0u,7);
    FF(b,c,d,e,a,256u,9);   FF(a,b,c,d,e,0u,8);

    // ---- Round 2 ----
    GG(e,a,b,c,d,x[7],7);   GG(d,e,a,b,c,x[4],6);
    GG(c,d,e,a,b,0u,8);     GG(b,c,d,e,a,x[1],13);
    GG(a,b,c,d,e,0u,11);    GG(e,a,b,c,d,x[6],9);
    GG(d,e,a,b,c,0u,7);     GG(c,d,e,a,b,x[3],15);
    GG(b,c,d,e,a,0u,7);     GG(a,b,c,d,e,x[0],12);
    GG(e,a,b,c,d,0u,15);    GG(d,e,a,b,c,x[5],9);
    GG(c,d,e,a,b,x[2],11);  GG(b,c,d,e,a,256u,7);
    GG(a,b,c,d,e,0u,13);    GG(e,a,b,c,d,128u,12);

    // ---- Round 3 ----
    HH(d,e,a,b,c,x[3],11);  HH(c,d,e,a,b,0u,13);
    HH(b,c,d,e,a,256u,6);   HH(a,b,c,d,e,x[4],7);
    HH(e,a,b,c,d,0u,14);    HH(d,e,a,b,c,0u,9);
    HH(c,d,e,a,b,128u,13);  HH(b,c,d,e,a,x[1],15);
    HH(a,b,c,d,e,x[2],14);  HH(e,a,b,c,d,x[7],8);
    HH(d,e,a,b,c,x[0],13);  HH(c,d,e,a,b,x[6],6);
    HH(b,c,d,e,a,0u,5);     HH(a,b,c,d,e,0u,12);
    HH(e,a,b,c,d,x[5],7);   HH(d,e,a,b,c,0u,5);

    // ---- Round 4 ----
    II(c,d,e,a,b,x[1],11);  II(b,c,d,e,a,0u,12);
    II(a,b,c,d,e,0u,14);    II(e,a,b,c,d,0u,15);
    II(d,e,a,b,c,x[0],14);  II(c,d,e,a,b,128u,15);
    II(b,c,d,e,a,0u,9);     II(a,b,c,d,e,x[4],8);
    II(e,a,b,c,d,0u,9);     II(d,e,a,b,c,x[3],14);
    II(c,d,e,a,b,x[7],5);   II(b,c,d,e,a,0u,6);
    II(a,b,c,d,e,256u,8);   II(e,a,b,c,d,x[5],6);
    II(d,e,a,b,c,x[6],5);   II(c,d,e,a,b,x[2],12);

    // ---- Round 5 ----
    JJ(b,c,d,e,a,x[4],9);   JJ(a,b,c,d,e,x[0],15);
    JJ(e,a,b,c,d,x[5],5);   JJ(d,e,a,b,c,0u,11);
    JJ(c,d,e,a,b,x[7],6);   JJ(b,c,d,e,a,0u,8);
    JJ(a,b,c,d,e,x[2],13);  JJ(e,a,b,c,d,0u,12);
    JJ(d,e,a,b,c,256u,5);   JJ(c,d,e,a,b,x[1],12);
    JJ(b,c,d,e,a,x[3],13);  JJ(a,b,c,d,e,128u,14);
    JJ(e,a,b,c,d,0u,11);    JJ(d,e,a,b,c,x[6],8);
    JJ(c,d,e,a,b,0u,5);     JJ(b,c,d,e,a,0u,6);

    digest[0] = c;
    digest[1] = d;
    digest[2] = e;
    digest[3] = a;
    digest[4] = b;
}



inline void ripemd160p2(thread const uint xIn[8], thread uint digest[5])
{
    uint a = RIPEMD160_IV[0];
    uint b = RIPEMD160_IV[1];
    uint c = RIPEMD160_IV[2];
    uint d = RIPEMD160_IV[3];
    uint e = RIPEMD160_IV[4];

    uint x[16];

    for (uint i = 0; i < 8; i++)
        x[i] = xIn[i];


    x[8]  = 128u;
    x[9]  = 0u;
    x[10] = 0u;
    x[11] = 0u;
    x[12] = 0u;
    x[13] = 0u;
    x[14] = 256u;
    x[15] = 0u;

    // ---- Parallel round 1 ----
    JJJ(a,b,c,d,e,x[5],8);     JJJ(e,a,b,c,d,256u,9);
    JJJ(d,e,a,b,c,x[7],9);     JJJ(c,d,e,a,b,x[0],11);
    JJJ(b,c,d,e,a,0u,13);      JJJ(a,b,c,d,e,x[2],15);
    JJJ(e,a,b,c,d,0u,15);      JJJ(d,e,a,b,c,x[4],5);
    JJJ(c,d,e,a,b,0u,7);       JJJ(b,c,d,e,a,x[6],7);
    JJJ(a,b,c,d,e,0u,8);       JJJ(e,a,b,c,d,128u,11);
    JJJ(d,e,a,b,c,x[1],14);    JJJ(c,d,e,a,b,0u,14);
    JJJ(b,c,d,e,a,x[3],12);    JJJ(a,b,c,d,e,0u,6);

    // ---- Parallel round 2 ----
    III(e,a,b,c,d,x[6],9);     III(d,e,a,b,c,0u,13);
    III(c,d,e,a,b,x[3],15);    III(b,c,d,e,a,x[7],7);
    III(a,b,c,d,e,x[0],12);    III(e,a,b,c,d,0u,8);
    III(d,e,a,b,c,x[5],9);     III(c,d,e,a,b,0u,11);
    III(b,c,d,e,a,256u,7);     III(a,b,c,d,e,0u,7);
    III(e,a,b,c,d,128u,12);    III(d,e,a,b,c,0u,7);
    III(c,d,e,a,b,x[4],6);     III(b,c,d,e,a,0u,15);
    III(a,b,c,d,e,x[1],13);    III(e,a,b,c,d,x[2],11);

    // ---- Parallel round 3 ----
    HHH(d,e,a,b,c,0u,9);       HHH(c,d,e,a,b,x[5],7);
    HHH(b,c,d,e,a,x[1],15);    HHH(a,b,c,d,e,x[3],11);
    HHH(e,a,b,c,d,x[7],8);     HHH(d,e,a,b,c,256u,6);
    HHH(c,d,e,a,b,x[6],6);     HHH(b,c,d,e,a,0u,14);
    HHH(a,b,c,d,e,0u,12);      HHH(e,a,b,c,d,128u,13);
    HHH(d,e,a,b,c,0u,5);       HHH(c,d,e,a,b,x[2],14);
    HHH(b,c,d,e,a,0u,13);      HHH(a,b,c,d,e,x[0],13);
    HHH(e,a,b,c,d,x[4],7);     HHH(d,e,a,b,c,0u,5);

    // ---- Parallel round 4 ----
    GGG(c,d,e,a,b,128u,15);    GGG(b,c,d,e,a,x[6],5);
    GGG(a,b,c,d,e,x[4],8);     GGG(e,a,b,c,d,x[1],11);
    GGG(d,e,a,b,c,x[3],14);    GGG(c,d,e,a,b,0u,14);
    GGG(b,c,d,e,a,0u,6);       GGG(a,b,c,d,e,x[0],14);
    GGG(e,a,b,c,d,x[5],6);     GGG(d,e,a,b,c,0u,9);
    GGG(c,d,e,a,b,x[2],12);    GGG(b,c,d,e,a,0u,9);
    GGG(a,b,c,d,e,0u,12);      GGG(e,a,b,c,d,x[7],5);
    GGG(d,e,a,b,c,0u,15);      GGG(c,d,e,a,b,256u,8);

    // ---- Parallel round 5 ----
    FFF(b,c,d,e,a,0u,8);       FFF(a,b,c,d,e,0u,5);
    FFF(e,a,b,c,d,0u,12);      FFF(d,e,a,b,c,x[4],9);
    FFF(c,d,e,a,b,x[1],12);    FFF(b,c,d,e,a,x[5],5);
    FFF(a,b,c,d,e,128u,14);    FFF(e,a,b,c,d,x[7],6);
    FFF(d,e,a,b,c,x[6],8);     FFF(c,d,e,a,b,x[2],13);
    FFF(b,c,d,e,a,0u,6);       FFF(a,b,c,d,e,256u,5);
    FFF(e,a,b,c,d,x[0],15);    FFF(d,e,a,b,c,x[3],13);
    FFF(c,d,e,a,b,0u,11);      FFF(b,c,d,e,a,0u,11);

    digest[0] = d;
    digest[1] = e;
    digest[2] = a;
    digest[3] = b;
    digest[4] = c;
}


inline void ripemd160sha256NoFinal(
    thread const uint x[8],
    thread uint digest[5]
)
{
    uint d1[5];
    uint d2[5];

    ripemd160p1(x, d1);
    ripemd160p2(x, d2);

    digest[0] = d1[0] + d2[0];
    digest[1] = d1[1] + d2[1];
    digest[2] = d1[2] + d2[2];
    digest[3] = d1[3] + d2[3];
    digest[4] = d1[4] + d2[4];
}

inline void ripemd160FinalRound(
    thread const uint hIn[5],
    thread uint hOut[5]
)
{
    hOut[0] = swap32(hIn[0] + RIPEMD160_IV[1]);
    hOut[1] = swap32(hIn[1] + RIPEMD160_IV[2]);
    hOut[2] = swap32(hIn[2] + RIPEMD160_IV[3]);
    hOut[3] = swap32(hIn[3] + RIPEMD160_IV[4]);
    hOut[4] = swap32(hIn[4] + RIPEMD160_IV[0]);
}




// -------------------------------------------------------------
// Undo RIPEMD160 final round
// Converts FINAL_HASH → PRE_FINAL_HASH used by bloom filter
// hFinal[i] = BIG-ENDIAN 32-bit output of RIPEMD160
// hOut[i]   = INTERMEDIATE STATE (digest1 + digest2)
// -------------------------------------------------------------
// hFinal: 5 x 32-bit words of RIPEMD160 output in big-endian (network order)
// hOut:   5 x 32-bit words = pre-final-round state (same domain as ripemd160sha256NoFinal output)
inline void undoRMD160FinalRound(const thread uint hFinal[5],
                                 thread uint hOut[5])
{
    // This is the inverse of:
    //   final[i] = endian(pre[i] + IV[(i + 1) % 5]);
    // So:
    //   pre[i]   = endian^-1(final[i]) - IV[(i + 1) % 5];

    for (uint i = 0; i < 5; i++)
    {
        uint w = swap32(hFinal[i]);              // endian^-1
        hOut[i] = w - RIPEMD160_IV[(i + 1) % 5];  // subtract rotated IV
    }
}


// -------------------------------------------------------------
// Variant that starts from 20-byte hash160 big-endian
// (This matches the bloom_insert input format.)
// -------------------------------------------------------------
inline void undoRMD160FinalRoundFromBytes(thread const uchar hash160[20],
                                          thread uint hOut[5])
{
    uint hFinal[5];

    // Convert 20-byte hash160 BE → 5 x uint32 BE
    for (uint i = 0; i < 5; i++)
    {
        uint b0 = hash160[i*4 + 0];
        uint b1 = hash160[i*4 + 1];
        uint b2 = hash160[i*4 + 2];
        uint b3 = hash160[i*4 + 3];

        hFinal[i] = (b0 << 24) | (b1 << 16) | (b2 << 8) | b3;
    }

    undoRMD160FinalRound(hFinal, hOut);
}
