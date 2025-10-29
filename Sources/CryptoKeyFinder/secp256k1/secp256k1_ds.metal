#include <metal_stdlib>
using namespace metal;

// ---- SECP256k1 constants (little-endian limb order) ----

// Secp256k1 prime modulus p = 2^256 - 2^32 - 977
constant uint P[8] = {
    0xFFFFFC2F, 0xFFFFFFFE, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF  // little endian limbs ordered from LS to MS
    //0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFE, 0xFFFFFC2F // reverse order
};


// Exponent p-2 for inversion: store as MSW-first for MSB->LSB scanning
//constant uint P_MINUS_2_MSW_FIRST[8] = {
//    0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFE, 0xFFFFFC2D
//};


constant uint GX[8] = {
    0x16F81798, 0x59F2815B, 0x2DCE28D9, 0x029BFCDB, 0xCE870B07, 0x55A06295, 0xF9DCBBAC, 0x79BE667E  // little endian limbs ordered from LS to MS
    //0x79BE667E, 0xF9DCBBAC, 0x55A06295, 0xCE870B07, 0x029BFCDB, 0x2DCE28D9, 0x59F2815B, 0x16F81798 // reverse order
};

constant uint GY[8] = {
    0xFB10D4B8, 0x9C47D08F, 0xA6855419, 0xFD17B448, 0x0E1108A8, 0x5DA4FBFC, 0x26A3C465, 0x483ADA77 // little endian limbs ordered from LS to MS
    //0x483ADA77, 0x26A3C465, 0x5DA4FBFC, 0x0E1108A8, 0xFD17B448, 0xA6855419, 0x9C47D08F, 0xFB10D4B8 // reverse order
};




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



// Utility functions
uint256 load_private_key(device const uint* private_keys, uint index) {
    uint256 result;
    for (int i = 0; i < 8; i++) {
        result.limbs[i] = private_keys[index * 8 + i];
    }
    return result;
}

void store_public_key(device uint* output, uint index, uint256 x, uint256 y) {
    for (int i = 0; i < 8; i++) {
        output[index * 16 + i] = x.limbs[i];      // x coordinate
        output[index * 16 + 8 + i] = y.limbs[i];  // y coordinate
    }
}

bool is_zero(uint256 a) {
    for (int i = 0; i < 8; i++) {
        if (a.limbs[i] != 0) return false;
    }
    return true;
}

bool is_equal(uint256 a, uint256 b) {
    for (int i = 0; i < 8; i++) {
        if (a.limbs[i] != b.limbs[i]) return false;
    }
    return true;
}



int compare(uint256 a, uint256 b) {
    for (int i = 7; i >= 0; i--) {
        if (a.limbs[i] > b.limbs[i]) return 1;
        if (a.limbs[i] < b.limbs[i]) return -1;
    }
    return 0;
}





// WORKS confirmed by test
uint256 field_sub(uint256 a, uint256 b) {
    uint256 result;
    uint borrow = 0;

    for (int i = 0; i < 8; i++) {
        uint ai = a.limbs[i];
        uint bi = b.limbs[i];

        // Compute raw subtraction with borrow
        uint temp = bi + borrow;
        uint new_borrow = (temp < bi) ? 1 : 0;     // overflow in temp = bi + borrow
        uint diff = ai - temp;
        if (ai < temp) new_borrow = 1;             // underflow in ai - temp

        result.limbs[i] = diff;
        borrow = new_borrow;
    }

    // If borrow remains, we need to add back the modulus P
    if (borrow) {
        uint carry = 0;
        for (int i = 0; i < 8; i++) {
            uint sum = result.limbs[i] + P[i] + carry;
            carry = (sum < result.limbs[i]) ? 1 : 0;
            result.limbs[i] = sum;
        }
    }

    return result;
}




void mul_32x32(uint a, uint b, thread uint* low, thread uint* high) {
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

void add_with_carry(uint a, uint b, uint carry_in, thread uint* result, thread uint* carry_out) {
    uint sum1 = a + b;
    uint c1 = (sum1 < a) ? 1u : 0u;
    
    uint sum2 = sum1 + carry_in;
    uint c2 = (sum2 < sum1) ? 1u : 0u;
    
    *result = sum2;
    *carry_out = c1 + c2;
}

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



//---------------
// Helper: Add two 32-bit numbers and return {low, high}
struct add_result {
    uint low;
    uint high;
};

add_result add_with_carry(uint a, uint b, uint carry_in) {
    add_result res;
    uint sum = a + b;
    uint c1 = (sum < a) ? 1u : 0u;
    sum += carry_in;
    uint c2 = (sum < carry_in) ? 1u : 0u;
    res.low = sum;
    res.high = c1 + c2;
    return res;
}


// Corrected modular reduction for secp256k1
uint256 mod_p_reduce(uint512 a) {
    uint256 result;
    
    // Start with lower 256 bits (limbs 0-7)
    for (int i = 0; i < 8; i++) {
        result.limbs[i] = a.limbs[i];
    }
    
    // We need to add: high_part * (2^32 + 977)
    // Where high_part is the upper 256 bits (limbs 8-15)
    
    // First: add high_part * 977
    uint carry = 0;
    for (int i = 0; i < 8; i++) {
        uint high_limb = a.limbs[i + 8];
        ulong product = (ulong)high_limb * 977ul + (ulong)result.limbs[i] + (ulong)carry;
        result.limbs[i] = (uint)(product & 0xFFFFFFFF);
        carry = (uint)(product >> 32);
    }
    
    // Second: add high_part * 2^32 (this means shifting high_part left by 32 bits)
    // This is equivalent to adding high_part starting at limb position 1
    uint carry2 = 0;
    for (int i = 0; i < 8; i++) {
        // We're adding to result.limbs[i+1], so we need to be careful about bounds
        if (i < 7) {
            uint high_limb = a.limbs[i + 8];
            ulong sum = (ulong)result.limbs[i + 1] + (ulong)high_limb + (ulong)carry2;
            result.limbs[i + 1] = (uint)(sum & 0xFFFFFFFF);
            carry2 = (uint)(sum >> 32);
        }
    }
    
    // Handle the remaining carry from the 2^32 addition
    // This goes beyond the 256-bit result, so we need to reduce it
    if (carry2 > 0) {
        // Add carry2 * 977 to the first limb
        ulong product = (ulong)result.limbs[0] + (ulong)carry2 * 977ul;
        result.limbs[0] = (uint)(product & 0xFFFFFFFF);
        uint new_carry = (uint)(product >> 32);
        
        // Propagate carry through remaining limbs
        for (int i = 1; i < 8 && new_carry > 0; i++) {
            ulong sum = (ulong)result.limbs[i] + (ulong)new_carry;
            result.limbs[i] = (uint)(sum & 0xFFFFFFFF);
            new_carry = (uint)(sum >> 32);
        }
    }
    
    // Handle the remaining carry from the 977 multiplication
    // This also goes beyond the 256-bit result
    if (carry > 0) {
        // Add carry * 977 to the first limb
        ulong product = (ulong)result.limbs[0] + (ulong)carry * 977ul;
        result.limbs[0] = (uint)(product & 0xFFFFFFFF);
        uint new_carry = (uint)(product >> 32);
        
        // Propagate carry through remaining limbs
        for (int i = 1; i < 8 && new_carry > 0; i++) {
            ulong sum = (ulong)result.limbs[i] + (ulong)new_carry;
            result.limbs[i] = (uint)(sum & 0xFFFFFFFF);
            new_carry = (uint)(sum >> 32);
        }
    }
    
    // Final reduction: if result >= P, subtract P
    uint256 p;
    for (int i = 0; i < 8; i++) {
        p.limbs[i] = P[i];
    }
    
    // Use your working field_sub function for final reduction
    while (compare(result, p) >= 0) {
        result = field_sub(result, p);
    }
    
    return result;
}




// Optional: Optimized field_add that uses mod_p_reduce
uint256 field_add(uint256 a, uint256 b) {
    uint512 sum;
    
    // Initialize upper half to zero
    for (int i = 8; i < 16; i++) {
        sum.limbs[i] = 0;
    }
    
    // Add with carry
    uint carry = 0;
    for (int i = 0; i < 8; i++) {
        add_result s = add_with_carry(a.limbs[i], b.limbs[i], carry);
        sum.limbs[i] = s.low;
        carry = s.high;
    }
    
    // Store carry in limb[8]
    sum.limbs[8] = carry;
    
    return mod_p_reduce(sum);
}
//---------------







uint256 field_sqr(uint256 a) {
    return field_mul(a, a);
}




// Modular inverse using Fermat's Little Theorem: a^(p-2) mod p
// For secp256k1: P-2 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2D
uint256 field_inv(uint256 a) {
    if (is_zero(a)) {
        return a;  // No inverse for zero
    }
    
    // P-2 in little-endian limb order (LSW first)
    const uint exp[8] = {
        0xFFFFFC2D,  // limb 0 (bits 0-31)
        0xFFFFFFFE,  // limb 1 (bits 32-63)
        0xFFFFFFFF,  // limb 2 (bits 64-95)
        0xFFFFFFFF,  // limb 3 (bits 96-127)
        0xFFFFFFFF,  // limb 4 (bits 128-159)
        0xFFFFFFFF,  // limb 5 (bits 160-191)
        0xFFFFFFFF,  // limb 6 (bits 192-223)
        0xFFFFFFFF   // limb 7 (bits 224-255, MSW)
    };
    
    uint256 result;
    for (int i = 0; i < 8; i++) result.limbs[i] = 0;
    result.limbs[0] = 1;  // result = 1
    
    uint256 base = a;  // base = a
    
    // Binary exponentiation: LSB to MSB
    for (int limb = 0; limb < 8; limb++) {
        uint exp_limb = exp[limb];
        
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


// Point operations
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

// Corrected point multiplication (double-and-add, MSB to LSB)
Point point_mul(Point base, uint256 scalar) {
    Point result;
    result.infinity = true;

    for (int limb = 7; limb >= 0; limb--) {           // MSB first
        uint word = scalar.limbs[limb];
        for (int bit = 31; bit >= 0; bit--) {         // MSB first
            if (!result.infinity) result = point_double(result);
            if ((word >> bit) & 1u) {
                if (result.infinity) result = base;
                else result = point_add(result, base);
            }
        }
    }
    return result;
}







kernel void test_mod_p_reduce(
    device const uint512* inputs [[buffer(0)]],
    device uint256* outputs [[buffer(1)]],
    uint id [[thread_position_in_grid]]
) {
    outputs[id] = mod_p_reduce(inputs[id]);
}





kernel void tmp_test_fixes(
    device const uint* private_keys [[buffer(0)]],
    device uint* debug_output [[buffer(1)]],
    uint id [[thread_position_in_grid]]
) {
    

    
    uint256 priv_key = load_private_key(private_keys, id);
    
    // Test 1: Multiply private key by 1 (should return private key)
    uint256 one = {2, 0, 0, 0, 0, 0, 0, 0};
    //uint256 result = field_mul(priv_key, one);
    
    uint512 t1 = {2, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 1};
    
    uint256 result = mod_p_reduce(t1);
    //uint256 result = field_inv(priv_key);
    
    //uint256 inv = field_inv(one);
    //uint256 result = field_mul(one, inv);
    
    
    // Store  results for comparison
    for (int i = 0; i < 8; i++) {
        debug_output[id * 8 + i] = result.limbs[i];
       
    }
}


// Main kernel - converts private keys to public keys
kernel void private_to_public_keys(
    device const uint* private_keys [[buffer(0)]],
    device uint* public_keys [[buffer(1)]],
    uint id [[thread_position_in_grid]]
) {
    // Load private key for this thread
    uint256 private_key = load_private_key(private_keys, id);
    
    // Skip if private key is zero
    if (is_zero(private_key)) {
        for (int i = 0; i < 16; i++) {
            public_keys[id * 16 + i] = 0;
        }
        return;
    }
    
    // Create generator point
    Point generator;
    generator.x = { GX[0], GX[1], GX[2], GX[3], GX[4], GX[5], GX[6], GX[7] };
    generator.y = { GY[0], GY[1], GY[2], GY[3], GY[4], GY[5], GY[6], GY[7] };
    
    //generator.x = { GX[7], GX[6], GX[5], GX[4], GX[3], GX[2], GX[1], GX[0] };
    //generator.y = { GY[7], GY[6], GY[5], GY[4], GY[3], GY[2], GY[1], GY[0] };
    
    generator.infinity = false;
    
    // Multiply generator by private key to get public key
    Point public_key_point = point_mul(generator, private_key);
    
    // Store result
    if (public_key_point.infinity) {
        for (int i = 0; i < 16; i++) {
            public_keys[id * 16 + i] = 0;
        }
    } else {
        store_public_key(public_keys, id, public_key_point.x, public_key_point.y);
    }
}

// ============= Test Kernels ==============

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
