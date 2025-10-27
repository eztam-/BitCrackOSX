#include <metal_stdlib>
using namespace metal;

// SECP256k1 constants

// Secp256k1 prime modulus p = 2^256 - 2^32 - 977
constant uint P[8] = {
    0xFFFFFC2F, 0xFFFFFFFE, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF
    // 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFE, 0xFFFFFC2F // reverse order
};

constant uint GX[8] = {
    0x16F81798, 0x59F2815B, 0x2DCE28D9, 0x029BFCDB, 0xCE870B07, 0x55A06295, 0xF9DCBBAC, 0x79BE667E
    //0x79BE667E, 0xF9DCBBAC, 0x55A06295, 0xCE870B07, 0x029BFCDB, 0x2DCE28D9, 0x59F2815B, 0x16F81798 // reverse order
};

constant uint GY[8] = {
    0xFB10D4B8, 0x9C47D08F, 0xA6855419, 0xFD17B448, 0x0E1108A8, 0x5DA4FBFC, 0x26A3C465, 0x483ADA77
    // 0x483ADA77, 0x26A3C465, 0x5DA4FBFC, 0x0E1108A8, 0xFD17B448, 0xA6855419, 0x9C47D08F, 0xFB10D4B8 // reverse order
};

struct uint256 {
    uint limbs[8];
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

// Modular arithmetic
uint256 field_add(uint256 a, uint256 b) {
    uint256 result;
    uint carry = 0;

    // Add a + b + carry
    for (int i = 0; i < 8; i++) {
        uint ai = a.limbs[i];
        uint bi = b.limbs[i];

        uint sum = ai + bi + carry;

        // Detect overflow
        carry = (sum < ai || (carry && sum == ai)) ? 1 : 0;

        result.limbs[i] = sum;
    }

    // Prepare modulus P
    uint256 p;
    for (int i = 0; i < 8; i++) {
        p.limbs[i] = P[i];
    }

    // If carry or result >= P, subtract P
    if (carry || compare(result, p) >= 0) {
        uint borrow = 0;
        for (int i = 0; i < 8; i++) {
            uint ri = result.limbs[i];
            uint pi = p.limbs[i];

            uint temp = pi + borrow;
            uint new_borrow = (temp < pi) ? 1 : 0;
            uint diff = ri - temp;
            if (ri < temp) new_borrow = 1;

            result.limbs[i] = diff;
            borrow = new_borrow;
        }
    }

    return result;
}




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

// TODO: This version is mathematically correct but not yet highly optimized for GPU parallelism.
// Once correctness is confirmed, you can:
// Unroll the 8×8 loops.
// Use threadgroup memory for partial products.
// Pipeline carry computation.
uint256 field_mul(uint256 a, uint256 b) {
    uint product[16];
    for (int i = 0; i < 16; i++) product[i] = 0;

    // 256-bit × 256-bit schoolbook multiplication
    for (int i = 0; i < 8; i++) {
        uint carry = 0;
        for (int j = 0; j < 8; j++) {
            int idx = i + j;

            // Multiply 32x32 -> 64 using 32-bit parts
            uint ai = a.limbs[i];
            uint bj = b.limbs[j];

            uint lo = (ai & 0xFFFF) * (bj & 0xFFFF);
            uint hi = (ai >> 16) * (bj >> 16);
            uint cross1 = (ai >> 16) * (bj & 0xFFFF);
            uint cross2 = (ai & 0xFFFF) * (bj >> 16);

            uint mid = (cross1 + cross2);
            uint carry_mid = (mid < cross1) ? 1 : 0;

            uint low32 = lo + (mid << 16);
            uint carry_low = (low32 < lo) ? 1 : 0;

            uint high32 = hi + (mid >> 16) + carry_mid + carry_low;

            // Add to product[idx]
            uint sum = product[idx] + low32 + carry;
            uint carry_out = (sum < product[idx]) ? 1 : 0;
            product[idx] = sum;
            carry = high32 + carry_out;
        }

        if (i + 8 < 16) {
            uint sum = product[i + 8] + carry;
            product[i + 8] = sum;
        }
    }

    // Modular reduction (simplified: subtract once if > P)
    uint256 result;
    for (int i = 0; i < 8; i++) {
        result.limbs[i] = product[i + 8]; // take upper 256 bits
    }

    // Simple reduction
    uint borrow = 0;
    uint256 p;
    for (int i = 0; i < 8; i++) p.limbs[i] = P[i];

    if (compare(result, p) >= 0) {
        for (int i = 0; i < 8; i++) {
            uint ri = result.limbs[i];
            uint pi = p.limbs[i];
            uint temp = pi + borrow;
            uint new_borrow = (temp < pi) ? 1 : 0;
            uint diff = ri - temp;
            if (ri < temp) new_borrow = 1;
            result.limbs[i] = diff;
            borrow = new_borrow;
        }
    }

    return result;
}


uint256 field_sqr(uint256 a) {
    return field_mul(a, a);
}

uint256 field_inv(uint256 a) {
    // Compute a^(P-2) mod P using Fermat's Little Theorem
    uint256 result;
    
    // Initialize result to 1
    //for (int i = 0; i < 7; i++) result.limbs[i] = 0;
    //result.limbs[7] = 1;
    
    for (int i = 0; i < 8; i++) result.limbs[i] = 0;
    result.limbs[0] = 1; // LSW = 1 (little-endian limbs)
    
    uint256 power = a;
    
    // Exponent: P - 2
    for (int word = 0; word < 8; word++) {
        uint exp_word;
        switch (word) {
            case 0: exp_word = 0xFFFFFFFD; break;
            case 1: case 2: case 3: case 4: case 5: case 6: exp_word = 0xFFFFFFFF; break;
            case 7: exp_word = 0xFFFFFFFF; break;
            default: exp_word = 0; break;
        }
        
        for (int bit = 0; bit < 32; bit++) {
            if (exp_word & (1u << bit)) {
                result = field_mul(result, power);
            }
            power = field_sqr(power);
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

Point point_mul(Point base, uint256 scalar) {
    Point result;
    result.infinity = true;
    
    Point current = base;
    
    for (int word = 0; word < 8; word++) {
        uint scalar_word = scalar.limbs[word];
        for (int bit = 0; bit < 32; bit++) {
            if (scalar_word & (1u << bit)) {
                if (result.infinity) {
                    result = current;
                } else {
                    result = point_add(result, current);
                }
            }
            current = point_double(current);
        }
    }
    
    return result;
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
