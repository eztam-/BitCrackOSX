#include <metal_stdlib>
using namespace metal;

// ---- SECP256k1 constants (little-endian limb order) ----

// Secp256k1 prime modulus p = 2^256 - 2^32 - 977
constant uint P[8] = {
    0xFFFFFC2F, 0xFFFFFFFE, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF  // little endian limbs ordered from LS to MS
};


// Exponent p-2 for inversion: stored as MSW-first for MSB->LSB scanning
// P-2 in little-endian limb order (LSW first)
constant uint P_MINUS_2[8] = {
    0xFFFFFC2D,  // limb 0 (bits 0-31)
    0xFFFFFFFE,  // limb 1 (bits 32-63)
    0xFFFFFFFF,  // limb 2 (bits 64-95)
    0xFFFFFFFF,  // limb 3 (bits 96-127)
    0xFFFFFFFF,  // limb 4 (bits 128-159)
    0xFFFFFFFF,  // limb 5 (bits 160-191)
    0xFFFFFFFF,  // limb 6 (bits 192-223)
    0xFFFFFFFF   // limb 7 (bits 224-255, MSW)
};





// ================ Type Definitions ================

struct uint256 {
    uint limbs[8];
};

struct uint512 {
    uint limbs[16];
};

struct Point {
    uint256 x;
    uint256 y;
    bool infinity;
};

// G
constant Point generator = {
    {   // x limbs - // little endian limbs ordered from LS to MS
        { 0x16F81798, 0x59F2815B, 0x2DCE28D9, 0x029BFCDB, 0xCE870B07, 0x55A06295, 0xF9DCBBAC, 0x79BE667E }
    },
    {   // y limbs // little endian limbs ordered from LS to MS
        { 0xFB10D4B8, 0x9C47D08F, 0xA6855419, 0xFD17B448, 0x0E1108A8, 0x5DA4FBFC, 0x26A3C465, 0x483ADA77 }
    },
    false
};





// constant Point generator{
 //    { { 0x16F81798, 0x59F2815B, 0x2DCE28D9, 0x029BFCDB, 0xCE870B07, 0x55A06295, 0xF9DCBBAC, 0x79BE667E } },
 //    { { 0xFB10D4B8, 0x9C47D08F, 0xA6855419, 0xFD17B448, 0x0E1108A8, 0x5DA4FBFC, 0x26A3C465, 0x483ADA77 } },
 //    false
// }

// ---- Precomputed 4-bit window table for secp256k1 base point ----
// G_TABLE[n] = (n+1) * G for n = 0..14, plus G_TABLE[15] = 16*G

constant Point G_TABLE[16] = {
    // Each entry is { {x limbs[8]}, {y limbs[8]}, false }
    // You must fill these with real secp256k1 multiples of G.
    // Below are only G (1·G) as an example — fill others offline.
   // {
    //    { { 0x16F81798, 0x59F2815B, 0x2DCE28D9, 0x029BFCDB, 0xCE870B07, 0x55A06295, 0xF9DCBBAC, 0x79BE667E } },
    //    { { 0xFB10D4B8, 0x9C47D08F, 0xA6855419, 0xFD17B448, 0x0E1108A8, 0x5DA4FBFC, 0x26A3C465, 0x483ADA77 } },
    //    false
   // },
    // { 2·G }, { 3·G }, ... { 16·G }
    
    
    { { 0x16f81798, 0x59f2815b, 0x2dce28d9, 0x029bfcdb, 0xce870b07, 0x55a06295, 0xf9dcbbac, 0x79be667e }, { 0xfb10d4b8, 0x9c47d08f, 0xa6855419, 0xfd17b448, 0x0e1108a8, 0x5da4fbfc, 0x26a3c465, 0x483ada77 }, false },
    { { 0x5c709ee5, 0xabac09b9, 0x8cef3ca7, 0x5c778e4b, 0x95c07cd8, 0x3045406e, 0x41ed7d6d, 0xc6047f94 }, { 0x50cfe52a, 0x236431a9, 0x3266d0e1, 0xf7f63265, 0x466ceaee, 0xa3c58419, 0xa63dc339, 0x1ae168fe }, false },
    { { 0xbce036f9, 0x8601f113, 0x836f99b0, 0xb531c845, 0xf89d5229, 0x49344f85, 0x9258c310, 0xf9308a01 }, { 0x84b8e672, 0x6cb9fd75, 0x34c2231b, 0x6500a999, 0x2a37f356, 0x0fe337e6, 0x632de814, 0x388f7b0f }, false },
    { { 0xe8c4cd13, 0x74fa94ab, 0x0ee07584, 0xcc6c1390, 0x930b1404, 0x581e4904, 0xc10d80f3, 0xe493dbf1 }, { 0x47739922, 0xcfe97bdc, 0xbfbdfe40, 0xd967ae33, 0x8ea51448, 0x5642e209, 0xa0d455b7, 0x51ed993e }, false },
    { { 0xb240efe4, 0xcba8d569, 0xdc619ab7, 0xe88b84bd, 0x0a5c5128, 0x55b4a725, 0x1a072093, 0x2f8bde4d }, { 0xa6ac62d6, 0xdca87d3a, 0xab0d6840, 0xf788271b, 0xa6c9c426, 0xd4dba9dd, 0x36e5e3d6, 0xd8ac2226 }, false },
    { { 0x60297556, 0x2f057a14, 0x8568a18b, 0x82f6472f, 0x355235d3, 0x20453a14, 0x755eeea4, 0xfff97bd5 }, { 0xb075f297, 0x3c870c36, 0x518fe4a0, 0xde80f0f6, 0x7f45c560, 0xf3be9601, 0xacfbb620, 0xae12777a }, false },
    { { 0xcac4f9bc, 0xe92bdded, 0x0330e39c, 0x3d419b7e, 0xf2ea7a0e, 0xa398f365, 0x6e5db4ea, 0x5cbdf064 }, { 0x087264da, 0xa5082628, 0x13fde7b5, 0xa813d0b8, 0x861a54db, 0xa3178d6d, 0xba255960, 0x6aebca40 }, false },
    { { 0xe10a2a01, 0x67784ef3, 0xe5af888a, 0x0a1bdd05, 0xb70f3c2f, 0xaff3843f, 0x5cca351d, 0x2f01e5e1 }, { 0x6cbde904, 0xb5da2cb7, 0xba5b7617, 0xc2e213d6, 0x132d13b4, 0x293d082a, 0x41539949, 0x5c4da8a7 }, false },
    { { 0xfc27ccbe, 0xc35f110d, 0x4c57e714, 0xe0979697, 0x9f559abd, 0x09ad178a, 0xf0c7f653, 0xacd484e2 }, { 0xc64f9c37, 0x05cc262a, 0x375f8e0f, 0xadd888a4, 0x763b61e9, 0x64380971, 0xb0a7d9fd, 0xcc338921 }, false },
    { { 0x47e247c7, 0x52a68e2a, 0x1943c2b7, 0x3442d49b, 0x1ae6ae5d, 0x35477c7b, 0x47f3c862, 0xa0434d9e }, { 0x037368d7, 0x3cbee53b, 0xd877a159, 0x6f794c2e, 0x93a24c69, 0xa3b6c7e6, 0x5419bc27, 0x893aba42 }, false },
    { { 0x5da008cb, 0xbbec1789, 0xe5c17891, 0x5649980b, 0x70c65aac, 0x5ef4246b, 0x58a9411e, 0x774ae7f8 }, { 0xc953c61b, 0x301d74c9, 0xdff9d6a8, 0x372db1e2, 0xd7b7b365, 0x0243dd56, 0xeb6b5e19, 0xd984a032 }, false },
    { { 0x70afe85a, 0xc5b0f470, 0x9620095b, 0x687cf441, 0x4d734633, 0x15c38f00, 0x48e7561b, 0xd01115d5 }, { 0xf4062327, 0x6b051b13, 0xd9a86d52, 0x79238c5d, 0xe17bd815, 0xa8b64537, 0xc815e0d7, 0xa9f34ffd }, false },
    { { 0x19405aa8, 0xdeeddf8f, 0x610e58cd, 0xb075fbc6, 0xc3748651, 0xc7d1d205, 0xd975288b, 0xf28773c2 }, { 0xdb03ed81, 0x29b5cb52, 0x521fa91f, 0x3a1a06da, 0x65cdaf47, 0x758212eb, 0x8d880a89, 0x0ab0902e }, false },
    { { 0x60e823e4, 0xe49b241a, 0x678949e6, 0x26aa7b63, 0x07d38e32, 0xfd64e67f, 0x895e719c, 0x499fdf9e }, { 0x03a13f5b, 0xc65f40d4, 0x7a3f95bc, 0x464279c2, 0xa7b3d464, 0x90f044e4, 0xb54e8551, 0xcac2f6c4 }, false },
    { { 0xe27e080e, 0x44adbcf8, 0x3c85f79e, 0x31e5946f, 0x095ff411, 0x5a465ae3, 0x7d43ea96, 0xd7924d4f }, { 0xf6a26b58, 0xc504dc9f, 0xd896d3a5, 0xea40af2b, 0x28cc6def, 0x83842ec2, 0xa86c72a6, 0x581e2872 }, false },
    { { 0x2a6dec0a, 0xc44ee89e, 0xb87a5ae9, 0xb2a31369, 0x21c23e97, 0x3011aabc, 0xb59e9ec5, 0xe60fce93 }, { 0x69616821, 0xe1f32cce, 0x44d23f0b, 0x1296891e, 0xf5793710, 0x9db99f34, 0x99e59592, 0xf7e35073 }, false }
    
    
};



// ================ Utility functions ================

inline uint256 load_private_key(device const uint* private_keys, uint index) {
    uint256 result;
    #pragma unroll
    for (int i = 0; i < 8; i++) {
        result.limbs[i] = private_keys[index * 8 + i];
    }
    return result;
}

/*
inline void store_public_key(device uint* output, uint index, uint256 x, uint256 y) {
    for (int i = 0; i < 8; i++) {
        output[index * 16 + i] = x.limbs[i];      // x coordinate
        output[index * 16 + 8 + i] = y.limbs[i];  // y coordinate
    }
}
*/

/**
 Creates a 65-byte uncompressed public key.
 Adds the 0x04 prefix byte at the beginning (that’s the uncompressed SEC1 format marker).
 Adjust the base offset so each key occupies 65 bytes instead of 64.
 */
inline void store_public_key_uncompressed(device uchar* output, uint index, uint256 x, uint256 y) {
    // Each public key = 65 bytes: 0x04 + 32 bytes X + 32 bytes Y (big-endian)
    int base = index * 65;

    // Prefix 0x04
    output[base + 0] = 0x04;

    // Write X coordinate in big-endian order
    int pos = base + 1;
    #pragma unroll
    for (int limb = 7; limb >= 0; limb--) {
        uint vx = x.limbs[limb];
        output[pos + 0] = (uchar)((vx >> 24) & 0xFF);
        output[pos + 1] = (uchar)((vx >> 16) & 0xFF);
        output[pos + 2] = (uchar)((vx >> 8)  & 0xFF);
        output[pos + 3] = (uchar)(vx & 0xFF);
        pos += 4;
    }

    // Write Y coordinate in big-endian order
    #pragma unroll
    for (int limb = 7; limb >= 0; limb--) {
        uint vy = y.limbs[limb];
        output[pos + 0] = (uchar)((vy >> 24) & 0xFF);
        output[pos + 1] = (uchar)((vy >> 16) & 0xFF);
        output[pos + 2] = (uchar)((vy >> 8)  & 0xFF);
        output[pos + 3] = (uchar)(vy & 0xFF);
        pos += 4;
    }
}


/**
 Creates a 33-byte compressed public key.
 Adds the prefix: 0x02 if Y is even or 0x03 if Y is odd
 */
inline void store_public_key_compressed(device uchar* output, uint index, uint256 x, uint256 y) {
    // Each public key = 33 bytes: prefix (0x02/0x03) + 32 bytes X (big-endian)
    int base = index * 33;

    // Y parity: LSB of the whole 256-bit Y is in y.limbs[0]
    uchar prefix = (y.limbs[0] & 1u) ? 0x03 : 0x02;
    output[base + 0] = prefix;

    // Write X in big-endian order: most-significant limb first, high byte first
    int outPos = base + 1; // first byte of X
    #pragma unroll
    for (int limb = 7; limb >= 0; limb--) {
        uint vx = x.limbs[limb];
        // write bytes MSB -> LSB
        output[outPos + 0] = (uchar)((vx >> 24) & 0xFF);
        output[outPos + 1] = (uchar)((vx >> 16) & 0xFF);
        output[outPos + 2] = (uchar)((vx >> 8)  & 0xFF);
        output[outPos + 3] = (uchar)((vx >> 0)  & 0xFF);
        outPos += 4;
    }
}



inline bool is_zero(uint256 a) {
    #pragma unroll
    for (int i = 0; i < 8; i++) {
        if (a.limbs[i] != 0) return false;
    }
    return true;
}

inline bool is_equal(uint256 a, uint256 b) {
    #pragma unroll
    for (int i = 0; i < 8; i++) {
        if (a.limbs[i] != b.limbs[i]) return false;
    }
    return true;
}

inline int compare(uint256 a, uint256 b) {
    #pragma unroll
    for (int i = 7; i >= 0; i--) {
        if (a.limbs[i] > b.limbs[i]) return 1;
        if (a.limbs[i] < b.limbs[i]) return -1;
    }
    return 0;
}



// ================ Field Arithmetic ================

uint256 field_sub(uint256 a, uint256 b) {
    uint256 result;
    ulong borrow = 0;
    #pragma unroll
    for (int i = 0; i < 8; i++) {
        ulong ai = (ulong)a.limbs[i];
        ulong bi = (ulong)b.limbs[i];
        ulong tmp = ai - bi - borrow;

        result.limbs[i] = (uint)tmp;
        // If ai < bi + borrow, then tmp wrapped around and top bit set
        borrow = (tmp >> 63) & 1ul; // borrow = 1 if underflow occurred
    }

    // If borrow == 1, we underflowed: add modulus back
    if (borrow) {
        ulong carry = 0;
        #pragma unroll
        for (int i = 0; i < 8; i++) {
            ulong sum = (ulong)result.limbs[i] + (ulong)P[i] + carry;
            result.limbs[i] = (uint)sum;
            carry = sum >> 32;
        }
    }

    return result;
}


inline void mul_32x32(uint a, uint b, thread uint* low, thread uint* high) {
    // use 64-bit product
    ulong prod = (ulong)a * (ulong)b;
    *low = (uint)prod;
    *high = (uint)(prod >> 32);
}





inline void add_with_carry(uint a, uint b, uint carry_in, thread uint* result, thread uint* carry_out) {
    ulong sum = (ulong)a + (ulong)b + (ulong)carry_in;
    *result = (uint)sum;
    *carry_out = (uint)(sum >> 32);
}


uint256 sub_uint256(uint256 a, uint256 b) {
    uint256 result;
    uint borrow = 0;
    
    #pragma unroll
    for (int i = 0; i < 8; i++) {
        uint ai = a.limbs[i];
        uint bi = b.limbs[i];
        
        uint temp = bi + borrow;
        uint new_borrow = (temp < bi) ? 1u : 0u;
        
        uint diff = ai - temp;
        if (ai < temp) new_borrow = 1u;
        
        result.limbs[i] = diff;
        borrow = new_borrow;
    }
    
    return result;
}


// Field addition with modular reduction
uint256 field_add(uint256 a, uint256 b) {
    uint256 result;
    uint carry = 0;
    
    // Add a + b with carry propagation
    #pragma unroll
    for (int i = 0; i < 8; i++) {
        uint sum, carry_out;
        add_with_carry(a.limbs[i], b.limbs[i], carry, &sum, &carry_out);
        result.limbs[i] = sum;
        carry = carry_out;
    }
    
    // If there's a carry out, result >= 2^256
    // We need to reduce: result = (a + b) - P if (a + b) >= P
    
    uint256 p;
    #pragma unroll
    for (int i = 0; i < 8; i++) {
        p.limbs[i] = P[i];
    }
    
    // If carry OR result >= P, subtract P
    if (carry || compare(result, p) >= 0) {
        result = sub_uint256(result, p);
    }
    
    return result;
}



// ===== Main Multiplication Function =====

uint256 field_mul(uint256 a, uint256 b) {
    // Step 1: 8x8 schoolbook multiplication -> 512-bit product
    uint512 product;
    #pragma unroll
    for (int i = 0; i < 16; i++) {
        product.limbs[i] = 0;
    }
    
    
    for (int i = 0; i < 8; i++) {
        uint carry = 0;
        
        for (int j = 0; j < 8; j++) {
            uint mul_low, mul_high;
            mul_32x32(a.limbs[i], b.limbs[j], &mul_low, &mul_high);
            
            uint sum, sum_carry;
            add_with_carry(product.limbs[i + j], mul_low, carry, &sum, &sum_carry);
            product.limbs[i + j] = sum;
            
            carry = mul_high + sum_carry;
        }
        
        product.limbs[i + 8] = carry;
    }
    
    // Step 2: Barrett-style reduction
    // Instead of complex reduction, do simple: while (product >= P * 2^256) subtract P * 2^256
    // Then final cleanup
    
    // Reduce upper limbs iteratively
    for (int round = 0; round < 9; round++) {
        for (int i = 15; i >= 8; i--) {
            uint c = product.limbs[i];
            if (c == 0) continue;
            
            product.limbs[i] = 0;
            
            // c * 2^(32*i) needs reduction
            // 2^256 ≡ 2^32 + 977 (mod P)
            // So 2^(32*i) = 2^(32*(i-8)) * 2^256 ≡ 2^(32*(i-8)) * (2^32 + 977)
            
            int pos = i - 8;
            
            // Add c * 977 at position pos
            uint mul_low, mul_high;
            mul_32x32(c, 977u, &mul_low, &mul_high);
            
            uint sum, carry_out;
            add_with_carry(product.limbs[pos], mul_low, 0u, &sum, &carry_out);
            product.limbs[pos] = sum;
            
            uint carry = mul_high + carry_out;
            for (int j = pos + 1; j < 16 && carry > 0; j++) {
                add_with_carry(product.limbs[j], 0u, carry, &sum, &carry_out);
                product.limbs[j] = sum;
                carry = carry_out;
            }
            
            // Add c * 2^32 at position pos+1
            if (pos + 1 < 16) {
                add_with_carry(product.limbs[pos + 1], c, 0u, &sum, &carry_out);
                product.limbs[pos + 1] = sum;
                
                carry = carry_out;
                for (int j = pos + 2; j < 16 && carry > 0; j++) {
                    add_with_carry(product.limbs[j], 0u, carry, &sum, &carry_out);
                    product.limbs[j] = sum;
                    carry = carry_out;
                }
            }
        }
    }
    
    // Copy to result
    uint256 result;
    #pragma unroll
    for (int i = 0; i < 8; i++) {
        result.limbs[i] = product.limbs[i];
    }
    
    // Final reductions
    uint256 p;
    #pragma unroll
    for (int i = 0; i < 8; i++) {
        p.limbs[i] = P[i];
    }
    #pragma unroll
    for (int i = 0; i < 3; i++) {
        if (compare(result, p) >= 0) {
            result = sub_uint256(result, p);
        }
    }
    
    return result;
}


uint256 field_sqr(uint256 a) {
    return field_mul(a, a);
}




// Build a uint256 from the global modulus P[8]
inline uint256 mod_p_u256() {
    uint256 m;
    #pragma unroll
    for (int i = 0; i < 8; i++) m.limbs[i] = P[i];
    return m;
}

// Right shift by 1 over 8×32-bit limbs; msb_in becomes the new top bit (bit 255)
inline uint256 rshift1_with_msb(uint256 a, uint msb_in) {
    uint256 r;
    uint carry = msb_in & 1u; // becomes top bit after shifting
    // walk from MS limb to LS limb
    #pragma unroll
    for (int i = 7; i >= 0; i--) {
        uint new_carry = a.limbs[i] & 1u;              // LSB that falls to next limb
        r.limbs[i] = (a.limbs[i] >> 1) | (carry << 31);
        carry = new_carry;
    }
    return r;
}

// Plain 256-bit add: r = a + b (no modular reduction). Returns final carry (0/1).
inline uint add_uint256_raw(thread uint256 &r, uint256 a, uint256 b) {
    uint carry = 0;
    #pragma unroll
    for (int i = 0; i < 8; i++) {
        uint sum, c1;
        add_with_carry(a.limbs[i], b.limbs[i], carry, &sum, &c1);
        r.limbs[i] = sum;
        carry = c1;
    }
    return carry; // 0 or 1
}



// Modular inverse using a binary extended GCD variant (fast, branchy, GPU-friendly)
// Returns a^{-1} mod p. If a == 0, returns 0.
uint256 field_inv(uint256 a) {
    if (is_zero(a)) return a;

    const uint256 p = mod_p_u256();

    // t0 = a, t1 = p, t2 = 1, t3 = 0
    uint256 t0 = a;
    uint256 t1 = p;

    uint256 t2; // accumulator for a^{-1} mod p
    #pragma unroll
    for (int i = 0; i < 8; i++) t2.limbs[i] = 0;
    t2.limbs[0] = 1;

    uint256 t3; // auxiliary (for p - a^{-1})
    #pragma unroll
    for (int i = 0; i < 8; i++) t3.limbs[i] = 0;

    // while (t0 != t1)
    while (!is_equal(t0, t1)) {
        if ((t0.limbs[0] & 1u) == 0u) {
            // t0 even: t0 >>= 1
            t0 = rshift1_with_msb(t0, 0u);

            // If t2 is odd, add p before halving to keep it integral mod p
            uint msb_in = 0u;
            if (t2.limbs[0] & 1u) {
                uint256 tmp;
                msb_in = add_uint256_raw(tmp, t2, p); // carry becomes top bit
                t2 = tmp;
            }
            t2 = rshift1_with_msb(t2, msb_in);
        }
        else if ((t1.limbs[0] & 1u) == 0u) {
            // t1 even
            t1 = rshift1_with_msb(t1, 0u);

            uint msb_in = 0u;
            if (t3.limbs[0] & 1u) {
                uint256 tmp;
                msb_in = add_uint256_raw(tmp, t3, p);
                t3 = tmp;
            }
            t3 = rshift1_with_msb(t3, msb_in);
        }
        else {
            // both odd: subtract the larger by the smaller
            if (compare(t0, t1) > 0) {
                // t0 = (t0 - t1) >> 1
                t0 = sub_uint256(t0, t1);

                // t2 = (t2 - t3) >> 1   (mod p), do borrow fix by +p if needed
                // If t2 < t3, add p before subtracting to avoid underflow.
                if (compare(t2, t3) < 0) {
                    uint256 tmp;
                    (void)add_uint256_raw(tmp, t2, p);
                    t2 = tmp;
                }
                t2 = sub_uint256(t2, t3);

                uint msb_in = 0u;
                if (t2.limbs[0] & 1u) {
                    uint256 tmp;
                    msb_in = add_uint256_raw(tmp, t2, p);
                    t2 = tmp;
                }
                t2 = rshift1_with_msb(t2, msb_in);

                t0 = rshift1_with_msb(t0, 0u);
            } else {
                // t1 = (t1 - t0) >> 1
                t1 = sub_uint256(t1, t0);

                // t3 = (t3 - t2) >> 1   (mod p)
                if (compare(t3, t2) < 0) {
                    uint256 tmp;
                    (void)add_uint256_raw(tmp, t3, p);
                    t3 = tmp;
                }
                t3 = sub_uint256(t3, t2);

                uint msb_in = 0u;
                if (t3.limbs[0] & 1u) {
                    uint256 tmp;
                    msb_in = add_uint256_raw(tmp, t3, p);
                    t3 = tmp;
                }
                t3 = rshift1_with_msb(t3, msb_in);

                t1 = rshift1_with_msb(t1, 0u);
            }
        }
    }

    // Result is t2
    return t2;
}


// ================ Point operations ================


// Add Jacobian point structure
struct PointJacobian {
    uint256 X;
    uint256 Y;
    uint256 Z;
    bool infinity;
};



// Convert Jacobian to affine (requires ONE inversion)
Point jacobian_to_affine(PointJacobian p) {
    Point result;
    if (p.infinity) {
        result.infinity = true;
        return result;
    }
    
    // Compute Z^-1, Z^-2, Z^-3
    uint256 z_inv = field_inv(p.Z);           // 1 inversion (expensive)
    uint256 z_inv_sq = field_sqr(z_inv);      // Z^-2
    uint256 z_inv_cube = field_mul(z_inv_sq, z_inv);  // Z^-3
    
    // x = X/Z^2 = X * Z^-2
    result.x = field_mul(p.X, z_inv_sq);
    
    // y = Y/Z^3 = Y * Z^-3
    result.y = field_mul(p.Y, z_inv_cube);
    
    result.infinity = false;
    return result;
}


inline PointJacobian point_double_jacobian(PointJacobian P) {
    if (P.infinity) return P;

    // Y2 = Y^2
    uint256 Y2 = field_sqr(P.Y);

    // S = 4 * X * Y^2
    uint256 S = field_mul(P.X, Y2);
    S = field_add(S, S);  // *2
    S = field_add(S, S);  // *4

    // M = 3 * X^2
    uint256 X2 = field_sqr(P.X);
    uint256 M  = field_add(field_add(X2, X2), X2);

    // X3 = M^2 - 2*S
    uint256 M2 = field_sqr(M);
    uint256 X3 = field_sub(M2, field_add(S, S));

    // Y3 = M*(S - X3) - 8*Y^4
    uint256 Y4 = field_sqr(Y2);
    uint256 eightY4 = field_add(field_add(Y4, Y4), field_add(Y4, Y4)); // *4
    eightY4 = field_add(eightY4, eightY4);                              // *8
    uint256 Y3 = field_sub(field_mul(M, field_sub(S, X3)), eightY4);

    // Z3 = 2 * Y * Z
    uint256 Z3 = field_mul(field_add(P.Y, P.Y), P.Z);

    PointJacobian R;
    R.X = X3;
    R.Y = Y3;
    R.Z = Z3;
    R.infinity = false;
    return R;
}


// Jacobian + Affine (Z2 = 1) : R = P + Q
// P is Jacobian (X1, Y1, Z1), Q is affine (x2, y2)
// Handles P or Q at infinity; zero-cost for Z2 since it's 1.
inline PointJacobian point_add_mixed_jacobian(PointJacobian P, Point Q) {
    if (P.infinity) {
        // Lift Q to Jacobian (Z=1)
        PointJacobian R;
        R.X = Q.x;
        R.Y = Q.y;
        #pragma unroll
        for (int i = 0; i < 8; i++) R.Z.limbs[i] = 0;
        R.Z.limbs[0] = 1;
        R.infinity = Q.infinity;
        return R;
    }
    if (Q.infinity) return P;

    // Z1Z1 = Z1^2
    uint256 Z1Z1 = field_sqr(P.Z);

    // U2 = x2 * Z1Z1
    uint256 U2 = field_mul(Q.x, Z1Z1);

    // Z1^3
    uint256 Z1_cubed = field_mul(Z1Z1, P.Z);

    // S2 = y2 * Z1^3
    uint256 S2 = field_mul(Q.y, Z1_cubed);

    // H = U2 - X1
    uint256 H = field_sub(U2, P.X);
    // r = S2 - Y1
    uint256 r = field_sub(S2, P.Y);

    // If H == 0:
    if (is_zero(H)) {
        // If r == 0: P == Q -> doubling
        if (is_zero(r)) {
            return point_double_jacobian(P);
        } else {
            PointJacobian R;
            R.infinity = true;
            return R;
        }
    }

    // HH = H^2
    uint256 HH = field_sqr(H);
    // HHH = H^3
    uint256 HHH = field_mul(HH, H);
    // V = X1 * HH
    uint256 V = field_mul(P.X, HH);

    // X3 = r^2 - H^3 - 2*V
    uint256 r2 = field_sqr(r);
    uint256 X3 = field_sub(field_sub(r2, HHH), field_add(V, V));

    // Y3 = r*(V - X3) - Y1*HHH
    uint256 Y3 = field_sub(field_mul(r, field_sub(V, X3)), field_mul(P.Y, HHH));

    // Z3 = Z1 * H
    uint256 Z3 = field_mul(P.Z, H);

    PointJacobian R;
    R.X = X3;
    R.Y = Y3;
    R.Z = Z3;
    R.infinity = false;
    return R;
}



// Windowed scalar multiplication with Jacobian accumulator and affine table.
// Uses your existing 4-bit G_TABLE[16] (values 1*G .. 16*G).
inline Point point_mul(uint256 k) {
    // R = ∞ in Jacobian
    PointJacobian R;
    R.infinity = true;

    // Process from MS nibble to LS nibble, 4 doublings per step
    for (int limb = 7; limb >= 0; limb--) {
        uint word = k.limbs[limb];

        // 8 nibbles per 32-bit word
        for (int nib = 7; nib >= 0; nib--) {
            // R = 16*R (4 doublings) — skip if infinity to avoid wasted work
            if (!R.infinity) {
                R = point_double_jacobian(R);
                R = point_double_jacobian(R);
                R = point_double_jacobian(R);
                R = point_double_jacobian(R);
            }

            uint idx = (word >> (nib * 4)) & 0xFu;
            if (idx != 0u) {
                // Table holds affine points at indices 0..15.
                // If your table is (1..16)*G at [0..15], use idx-1.
                const Point addend = G_TABLE[idx - 1];
                if (R.infinity) {
                    // Lift addend to Jacobian (Z=1)
                    R.X = addend.x;
                    R.Y = addend.y;
                    #pragma unroll
                    for (int i = 0; i < 8; i++) R.Z.limbs[i] = 0;
                    R.Z.limbs[0] = 1;
                    R.infinity = false;
                } else {
                    R = point_add_mixed_jacobian(R, addend);
                }
            }
        }
    }

    // Single inversion here
    return jacobian_to_affine(R);
}





// ================ Kernel ================


// Main kernel - converts private keys to public keys
kernel void private_to_public_keys(
    device const uint* private_keys [[buffer(0)]],
    device uchar* public_keys_comp [[buffer(1)]],
    device uchar* public_keys_uncomp [[buffer(2)]],
    uint id [[thread_position_in_grid]],
    uint lid [[thread_position_in_threadgroup]]
                                   
) {
    // Load private key for this thread
    uint256 private_key = load_private_key(private_keys, id);
    

    // Multiply generator by private key to get public key
    Point public_key_point = point_mul(private_key); // Pre-calculated G values
    
    
    // Store result
    if (public_key_point.infinity) {
        #pragma unroll
        for (int i = 0; i < 33; i++) {
            public_keys_comp[id * 33 + i] = 0;
        }
        #pragma unroll
        for (int i = 0; i < 65; i++) {
            public_keys_uncomp[id * 65 + i] = 0;
        }
    } else {
        store_public_key_compressed(public_keys_comp, id, public_key_point.x, public_key_point.y);
        store_public_key_uncompressed(public_keys_uncomp, id, public_key_point.x, public_key_point.y);
    }
}

// ================ Test Kernels ================

kernel void test_field_mul(
    device const uint* input_a [[buffer(0)]],
    device const uint* input_b [[buffer(1)]],
    device uint* output [[buffer(2)]],
    uint id [[thread_position_in_grid]]
) {
    uint256 a, b;
    for (int i = 0; i < 8; i++) {
        a.limbs[i] = input_a[id * 8 + i];
        b.limbs[i] = input_b[id * 8 + i];
    }
    
    uint256 result = field_mul(a, b);
    
    for (int i = 0; i < 8; i++) {
        output[id * 8 + i] = result.limbs[i];
    }
}

kernel void test_field_inv(
    device const uint* input_a [[buffer(0)]],
    device const uint* input_b [[buffer(1)]],
    device uint* output [[buffer(2)]],
    uint id [[thread_position_in_grid]]
) {
    uint256 a, b;
    for (int i = 0; i < 8; i++) {
        a.limbs[i] = input_a[id * 8 + i];
        b.limbs[i] = input_b[id * 8 + i];
    }
    
    uint256 result = field_inv(a);
    
    for (int i = 0; i < 8; i++) {
        output[id * 8 + i] = result.limbs[i];
    }
}


kernel void test_field_sub(
    device const uint* input_a [[buffer(0)]],
    device const uint* input_b [[buffer(1)]],
    device uint* output [[buffer(2)]],
    uint id [[thread_position_in_grid]]
) {
    uint256 a, b;
    for (int i = 0; i < 8; i++) {
        a.limbs[i] = input_a[id * 8 + i];
        b.limbs[i] = input_b[id * 8 + i];
    }
    
    uint256 result = field_sub(a, b);
    
    for (int i = 0; i < 8; i++) {
        output[id * 8 + i] = result.limbs[i];
    }
}
