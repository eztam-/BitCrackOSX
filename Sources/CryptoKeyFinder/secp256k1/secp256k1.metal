// Source from: https://github.com/haqatak/anotherbit/blob/master/MetalKeySearchDevice/keysearch.metal

#include <metal_stdlib>

using namespace metal;

// Define a 256-bit unsigned integer type
struct uint256_t {
    uint v[8];
};

// Prime modulus 2^256 - 2^32 - 977
constant uint _P[8] = {
    0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFE, 0xFFFFFC2F
};

// Base point X
constant uint _GX[8] = {
    0x79BE667E, 0xF9DCBBAC, 0x55A06295, 0xCE870B07, 0x029BFCDB, 0x2DCE28D9, 0x59F2815B, 0x16F81798
};

// Base point Y
constant uint _GY[8] = {
    0x483ADA77, 0x26A3C465, 0x5DA4FBFC, 0x0E1108A8, 0xFD17B448, 0xA6855419, 0x9C47D08F, 0xFB10D4B8
};

// Group order
constant uint _N[8] = {
    0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFE, 0xBAAEDCE6, 0xAF48A03B, 0xBFD25E8C, 0xD0364141
};

// Infinity representation
constant uint _INFINITY[8] = {
    0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF
};

// Add with carry
uint addc(uint a, uint b, thread uint* carry) {
    ulong sum = (ulong)a + *carry;
    *carry = (sum >> 32);
    sum += b;
    *carry += (sum >> 32);
    return (uint)sum;
}

// Subtract with borrow
uint subc(uint a, uint b, thread uint* borrow) {
    ulong diff = (ulong)a - *borrow;
    *borrow = (diff >> 32) & 1;
    diff -= b;
    *borrow += (diff >> 32) & 1;
    return (uint)diff;
}

// 32x32 -> 64 multiply
ulong mul64(uint a, uint b) {
    return (ulong)a * b;
}

// 32x32 multiply-add
void madd(thread uint* high, thread uint* low, uint a, uint b, uint c) {
    ulong product = mul64(a, b) + c;
    *low = (uint)product;
    *high = (uint)(product >> 32);
}

uint256_t add256k(uint256_t a, uint256_t b, thread uint* carry) {
    uint256_t c;
    *carry = 0;
    for (int i = 7; i >= 0; i--) {
        c.v[i] = addc(a.v[i], b.v[i], carry);
    }
    return c;
}

uint256_t sub256k(uint256_t a, uint256_t b, thread uint* borrow) {
    uint256_t c;
    *borrow = 0;
    for (int i = 7; i >= 0; i--) {
        c.v[i] = subc(a.v[i], b.v[i], borrow);
    }
    return c;
}

void multiply256(uint256_t x, uint256_t y, thread uint256_t* out_high, thread uint256_t* out_low) {
    uint z[16] = {0};
    uint high = 0;

    for (int j = 7; j >= 0; j--) {
        ulong product = mul64(x.v[7], y.v[j]) + high;
        z[7 + j + 1] = (uint)product;
        high = (uint)(product >> 32);
    }
    z[7] = high;

    for (int i = 6; i >= 0; i--) {
        high = 0;
        for (int j = 7; j >= 0; j--) {
            ulong product = mul64(x.v[i], y.v[j]) + z[i + j + 1] + high;
            z[i + j + 1] = (uint)product;
            high = (uint)(product >> 32);
        }
        z[i] = high;
    }

    for (int i = 0; i < 8; i++) {
        out_high->v[i] = z[i];
        out_low->v[i] = z[8 + i];
    }
}

bool isInfinity(uint256_t p) {
    for (int i = 0; i < 8; i++) {
        if (p.v[i] != 0xffffffff) {
            return false;
        }
    }
    return true;
}

bool greaterThanEqualToP(uint256_t a) {
    for(int i = 0; i < 8; i++) {
        if(a.v[i] > _P[i]) {
            return true;
        } else if(a.v[i] < _P[i]) {
            return false;
        }
    }
    return true;
}

uint256_t subModP256k(uint256_t a, uint256_t b) {
    uint borrow = 0;
    uint256_t c = sub256k(a, b, &borrow);
    if (borrow) {
        uint carry = 0;
        add256k(c, (uint256_t){_P[0], _P[1], _P[2], _P[3], _P[4], _P[5], _P[6], _P[7]}, &carry);
    }
    return c;
}

uint256_t addModP256k(uint256_t a, uint256_t b) {
    uint carry = 0;
    uint256_t c = add256k(a, b, &carry);
    if (carry || greaterThanEqualToP(c)) {
        uint borrow = 0;
        sub256k(c, (uint256_t){_P[0], _P[1], _P[2], _P[3], _P[4], _P[5], _P[6], _P[7]}, &borrow);
    }
    return c;
}

uint256_t mulModP256k(uint256_t a, uint256_t b) {
    uint256_t high, low;
    multiply256(a, b, &high, &low);

    // This is a simplified version of the modular reduction from the OpenCL code.
    // A full implementation is required for correctness.
    // For now, just return the low part of the product.
    return low;
}

uint256_t squareModP256k(uint256_t a) {
    return mulModP256k(a, a);
}

// Modular inverse using Fermat's Little Theorem
uint256_t invModP256k(uint256_t n) {
    // Simplified version, a full implementation is required
    return n;
}

void point_add(thread uint256_t* p1x, thread uint256_t* p1y, uint256_t p2x, uint256_t p2y, thread uint256_t* p3x, thread uint256_t* p3y) {
    if (isInfinity(*p1x)) {
        *p3x = p2x;
        *p3y = p2y;
        return;
    }
    if (isInfinity(p2x)) {
        *p3x = *p1x;
        *p3y = *p1y;
        return;
    }

    uint256_t s;
    if (equal(*p1x, p2x)) {
        if (equal(*p1y, p2y)) {
            // Point doubling
            uint256_t n = addModP256k(*p1y, *p1y);
            n = invModP256k(n);
            uint256_t m = squareModP256k(*p1x);
            m = addModP256k(m, m);
            m = addModP256k(m, m); // 3x^2
            s = mulModP256k(m, n);
        } else {
            // Points are opposite, return infinity
            for (int i = 0; i < 8; i++) {
                p3x->v[i] = 0xffffffff;
                p3y->v[i] = 0xffffffff;
            }
            return;
        }
    } else {
        uint256_t n = subModP256k(p2x, *p1x);
        n = invModP256k(n);
        uint256_t m = subModP256k(p2y, *p1y);
        s = mulModP256k(m, n);
    }

    uint256_t s2 = squareModP256k(s);
    uint256_t rx = subModP256k(s2, *p1x);
    rx = subModP256k(rx, p2x);
    uint256_t ry = subModP256k(*p1x, rx);
    ry = mulModP256k(s, ry);
    ry = subModP256k(ry, *p1y);
    *p3x = rx;
    *p3y = ry;
}

kernel void generate_public_key(
    device const uint256_t* private_keys,
    device uint256_t* public_keys_x,
    device uint256_t* public_keys_y,
    uint gid [[thread_position_in_grid]])
{
    uint256_t private_key = private_keys[gid];
    uint256_t px = { _GX[0], _GX[1], _GX[2], _GX[3], _GX[4], _GX[5], _GX[6], _GX[7] };
    uint256_t py = { _GY[0], _GY[1], _GY[2], _GY[3], _GY[4], _GY[5], _GY[6], _GY[7] };

    uint256_t tx, ty;
    for (int i = 0; i < 256; i++) {
        if ((private_key.v[7 - i / 32] >> (i % 32)) & 1) {
            point_add(&px, &py, tx, ty, &px, &py);
        }
        point_add(&tx, &ty, tx, ty, &tx, &ty);
    }

    public_keys_x[gid] = px;
    public_keys_y[gid] = py;
}

bool equal(uint256_t a, uint256_t b) {
    for (int i = 0; i < 8; i++) {
        if (a.v[i] != b.v[i]) {
            return false;
        }
    }
    return true;
}
