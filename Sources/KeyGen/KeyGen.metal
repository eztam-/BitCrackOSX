#include <metal_stdlib>
using namespace metal;



/// currentKey: 8 uint limbs (little-endian).
/// outKeys: destination array: (numThreads) * 8 uints
///
/// Each thread writes outKeys[gid*8 + 0..7] = currentKey + offset256 + gid
kernel void generate_keys(
                          device uint* currentKey     [[ buffer(0) ]], // 8 elements
                          device uint*       outKeys      [[ buffer(1) ]],
                          constant uint& numKeys [[ buffer(2) ]],
                          uint               gid          [[ thread_position_in_grid ]])
{
    // Load start key
    uint s0 = currentKey[0];
    uint s1 = currentKey[1];
    uint s2 = currentKey[2];
    uint s3 = currentKey[3];
    uint s4 = currentKey[4];
    uint s5 = currentKey[5];
    uint s6 = currentKey[6];
    uint s7 = currentKey[7];
    
    
    // Add start + offset + gid (gid fits in 32-bits).
    // Use 64-bit temporaries to capture carry.
    // Limb 0: add s0 + o0 + gid
    ulong t = (ulong)s0 + (ulong)gid;
    uint r0 = (uint)t;
    uint carry = (uint)(t >> 32);
    
    // Limb 1: s1 + o1 + carry
    t = (ulong)s1 + (ulong)carry;
    uint r1 = (uint)t;
    carry = (uint)(t >> 32);
    
    // Propagate through remaining limbs
    t = (ulong)s2 + (ulong)carry; uint r2 = (uint)t; carry = (uint)(t >> 32);
    t = (ulong)s3 + (ulong)carry; uint r3 = (uint)t; carry = (uint)(t >> 32);
    t = (ulong)s4 + (ulong)carry; uint r4 = (uint)t; carry = (uint)(t >> 32);
    t = (ulong)s5 + (ulong)carry; uint r5 = (uint)t; carry = (uint)(t >> 32);
    t = (ulong)s6 + (ulong)carry; uint r6 = (uint)t; carry = (uint)(t >> 32);
    t = (ulong)s7 + (ulong)carry; uint r7 = (uint)t; /*carry beyond 256 bits ignored*/
    
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
    
        
    // Only the LAST thread updates the persistent currentKey
      if (gid == numKeys - 1) {
          // Compute next batch start = currentKey + numThreads
          ulong tt = (ulong)s0 + (ulong)numKeys;
          uint n0 = (uint)tt; uint c = (uint)(tt >> 32);
          tt = (ulong)s1 + (ulong)c; uint n1 = (uint)tt; c = (uint)(tt >> 32);
          tt = (ulong)s2 + (ulong)c; uint n2 = (uint)tt; c = (uint)(tt >> 32);
          tt = (ulong)s3 + (ulong)c; uint n3 = (uint)tt; c = (uint)(tt >> 32);
          tt = (ulong)s4 + (ulong)c; uint n4 = (uint)tt; c = (uint)(tt >> 32);
          tt = (ulong)s5 + (ulong)c; uint n5 = (uint)tt; c = (uint)(tt >> 32);
          tt = (ulong)s6 + (ulong)c; uint n6 = (uint)tt; c = (uint)(tt >> 32);
          tt = (ulong)s7 + (ulong)c; uint n7 = (uint)tt;

          currentKey[0] = n0;
          currentKey[1] = n1;
          currentKey[2] = n2;
          currentKey[3] = n3;
          currentKey[4] = n4;
          currentKey[5] = n5;
          currentKey[6] = n6;
          currentKey[7] = n7;
      }
}
