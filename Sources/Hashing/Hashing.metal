//  Combined SHA-256 + RIPEMD-160 (hash160)
#include <metal_stdlib>
using namespace metal;

#include "SHA256.metal"
#include "RIPEMD160.metal"


// ==========================
// Combined Kernel: SHA-256 -> RIPEMD-160
// ==========================
//
// Input:
//   buffer(0): messages (uchar*), numMessages * messageSize bytes
//   buffer(2): SHA256Constants { numMessages, messageSize }
//
// Output:
//   buffer(1): outHashes — 5 uint per message = RIPEMD-160(SHA256(msg))
//
kernel void sha256_ripemd160_batch_kernel(
    const device uchar*         messages       [[ buffer(0) ]],
    device uint*                outHashes      [[ buffer(1) ]],
    constant SHA256Constants&   c              [[ buffer(2) ]],
    uint                        gid            [[ thread_position_in_grid ]]
)
{
    if (gid >= c.numMessages) return;

    uint offset = gid * c.messageSize;

    // ---- SHA-256 ----
    uint shaState[8];
    sha256(messages, offset, c.messageSize, shaState);

    // ---- RIPEMD-160(SHA256(msg)) ----
    uint ripemdOut[5];
    ripemd160(shaState, ripemdOut);

    // ---- store output ----
    uint dst = gid * 5u;
    outHashes[dst + 0] = ripemdOut[0];
    outHashes[dst + 1] = ripemdOut[1];
    outHashes[dst + 2] = ripemdOut[2];
    outHashes[dst + 3] = ripemdOut[3];
    outHashes[dst + 4] = ripemdOut[4];
}

