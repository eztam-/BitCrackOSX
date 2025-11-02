#include <metal_stdlib>
using namespace metal;


/*
 
 Notes, variants & tuning

 Per-thread increment larger than 32 bits: thread_position_in_grid is a uint (32-bit). If your grid could exceed 4,294,967,295 or you want to support adding a larger per-thread index (e.g., 64-bit per-thread increment or combination of a per-dispatch 256-bit base + per-thread 64-bit extra), pass that extra value in another buffer and add it to limb0/1 before carry propagation. Example: add extraLow32 to limb0 and extraHigh32 to limb1.

 Performance: using .storageModePrivate for outBuf and keeping subsequent processing on GPU avoids slow CPU readbacks. Tune threadsPerThreadgroup with pipeline.threadExecutionWidth and maxTotalThreadsPerThreadgroup.

 No branching & minimal work: kernel performs exactly 8 limb additions + carry propagation per thread (cheap), so it scales well.

 Overflow beyond 256 bits is ignored (typical for iterators rolling over). If you need to detect overflow, capture final carry.

 If you want to add a per-dispatch 256-bit base and a per-thread 256-bit per-thread offset (rare), you can make offset256 an array of numThreads×8 limbs and index by gid*8.
 
 */





/// startKey: 8 uint limbs (little-endian).
/// offset256: 8 uint limbs (little-endian) - arbitrary 256-bit offset for this dispatch.
/// outKeys: destination array: (numThreads) * 8 uints
///
/// Each thread writes outKeys[gid*8 + 0..7] = startKey + offset256 + gid
kernel void generate_keys_256_offset(
    device const uint* startKey     [[ buffer(0) ]], // 8 elements
    device const uint* offset256    [[ buffer(1) ]], // 8 elements
    device uint*       outKeys      [[ buffer(2) ]],
    uint               gid          [[ thread_position_in_grid ]])
{
    // Load start key
    uint s0 = startKey[0];
    uint s1 = startKey[1];
    uint s2 = startKey[2];
    uint s3 = startKey[3];
    uint s4 = startKey[4];
    uint s5 = startKey[5];
    uint s6 = startKey[6];
    uint s7 = startKey[7];

    // Load 256-bit offset
    uint o0 = offset256[0];
    uint o1 = offset256[1];
    uint o2 = offset256[2];
    uint o3 = offset256[3];
    uint o4 = offset256[4];
    uint o5 = offset256[5];
    uint o6 = offset256[6];
    uint o7 = offset256[7];

    // Add start + offset + gid (gid fits in 32-bits).
    // Use 64-bit temporaries to capture carry.
    // Limb 0: add s0 + o0 + gid
    ulong t = (ulong)s0 + (ulong)o0 + (ulong)gid;
    uint r0 = (uint)t;
    uint carry = (uint)(t >> 32);

    // Limb 1: s1 + o1 + carry
    t = (ulong)s1 + (ulong)o1 + (ulong)carry;
    uint r1 = (uint)t;
    carry = (uint)(t >> 32);

    // Propagate through remaining limbs
    t = (ulong)s2 + (ulong)o2 + (ulong)carry; uint r2 = (uint)t; carry = (uint)(t >> 32);
    t = (ulong)s3 + (ulong)o3 + (ulong)carry; uint r3 = (uint)t; carry = (uint)(t >> 32);
    t = (ulong)s4 + (ulong)o4 + (ulong)carry; uint r4 = (uint)t; carry = (uint)(t >> 32);
    t = (ulong)s5 + (ulong)o5 + (ulong)carry; uint r5 = (uint)t; carry = (uint)(t >> 32);
    t = (ulong)s6 + (ulong)o6 + (ulong)carry; uint r6 = (uint)t; carry = (uint)(t >> 32);
    t = (ulong)s7 + (ulong)o7 + (ulong)carry; uint r7 = (uint)t; /*carry beyond 256 bits ignored*/

    // Write result in little-endian limb order
    uint outIndex = gid * 8u;
    outKeys[outIndex + 0u] = r0;
    outKeys[outIndex + 1u] = r1;
    outKeys[outIndex + 2u] = r2;
    outKeys[outIndex + 3u] = r3;
    outKeys[outIndex + 4u] = r4;
    outKeys[outIndex + 5u] = r5;
    outKeys[outIndex + 6u] = r6;
    outKeys[outIndex + 7u] = r7;
}
