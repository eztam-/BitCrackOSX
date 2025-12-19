#pragma clang fp contract(fast)
#include <metal_stdlib>
using namespace metal;

#include "Secp256k1.metal"
#include "Sha256.metal"
#include "Ripemd160.metal"
#include "BloomFilter.metal"

#pragma clang optimize on


struct HitResult
{
    uint index;      // point index (iForward)
    uint digest[5];  // hash160
};

constant uint BLOOM_MAX_HITS = 100000; // This needs to be exactly aligned with the corresponding value on host side

//Adds ΔG to all points each iteration.
//
//  EC step kernel for Metal
//
//  Performs batch EC addition for ALL points in (xPtr, yPtr) using:
//      Q[i] = Q[i] + ΔG
//  where ΔG = (incX, incY)
//
//
// Important launch requirements!
// You must launch this kernel with:
//   numThreads = gridSize
//   totalPoints ≥ gridSize
// Adds ΔG to all points and does:
//   Q[i] -> pubkey -> SHA-256 -> RIPEMD-160 -> Bloom
//
// Inputs:
//   buffer(0): totalPoints    (constant uint)
//   buffer(1): gridSize       (constant uint)
//   buffer(2): chain          (device uint256*)
//   buffer(3): xPtr           (device uint256*)
//   buffer(4): yPtr           (device uint256*)
//   buffer(5): incX           (constant uint256)
//   buffer(6): incY           (constant uint256)
//   buffer(7): bloomBits      (device uint*)   bloom bit array
//   buffer(8): m_bits         (constant uint)  bloom bit count
//   buffer(9): bloomResults   (device uint*)   per-point 0/1
//   buffer(10): outRipemd160  (device uint*)   5 uints per point
//   buffer(11): compression   (constant uint)  0=uncompressed,1=compressed
//
kernel void step_points(
    constant uint&       totalPoints   [[buffer(0)]],
    constant uint&       gridSize      [[buffer(1)]],
    device   uint256*    chain         [[buffer(2)]],
    device   uint256*    xPtr          [[buffer(3)]],
    device   uint256*    yPtr          [[buffer(4)]],
    constant uint256&    incX          [[buffer(5)]],
    constant uint256&    incY          [[buffer(6)]],
    const device uint*   bloomBits     [[buffer(7)]],
    constant uint&       mask          [[buffer(8)]],
    device   atomic_uint* resultCount  [[buffer(9)]],
    device   HitResult*   results      [[buffer(10)]],
    //constant uint&       compression   [[buffer(11)]],
    uint                 gid           [[thread_position_in_grid]]
)
{
    if (gid >= gridSize) return;

    uint dim = gridSize;

    // --------------------------------------------------------------------
    // LOCAL POINTERS for strided traversal
    // --------------------------------------------------------------------
    device uint256* xPtrLocal = xPtr + gid;
    device uint256* yPtrLocal = yPtr + gid;

    // --------------------------------------------------------------------
    // Load this thread’s starting point ONCE
    // --------------------------------------------------------------------
    uint256 x = *xPtrLocal;
    uint256 y = *yPtrLocal;

    // --------------------------------------------------------------------
    // Initialize prefix inverse accumulator = 1
    // --------------------------------------------------------------------
    uint256 inverse;
    for (uint k = 0; k < 8; ++k)
        inverse.limbs[k] = 0u;
    inverse.limbs[0] = 1u;

    int batchIdx = 0;
    uint iForward;

    // --------------------------------------------------------------------
    // FORWARD PASS (MAIN LOOP) — NO repeated global loads of xPtr/yPtr
    // --------------------------------------------------------------------
    for (iForward = gid; iForward < totalPoints; iForward += dim)
    {
        // ---- 1) Compute y-parity ----
        uint yParity = (y.limbs[0] & 1u);

        // ---- 2) SHA256(pubkey compressed) ----
        uint shaState[8];
        sha256PublicKeyCompressed(x.limbs, yParity, shaState);

        // ---- 3) RIPEMD160 pre-final ----
        uint preFinal[5];
        ripemd160sha256NoFinal(shaState, preFinal);

        // ---- 4) Bloom filter check ----
        bool hit = bloom_contains(preFinal, bloomBits, mask);

        // ---- 5) On hit → compute final RIPEMD160 and store ----
        if (hit)
        {
            uint digestFinal[5];
            ripemd160FinalRound(preFinal, digestFinal);

            uint slot = atomic_fetch_add_explicit(resultCount, 1u, memory_order_relaxed);
            
            // BLOOM_MAX_HITS should usually never be exceeded, but if, then we would have a buffer overflow here
            // Clamp index so it never exceeds maxResults-1.
            slot = min(slot, BLOOM_MAX_HITS - 1);
            
          //  if (slot >= BLOOM_MAX_HITS) {
                // optionally decrement count here
          //      return;
          //  }
            
            HitResult r;
            r.index = iForward;
            for (uint k = 0; k < 5; ++k)
                r.digest[k] = digestFinal[k];

            results[slot] = r;
        }

        // ---- 6) Forward batch-add prefix computation ----
        // beginBatchAdd256k DOES NOT update x, y. It ONLY:
        //   - computes diff = incX - x
        //   - updates inverse = inverse * diff
        //   - writes chain entry
        beginBatchAdd256k(
            incX,
            x,
            chain,
            (int)iForward,
            batchIdx,
            &inverse,
            gid,
            dim
        );
        batchIdx++;

        // ---- 7) Advance to next element in the strided sequence ----
        xPtrLocal += dim;
        yPtrLocal += dim;

        if (iForward + dim < totalPoints) {
            // Load x,y ONLY once per stride jump
            x = *xPtrLocal;
            y = *yPtrLocal;
        }
    }

    // --------------------------------------------------------------------
    // INVERSION STEP — compute batch-wide inverse
    // --------------------------------------------------------------------
    doBatchInverse256k(inverse.limbs);

    // --------------------------------------------------------------------
    // BACKWARD PASS — correct each point using prefix products
    // --------------------------------------------------------------------
    int i = (int)iForward - (int)dim;
    for (; i >= 0; i -= (int)dim)
    {
        batchIdx--;

        uint256 newX, newY;

        completeBatchAdd256k(
            incX,
            incY,
            xPtr,
            yPtr,
            i,
            batchIdx,
            chain,
            &inverse,
            &newX,
            &newY,
            gid,
            dim
        );

        xPtr[i] = newX;
        yPtr[i] = newY;
    }
}







// --- assumes you already have: ---
// struct uint256 { uint limbs[8]; };
// struct Point   { uint256 x; uint256 y; bool infinity; };
// constant Point G_POINT;
// constant Point G_DOUBLES[8];
// constant Point G_TABLE256[256];
// uint256 field_add(uint256, uint256);
// Point   point_mul(uint256, constant Point*, constant Point*);

// Helper: build uint256 from a small 32-bit scalar (LS limb only)
inline uint256 u256_from_u32(uint v) {
    uint256 r;
    #pragma unroll
    for (int i = 0; i < 8; ++i) r.limbs[i] = 0u;
    r.limbs[0] = v;
    return r;
}

/**
 *  - For each thread i < totalPoints:
 *       k_i = startKey + i
 *       P_i = k_i · G
 *       xPtr[i] = P_i.x
 *       yPtr[i] = P_i.y
 *
 *  - Thread 0:
 *       deltaK   = totalPoints
 *       deltaG   = deltaK · G
 *       deltaG_out = deltaG
 */
kernel void init_points(
    constant uint      &totalPoints        [[ buffer(0) ]],
    device   const uint*start_key_limbs   [[ buffer(1) ]],  // 8 limbs (LE)
    device   uint256   *xPtr              [[ buffer(2) ]],
    device   uint256   *yPtr              [[ buffer(3) ]],
    device   uint256&    deltaG_x          [[buffer(4)]],
    device   uint256&    deltaG_y          [[buffer(5)]],
    uint                  tid             [[ thread_position_in_grid ]]
)
{
    if (tid >= totalPoints) {
        return;
    }

    // ---- Load startKey (uint256) from 8 limbs ----
    uint256 startKey;
    #pragma unroll
    for (int i = 0; i < 8; ++i) {
        startKey.limbs[i] = start_key_limbs[i];
    }

    // ---- Compute k_i = startKey + i ----
    uint256 k_i = startKey;
    uint256 offset = u256_from_u32(tid);   // we assume totalPoints fits in limb[0]
    k_i = field_add(k_i, offset);         // modular add in secp256k1 order domain

    // ---- P_i = k_i · G (affine) ----
    Point P_i = point_mul(k_i, G_TABLE256, G_DOUBLES);

    // ---- Store affine coordinates into xPtr / yPtr ----
    xPtr[tid] = P_i.x;
    yPtr[tid] = P_i.y;

    // ---- Thread 0: compute ΔG and last private key ----
    if (tid == 0) {
        // Δk = totalPoints
        uint256 deltaK = u256_from_u32(totalPoints);

        // ΔG = Δk · G
        Point deltaG = point_mul(deltaK, G_TABLE256, G_DOUBLES);
        deltaG_x = deltaG.x;
        deltaG_y = deltaG.y;

        // lastPriv = startKey + totalPoints
        // uint256 lastPriv = field_add(startKey, deltaK);
        // #pragma unroll
        // for (int i = 0; i < 8; ++i) {
        //    last_private_key[i] = lastPriv.limbs[i];
        // }
    }
}


kernel void bloom_insert(
    const device uchar *items      [[buffer(0)]],  // N * 20-byte hash160
    constant uint &item_count      [[buffer(1)]],
    device atomic_uint *bits       [[buffer(2)]],  // bloom bit array
    constant uint &mask            [[buffer(3)]],  // mask (2^n - 1)
    uint gid [[thread_position_in_grid]])
{
    if (gid >= item_count) return;

    // 20-byte hash160 for this item
    const device uchar *key = items + (gid * 20);

    // Local copy so we can pass as thread array
    uchar hashBytes[20];
    for (uint i = 0; i < 20; ++i)
        hashBytes[i] = key[i];

    // Pre-final RIPEMD160 state
    uint preFinal[5];
    undoRMD160FinalRoundFromBytes(hashBytes, preFinal);

    // Insert into bit array using index generation
    bloom_insert(preFinal, bits, mask);
}




 
// ================ Test Kernels ================
//#ifdef DEBUG

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


kernel void test_field_sub(
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
    
    uint256 result = field_sub(a, b);
    
    for (int i = 0; i < 8; i++) {
        output[id * 8 + i] = result.limbs[i];
    }
}





// =========================================================
// TEST KERNEL
// =========================================================
// Inputs:
//   buffer(0): compressed public key (33 bytes, uint8_t)
// Outputs:
//   buffer(1): sha256 state (8 × uint32)
//   buffer(2): ripemd160 intermediate (5 × uint32)
//   buffer(3): final hash160 (5 × uint32)
//
// Run with thread_count = 1
// =========================================================

kernel void test_hash_kernel(
    const device uint8_t*   pubkey33   [[buffer(0)]],
    device uint*            outSHA256  [[buffer(1)]],
    device uint*            outRMDtmp  [[buffer(2)]],
    device uint*            outHASH160 [[buffer(3)]],
    uint                    tid        [[thread_position_in_grid]]
)
{
    if (tid != 0) return;

    // ----------------------------------------
    // 1. Load compressed public key into limbs
    // ----------------------------------------
    // format:
    //   x = 32 bytes = 8×uint, big-endian per limb
    //   prefix = pubkey33[0] (0x02 or 0x03)
    //
    // pubkey33 layout:
    //   [0] prefix
    //   [1..32] X coordinate
    //
    // SHA256PublicKeyCompressed expects:
    //   uint x[8]  (big-endian 32-bit words)
    //   uint yParity = prefix & 1

    uint x[8];

    for (uint i = 0; i < 8; i++) {
        x[i] =
            (uint(pubkey33[1 + i*4 + 0]) << 24) |
            (uint(pubkey33[1 + i*4 + 1]) << 16) |
            (uint(pubkey33[1 + i*4 + 2]) << 8 ) |
            (uint(pubkey33[1 + i*4 + 3])      );
    }

    uint yParity = pubkey33[0] & 1;

    // ----------------------------------------
    // 2. Run SHA-256
    // ----------------------------------------
    uint shaState[8];
    sha256PublicKeyCompressed(x, yParity, shaState);

    for (uint i = 0; i < 8; i++)
        outSHA256[i] = shaState[i];

    // ----------------------------------------
    // 3. Run RIPEMD160 (p1+p2)
    // ----------------------------------------
    uint rmdTmp[5];
    ripemd160sha256NoFinal(shaState, rmdTmp);

    for (uint i = 0; i < 5; i++)
        outRMDtmp[i] = rmdTmp[i];

    // ----------------------------------------
    // 4. Run final mixing
    // ----------------------------------------
    uint hash160[5];
    ripemd160FinalRound(rmdTmp, hash160);

    for (uint i = 0; i < 5; i++)
        outHASH160[i] = hash160[i];
}
