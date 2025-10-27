#include <metal_stdlib>
using namespace metal;

// SECP256k1 constants
constant uint P[8] = {
    0xFFFFFC2F, 0xFFFFFFFE, 0xFFFFFFFF, 0xFFFFFFFF,
    0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF
};

constant uint GX[8] = {
    0x16F81798, 0x59F2815B, 0x2DCE28D9, 0x029BFCDB,
    0xCE870B07, 0x55A06295, 0xF9DCBBAC, 0x79BE667E
};

constant uint GY[8] = {
    0xFB10D4B8, 0x9C47D08F, 0xA6855419, 0xFD17B448,
    0x0E1108A8, 0x5DA4FBFC, 0x26A3C465, 0x483ADA77
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
    
    for (int i = 0; i < 8; i++) {
        ulong sum = (ulong)a.limbs[i] + (ulong)b.limbs[i] + (ulong)carry;
        result.limbs[i] = uint(sum & 0xFFFFFFFF);
        carry = uint(sum >> 32);
    }
    
    // Reduce modulo P if necessary
    uint256 p;
    for (int i = 0; i < 8; i++) p.limbs[i] = P[i];
    
    if (carry || compare(result, p) >= 0) {
        uint borrow = 0;
        for (int i = 0; i < 8; i++) {
            long diff = (long)result.limbs[i] - (long)p.limbs[i] - (long)borrow;
            borrow = (diff < 0) ? 1 : 0;
            result.limbs[i] = uint(diff & 0xFFFFFFFF);
        }
    }
    
    return result;
}

uint256 field_sub(uint256 a, uint256 b) {
    uint256 result;
    uint borrow = 0;
    
    for (int i = 0; i < 8; i++) {
        long diff = (long)a.limbs[i] - (long)b.limbs[i] - (long)borrow;
        borrow = (diff < 0) ? 1 : 0;
        result.limbs[i] = uint(diff & 0xFFFFFFFF);
    }
    
    if (borrow) {
        uint carry = 0;
        for (int i = 0; i < 8; i++) {
            ulong sum = (ulong)result.limbs[i] + (ulong)P[i] + (ulong)carry;
            result.limbs[i] = uint(sum & 0xFFFFFFFF);
            carry = uint(sum >> 32);
        }
    }
    
    return result;
}

uint256 field_mul(uint256 a, uint256 b) {
    ulong product[16] = {0};
    
    // Schoolbook multiplication
    for (int i = 0; i < 8; i++) {
        ulong carry = 0;
        for (int j = 0; j < 8; j++) {
            int idx = i + j;
            ulong temp = product[idx] + (ulong)a.limbs[i] * (ulong)b.limbs[j] + carry;
            product[idx] = temp & 0xFFFFFFFF;
            carry = temp >> 32;
        }
        if (i + 8 < 16) {
            product[i + 8] += carry;
        }
    }
    
    // Montgomery reduction for SECP256k1
    uint256 result;
    
    for (int i = 0; i < 8; i++) {
        ulong m = product[i] * 0xD838091DD2253531UL; // Inverse of P mod 2^64
        
        ulong carry = 0;
        for (int j = 0; j < 8; j++) {
            ulong temp = product[i + j] + m * (ulong)P[j] + carry;
            product[i + j] = temp & 0xFFFFFFFF;
            carry = temp >> 32;
        }
        
        // Propagate carry
        for (int j = i + 8; j < 16 && carry > 0; j++) {
            ulong temp = product[j] + carry;
            product[j] = temp & 0xFFFFFFFF;
            carry = temp >> 32;
        }
    }
    
    // Copy result from upper half
    for (int i = 0; i < 8; i++) {
        result.limbs[i] = uint(product[i + 8]);
    }
    
    // Final reduction
    uint256 p_val;
    for (int i = 0; i < 8; i++) p_val.limbs[i] = P[i];
    
    if (compare(result, p_val) >= 0) {
        uint borrow = 0;
        for (int i = 0; i < 8; i++) {
            long diff = (long)result.limbs[i] - (long)P[i] - (long)borrow;
            borrow = (diff < 0) ? 1 : 0;
            result.limbs[i] = uint(diff & 0xFFFFFFFF);
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
    for (int i = 0; i < 7; i++) result.limbs[i] = 0;
    result.limbs[7] = 1;
    
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
    for (int i = 0; i < 8; i++) {
        generator.x.limbs[i] = GX[i];
        generator.y.limbs[i] = GY[i];
    }
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
