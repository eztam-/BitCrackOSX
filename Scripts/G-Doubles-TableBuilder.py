# Generate 8 precomputed doublings of secp256k1 G in Metal C array syntax
# Requires: pip install ecdsa

from ecdsa import SECP256k1

# Number of points to generate (doublings)
COUNT = 8
G = SECP256k1.generator

def int_to_le32_words(x: int) -> list[int]:
    """Convert integer to 8 little-endian 32-bit words."""
    return [(x >> (32 * i)) & 0xFFFFFFFF for i in range(8)]

def fmt_words(words):
    """Format list of 8 32-bit words for Metal constant arrays."""
    return ", ".join(f"0x{w:08x}" for w in words)

print("constant Point G_DOUBLES[8] = {")
for i in range(COUNT):
    P = G * (1 << i)  # doubling: G, 2G, 4G, 8G, ...
    x_words = int_to_le32_words(P.x())
    y_words = int_to_le32_words(P.y())
    print("    {")
    print(f"        {{ {fmt_words(x_words)} }},")
    print(f"        {{ {fmt_words(y_words)} }},")
    print("        false")
    print("    },")
print("};")
