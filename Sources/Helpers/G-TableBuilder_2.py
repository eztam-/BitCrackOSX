# generate_G_TABLE256.py
from ecdsa import ellipticcurve, curves

# Use secp256k1 curve parameters
secp256k1 = curves.SECP256k1
G = secp256k1.generator
p = secp256k1.curve.p()

def uint256_to_limbs_le(value):
    """Convert a 256-bit integer to 8 little-endian 32-bit limbs"""
    limbs = []
    for i in range(8):
        limbs.append(value & 0xFFFFFFFF)
        value >>= 32
    return limbs

def format_point(i, P):
    """Format a Point as Metal syntax with limbs in little-endian order"""
    x_limbs = uint256_to_limbs_le(P.x())
    y_limbs = uint256_to_limbs_le(P.y())

    fmt = "    {{ {{ {} }}, {{ {} }}, false }}".format(
        ", ".join(f"0x{w:08x}" for w in x_limbs),
        ", ".join(f"0x{w:08x}" for w in y_limbs)
    )

    if i < 255:
        fmt += ","
    return fmt

def main():
    print("constant Point G_TABLE256[256] = {")
    P = G
    for i in range(256):
        print(format_point(i, P))
        P = P + G  # next multiple
    print("};")

if __name__ == "__main__":
    main()
