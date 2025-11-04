/**
 
 This script is only used once, to generate the pre-calculated G-Table that has been copied inot secp256k1.metal
 
 */

from ecdsa import SECP256k1

def limbs_le(hex_str):
    """Split a 64-hex-digit string into 8×32-bit words (LSW→MSW)."""
    return [
        "0x" + hex_str[i:i+8] for i in range(56, -1, -8)
    ]

G = SECP256k1.generator

for i in range(1, 17):  # 1·G through 16·G
    P = i * G
    x_hex = f"{P.x():064x}"
    y_hex = f"{P.y():064x}"

    x_limbs = ", ".join(limbs_le(x_hex))
    y_limbs = ", ".join(limbs_le(y_hex))

    print(f"{{ {{ {x_limbs} }}, {{ {y_limbs} }}, false }},")
