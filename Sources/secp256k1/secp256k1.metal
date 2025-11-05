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
    for (int limb = 7; limb >= 0; limb--) {
        uint vx = x.limbs[limb];
        output[pos + 0] = (uchar)((vx >> 24) & 0xFF);
        output[pos + 1] = (uchar)((vx >> 16) & 0xFF);
        output[pos + 2] = (uchar)((vx >> 8)  & 0xFF);
        output[pos + 3] = (uchar)(vx & 0xFF);
        pos += 4;
    }

    // Write Y coordinate in big-endian order
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
    for (int i = 0; i < 8; i++) {
        if (a.limbs[i] != 0) return false;
    }
    return true;
}

inline bool is_equal(uint256 a, uint256 b) {
    for (int i = 0; i < 8; i++) {
        if (a.limbs[i] != b.limbs[i]) return false;
    }
    return true;
}

inline int compare(uint256 a, uint256 b) {
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

/*
 TODO: compare with the other implementation for performance. This one is well tested and is correct!
inline void mul_32x32(uint a, uint b, thread uint* low, thread uint* high) {
    uint a_lo = a & 0xFFFFu;
    uint a_hi = a >> 16;
    uint b_lo = b & 0xFFFFu;
    uint b_hi = b >> 16;
    
    uint p0 = a_lo * b_lo;
    uint p1 = a_lo * b_hi;
    uint p2 = a_hi * b_lo;
    uint p3 = a_hi * b_hi;
    
    uint middle = p1 + p2;
    uint middle_carry = (middle < p1) ? 1u : 0u;
    
    *low = p0 + (middle << 16);
    uint carry = (*low < p0) ? 1u : 0u;
    
    *high = p3 + (middle >> 16) + (middle_carry << 16) + carry;
}
*/


inline void add_with_carry(uint a, uint b, uint carry_in, thread uint* result, thread uint* carry_out) {
    ulong sum = (ulong)a + (ulong)b + (ulong)carry_in;
    *result = (uint)sum;
    *carry_out = (uint)(sum >> 32);
}

/*
TODO: compare with the other implementation for performance. This one is well tested and is correct!
inline void add_with_carry(uint a, uint b, uint carry_in, thread uint* result, thread uint* carry_out) {
    uint sum1 = a + b;
    uint c1 = (sum1 < a) ? 1u : 0u;
    
    uint sum2 = sum1 + carry_in;
    uint c2 = (sum2 < sum1) ? 1u : 0u;
    
    *result = sum2;
    *carry_out = c1 + c2;
}
 */

// TODO I assume we need to apply P-2 if negative? Same as for sub_uint256? but then it would be the same??
uint256 sub_uint256(uint256 a, uint256 b) {
    uint256 result;
    uint borrow = 0;
    
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
    for (int i = 0; i < 8; i++) {
        uint sum, carry_out;
        add_with_carry(a.limbs[i], b.limbs[i], carry, &sum, &carry_out);
        result.limbs[i] = sum;
        carry = carry_out;
    }
    
    // If there's a carry out, result >= 2^256
    // We need to reduce: result = (a + b) - P if (a + b) >= P
    
    uint256 p;
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
    for (int i = 0; i < 8; i++) {
        result.limbs[i] = product.limbs[i];
    }
    
    // Final reductions
    uint256 p;
    for (int i = 0; i < 8; i++) {
        p.limbs[i] = P[i];
    }
    
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

/*
TODO: verify this once more against the other implementaations
// This is another version fully correct, but slower
// Modular inverse using Fermat's Little Theorem: a^(p-2) mod p
// For secp256k1: P-2 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2D
uint256 field_inv(uint256 a) {
    if (is_zero(a)) {
        return a;  // No inverse for zero
    }
    

    
    uint256 result;
    for (int i = 0; i < 8; i++) result.limbs[i] = 0;
    result.limbs[0] = 1;  // result = 1
    
    uint256 base = a;  // base = a
    
    // Binary exponentiation: LSB to MSB
    for (int limb = 0; limb < 8; limb++) {
        uint exp_limb = P_MINUS_2[limb];
        
        for (int bit = 0; bit < 32; bit++) {
            // If bit is set, multiply result by current base
            if ((exp_limb >> bit) & 1u) {
                result = field_mul(result, base);
            }
            
            // Square base for next bit (except on very last iteration)
            if (limb < 7 || bit < 31) {
                base = field_sqr(base);
            }
        }
    }
    
    return result;
}
*/



// Build a uint256 from the global modulus P[8]
inline uint256 mod_p_u256() {
    uint256 m;
    for (int i = 0; i < 8; i++) m.limbs[i] = P[i];
    return m;
}

// Right shift by 1 over 8×32-bit limbs; msb_in becomes the new top bit (bit 255)
inline uint256 rshift1_with_msb(uint256 a, uint msb_in) {
    uint256 r;
    uint carry = msb_in & 1u; // becomes top bit after shifting
    // walk from MS limb to LS limb
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
    for (int i = 0; i < 8; i++) t2.limbs[i] = 0;
    t2.limbs[0] = 1;

    uint256 t3; // auxiliary (for p - a^{-1})
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




// Plain comparison helper (already present, but keeping here for clarity):
// int compare(uint256 a, uint256 b) // returns -1,0,1
// bool is_equal(uint256 a, uint256 b)
// uint256 sub_uint256(uint256 a, uint256 b) // non-mod, may underflow (we guard by adding p first)




// ================ Point operations ================

Point point_double(Point p) {
  
    
    if (p.infinity) return p;
    
    // lambda = (3 * x^2) * (2 * y)^-1
    uint256 x_sqr = field_sqr(p.x);
    uint256 three_x_sqr = field_add(field_add(x_sqr, x_sqr), x_sqr);
    uint256 two_y = field_add(p.y, p.y);
    uint256 inv_two_y = field_inv(two_y);
    uint256 lambda = field_mul(three_x_sqr, inv_two_y);
    
    // x_r = lambda^2 - 2*x
    uint256 lambda_sqr = field_sqr(lambda);
    uint256 two_x = field_add(p.x, p.x);
    
    Point result;
    result.x = field_sub(lambda_sqr, two_x);
    result.y = field_sub(field_mul(lambda, field_sub(p.x, result.x)), p.y);
    result.infinity = false;
    
    return result;
}

Point point_add(Point p, Point q) {
    if (p.infinity) return q;
    if (q.infinity) return p;
    
    if (is_equal(p.x, q.x)) {
        if (is_equal(p.y, q.y)) {
            return point_double(p);
        } else {
            Point result;
            result.infinity = true;
            return result;
        }
    }
    
    // lambda = (q_y - p_y) * (q_x - p_x)^-1
    uint256 dy = field_sub(q.y, p.y);
    uint256 dx = field_sub(q.x, p.x);
    uint256 inv_dx = field_inv(dx);
    uint256 lambda = field_mul(dy, inv_dx);
    
    // x_r = lambda^2 - p_x - q_x
    uint256 lambda_sqr = field_sqr(lambda);
    
    Point result;
    result.x = field_sub(lambda_sqr, field_add(p.x, q.x));
    result.y = field_sub(field_mul(lambda, field_sub(p.x, result.x)), p.y);
    result.infinity = false;
    
    return result;
}



// Add Jacobian point structure
struct PointJacobian {
    uint256 X;
    uint256 Y;
    uint256 Z;
    bool infinity;
};

// Convert affine to Jacobian
PointJacobian affine_to_jacobian(Point p) {
    PointJacobian result;
    if (p.infinity) {
        result.infinity = true;
        return result;
    }
    
    result.X = p.x;
    result.Y = p.y;
    // Z = 1
    for (int i = 0; i < 8; i++) result.Z.limbs[i] = 0;
    result.Z.limbs[0] = 1;
    result.infinity = false;
    
    return result;
}

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

// Point doubling in Jacobian coordinates (NO INVERSION!)
// Formula from: http://hyperelliptic.org/EFD/g1p/auto-shortw-jacobian.html
PointJacobian point_double_jacobian(PointJacobian p) {
    if (p.infinity) return p;
    
    // For curve y² = x³ + 7 (secp256k1)
    // S = 4*X*Y²
    // M = 3*X² (since a=0)
    // X' = M² - 2*S
    // Y' = M*(S - X') - 8*Y⁴
    // Z' = 2*Y*Z
    
    uint256 Y_sq = field_sqr(p.Y);                    // Y²
    uint256 S = field_mul(p.X, Y_sq);                 // X*Y²
    S = field_add(S, S);                              // 2*X*Y²
    S = field_add(S, S);                              // 4*X*Y² = S
    
    uint256 X_sq = field_sqr(p.X);                    // X²
    uint256 M = field_add(X_sq, X_sq);                // 2*X²
    M = field_add(M, X_sq);                           // 3*X² = M
    
    uint256 M_sq = field_sqr(M);                      // M²
    uint256 two_S = field_add(S, S);                  // 2*S
    
    PointJacobian result;
    result.X = field_sub(M_sq, two_S);                // X' = M² - 2*S
    
    uint256 Y_sq_sq = field_sqr(Y_sq);                // Y⁴
    uint256 eight_Y4 = field_add(Y_sq_sq, Y_sq_sq);   // 2*Y⁴
    eight_Y4 = field_add(eight_Y4, eight_Y4);         // 4*Y⁴
    eight_Y4 = field_add(eight_Y4, eight_Y4);         // 8*Y⁴
    
    uint256 S_minus_X = field_sub(S, result.X);       // S - X'
    uint256 M_times = field_mul(M, S_minus_X);        // M*(S - X')
    result.Y = field_sub(M_times, eight_Y4);          // Y' = M*(S - X') - 8*Y⁴
    
    uint256 two_Y = field_add(p.Y, p.Y);              // 2*Y
    result.Z = field_mul(two_Y, p.Z);                 // Z' = 2*Y*Z
    
    result.infinity = false;
    return result;
}

// Point addition in Jacobian coordinates (NO INVERSION!)
// Mixed addition: p in Jacobian, q in affine (Z2=1)
PointJacobian point_add_mixed_jacobian(PointJacobian p, Point q) {
    if (p.infinity) return affine_to_jacobian(q);
    if (q.infinity) return p;
    
    // U1 = X1, U2 = X2*Z1²
    // S1 = Y1, S2 = Y2*Z1³
    // H = U2 - U1
    // r = S2 - S1
    
    uint256 Z1_sq = field_sqr(p.Z);                   // Z1²
    uint256 Z1_cube = field_mul(Z1_sq, p.Z);          // Z1³
    
    uint256 U2 = field_mul(q.x, Z1_sq);               // U2 = X2*Z1²
    uint256 S2 = field_mul(q.y, Z1_cube);             // S2 = Y2*Z1³
    
    uint256 H = field_sub(U2, p.X);                   // H = U2 - U1
    uint256 r = field_sub(S2, p.Y);                   // r = S2 - S1
    
    // Check if points are equal (H=0 and r=0 means double)
    if (is_zero(H)) {
        if (is_zero(r)) {
            return point_double_jacobian(p);
        } else {
            PointJacobian result;
            result.infinity = true;
            return result;
        }
    }
    
    // X3 = r² - H³ - 2*U1*H²
    // Y3 = r*(U1*H² - X3) - S1*H³
    // Z3 = H*Z1
    
    uint256 H_sq = field_sqr(H);                      // H²
    uint256 H_cube = field_mul(H_sq, H);              // H³
    uint256 U1_H_sq = field_mul(p.X, H_sq);           // U1*H²
    uint256 two_U1_H_sq = field_add(U1_H_sq, U1_H_sq); // 2*U1*H²
    
    uint256 r_sq = field_sqr(r);                      // r²
    PointJacobian result;
    result.X = field_sub(r_sq, H_cube);               // r² - H³
    result.X = field_sub(result.X, two_U1_H_sq);     // X3 = r² - H³ - 2*U1*H²
    
    uint256 diff = field_sub(U1_H_sq, result.X);     // U1*H² - X3
    uint256 r_times_diff = field_mul(r, diff);        // r*(U1*H² - X3)
    uint256 S1_H_cube = field_mul(p.Y, H_cube);       // S1*H³
    result.Y = field_sub(r_times_diff, S1_H_cube);    // Y3
    
    result.Z = field_mul(H, p.Z);                     // Z3 = H*Z1
    result.infinity = false;
    
    return result;
}

/* TODO: compare against the other, implementation which uses pre-calculated values. To do so, you need to add the generator point again in the main kernel
// Point multiplication using Jacobian coordinates
Point point_mul(Point base, uint256 scalar) {
    // Convert base to Jacobian
    PointJacobian base_jac = affine_to_jacobian(base);
    PointJacobian result;
    result.infinity = true;
    
    // Double-and-add in Jacobian space (no inversions during loop!)
    for (int limb = 7; limb >= 0; limb--) {
        uint word = scalar.limbs[limb];
        for (int bit = 31; bit >= 0; bit--) {
            if (!result.infinity) {
                result = point_double_jacobian(result);
            }
            
            if ((word >> bit) & 1u) {
                if (result.infinity) {
                    result = base_jac;
                } else {
                    // Use mixed addition (result in Jacobian, base in affine)
                    result = point_add_mixed_jacobian(result, base);
                }
            }
        }
    }
    
    // Convert back to affine (only ONE inversion for the entire multiplication!)
    return jacobian_to_affine(result);
}

*/


Point point_mul(uint256 scalar, threadgroup const Point* G_table_tg) {
    PointJacobian result;
    result.infinity = true;

    // Process scalar from most significant nibble (4 bits) to least
    for (int limb = 7; limb >= 0; limb--) {
        uint word = scalar.limbs[limb];

        #pragma unroll
        for (int nib = 7; nib >= 0; nib--) {
            // Each nibble = 4 bits
            uint nibble = (word >> (nib * 4)) & 0xFu;

            
            // Always perform 4 doublings (to shift left by 4 bits)
            if (!result.infinity) {
                for (int i = 0; i < 4; i++) {
                    result = point_double_jacobian(result);
                }
            }

            if (nibble != 0u) {
                Point addend = G_table_tg[nibble - 1];
                if (result.infinity) {
                    result = affine_to_jacobian(addend);
                } else {
                    result = point_add_mixed_jacobian(result, addend);
                }
            }
        }
    }

    // Convert back to affine (1 inversion total)
    return jacobian_to_affine(result);
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
    
    
    // START point_mul (traditional)
    //Point public_key_point = point_mul(generator, private_key);
    // END
    
    // START point_mul windowed with pre-calculated G table
    // We create copies of the G-Table in each thread group, for faster access
    threadgroup Point G_table_tg[16];
    if (lid == 0) {
        for (int i = 0; i < 16; i++) G_table_tg[i] = G_TABLE[i];
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    //END

    // Multiply generator by private key to get public key
    Point public_key_point = point_mul(private_key, G_table_tg); // Pre-calculated G values
    

    
    // Store result
    if (public_key_point.infinity) {
        for (int i = 0; i < 33; i++) {
            public_keys_comp[id * 33 + i] = 0;
        }
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
