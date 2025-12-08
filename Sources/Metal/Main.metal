#pragma clang fp contract(fast)
#include <metal_stdlib>
using namespace metal;

#include "Secp256k1.metal"
#include "Sha256.metal"
#include "Ripemd160.metal"
#include "BloomFilter.metal"

#pragma clang optimize on


constant const uint NUMBER_HASHES = 20;

/// Backward pass: compute new affine point (rx, ry) = Q + P using shared inversion.
///
/// Inputs:
///   px, py     = increment point (ΔG.x, ΔG.y)
///   xPtr, yPtr = global arrays of affine points
///   i          = point index
///   batchIdx   = index in backward iteration
///   chain      = global chain buffer
///   inverse    = running suffix inverse (updated each iteration)
///
/// Output:
///   newX, newY = updated affine coordinates
inline void completeBatchAdd256k(
    const uint256       px,
    const uint256       py,
    device uint256*     xPtr,
    device uint256*     yPtr,
    int                 i,
    int                 batchIdx,
    device uint256*     chain,
    thread uint256*     inverse,
    thread uint256*     newX,
    thread uint256*     newY,
    uint                gid,
    uint                dim
)
{
    uint256 s;

    if (batchIdx > 0) {
        // Load previous prefix product
        uint chainIndex = (batchIdx - 1) * dim + gid;
        uint256 c = chain[chainIndex];

        // slope numerator partially: s = inverse * c
        s = field_mul(*inverse, c);

        // advance inverse: inverse = inverse * (px - x[i])
        uint256 diff = field_sub(px, xPtr[i]);
        *inverse = field_mul(*inverse, diff);
    }
    else {
        // Last one in backward pass
        s = *inverse;
    }

    // rise = py - yPtr[i]
    uint256 rise = field_sub(py, yPtr[i]);

    // full slope: s = rise * s
    s = field_mul(rise, s);

    // s^2
    uint256 s2 = field_sqr(s);

    // rx = s^2 - px - x[i]
    uint256 rx = field_sub(s2, px);
    rx = field_sub(rx, xPtr[i]);

    // ry = s*(px - rx) - py
    uint256 px_minus_rx = field_sub(px, rx);
    uint256 ry = field_mul(s, px_minus_rx);
    ry = field_sub(ry, py);

    *newX = rx;
    *newY = ry;
}

inline void doBatchInverse256k(thread uint* limbs8)
{
    // Load uint256
    uint256 t;
    #pragma unroll
    for (int i = 0; i < 8; i++) t.limbs[i] = limbs8[i];

    // Compute inverse mod p
    t = field_inv(t);

    // Store back
    #pragma unroll
    for (int i = 0; i < 8; i++) limbs8[i] = t.limbs[i];
}



/// Forward pass for batch addition
/// - px        = increment point X (ΔG.x)
/// - qx        = current point's X coordinate (xPtr[i])
/// - chain     = global chain buffer (size >= totalPoints)
/// - idx       = global point index i
/// - batchIdx  = index of this step inside the batch pass
/// - inverse   = running accumulator of prefix products
///
/// The actual chain index is assumed to be:
///    chainIdx = batchIdx * dim + gid
/// So idx is not used directly for indexing chain.
inline void beginBatchAdd256k(
    const uint256       px,
    const uint256       qx,
    device uint256*     chain,
    int                 idx,        // kept for compatibility, not used here
    int                 batchIdx,
    thread uint256*     inverse,
    uint                gid,
    uint                dim
)
{
    // diff = px - qx
    uint256 diff = field_sub(px, qx);

    // prefix product: inverse = inverse * diff (mod p)
    *inverse = field_mul(*inverse, diff);

    // chain[p] = inverse
    uint chainIndex = batchIdx * dim + gid;
    chain[chainIndex] = *inverse;
}


// Convert little-endian uint256 to 32 big-endian bytes
inline void u256_to_be32(const uint256 x, thread uchar out[32]) {
    // limbs[0] = least significant word
    #pragma unroll
    for (int limb = 0; limb < 8; ++limb) {
        uint w = x.limbs[limb];
        int byteBase = 28 - limb * 4; // big-endian order

        out[byteBase + 0] = (uchar)((w >> 24) & 0xFFu);
        out[byteBase + 1] = (uchar)((w >> 16) & 0xFFu);
        out[byteBase + 2] = (uchar)((w >>  8) & 0xFFu);
        out[byteBase + 3] = (uchar)( w        & 0xFFu);
    }
}



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
    constant uint&    totalPoints   [[buffer(0)]],
    constant uint&    gridSize      [[buffer(1)]],
    device   uint256* chain         [[buffer(2)]],
    device   uint256* xPtr          [[buffer(3)]],
    device   uint256* yPtr          [[buffer(4)]],
    constant uint256& incX          [[buffer(5)]],
    constant uint256& incY          [[buffer(6)]],
    const device uint*    bloomBits     [[buffer(7)]],
    constant uint&        m_bits        [[buffer(8)]],
    device   uint*        bloomResults  [[buffer(9)]],
    device   uint*        outRipemd160  [[buffer(10)]],
    constant uint&        compression   [[buffer(11)]],
    uint                  gid           [[thread_position_in_grid ]]
)
{
    if (gid >= gridSize) return;

    // ---- init inverse = 1 ----
    uint256 inverse;
    for (int k = 0; k < 8; ++k) inverse.limbs[k] = 0u;
    inverse.limbs[0] = 1u;

    int batchIdx = 0;
    uint dim = gridSize;

    // ---- forward pass: hash + bloom + batch-add ----
    uint iForward;
    for (iForward = gid; iForward < totalPoints; iForward += dim)
    {
        // ----- 1) Hash this point's public key -----
       // bool useCompressed = (compression != 0u);
       // uchar pk[65];
       // uint  pkLen = useCompressed ? 33u : 65u;

        // ----- 1) SHA256 hash this point's public key -----
        uint256 x = xPtr[iForward];
        uint256 y = yPtr[iForward];
        uint yParity = (y.limbs[0] & 1u);
        uint shaState[8];
        sha256PublicKeyCompressed(x.limbs, yParity, shaState);

        // ----- 2) RIPEMD160 -----
        uint ripemdTmp[5];
        uint ripemdOut[5];
        ripemd160sha256NoFinal(shaState, ripemdTmp);
        ripemd160FinalRound(ripemdTmp, ripemdOut);

        //
        // Store RIPEMD-160
        //
        uint base = iForward * 5u;
        outRipemd160[base + 0u] = ripemdOut[0];
        outRipemd160[base + 1u] = ripemdOut[1];
        outRipemd160[base + 2u] = ripemdOut[2];
        outRipemd160[base + 3u] = ripemdOut[3];
        outRipemd160[base + 4u] = ripemdOut[4];

        
        // TODO: REMOVE THIS
        uint packedOut[5];

        for (uint i = 0; i < 5; i++)
        {
            uint w = ripemdOut[i];
            // convert from BIG-endian to LITTLE-endian
            uint b0 = (w >> 24) & 0xFF;
            uint b1 = (w >> 16) & 0xFF;
            uint b2 = (w >> 8 ) & 0xFF;
            uint b3 = (w      ) & 0xFF;

            // pack into little-endian word for bloom_insert compatibility
            packedOut[i] = (b3 << 24) | (b2 << 16) | (b1 << 8) | b0;
        }
        // END REMOVE THIS
        
        
        
        // ----- 2) Bloom query -----
        uint h1, h2;
        hash_pair_fnv_words(packedOut, 5u, h1, h2);
        //hash_pair_fnv_words(ripemdOut, 5u, h1, h2);

        uint hit = 1u;
        for (uint j = 0; j < NUMBER_HASHES; ++j) {
            ulong combined = (ulong)h1 + (ulong)j * (ulong)h2;
            uint bit_idx = (uint)(combined % (ulong)m_bits);

            uint word_idx = bit_idx >> 5;
            uint bit_mask = 1u << (bit_idx & 31u);

            if ((bloomBits[word_idx] & bit_mask) == 0u) {
                hit = 0u;
                break;
            }
        }
        bloomResults[iForward] = hit;

        // ----- 3) Batch-add prefix product -----
        beginBatchAdd256k(
            incX,
            xPtr[iForward],
            chain,
            (int)iForward,
            batchIdx,
            &inverse,
            gid,
            dim
        );

        batchIdx++;
    }

    // ---- single inversion ----
    doBatchInverse256k(inverse.limbs);

    // ---- backward pass: apply batch-add ----
    int i = (int)iForward - (int)dim;

    uint256 newX;
    uint256 newY;

    for (; i >= 0; i -= (int)dim)
    {
        batchIdx--;

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
 *       (optional) lastPriv = startKey + totalPoints
 */
kernel void init_points(
    constant uint      &totalPoints        [[ buffer(0) ]],
    device   const uint*start_key_limbs   [[ buffer(1) ]],  // 8 limbs (LE)
    device   uint256   *xPtr              [[ buffer(2) ]],
    device   uint256   *yPtr              [[ buffer(3) ]],
    device   Point     &deltaG_out        [[ buffer(4) ]],
    device   uint      *last_private_key  [[ buffer(5) ]],  // optional: 8 limbs out
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
        deltaG_out = deltaG;

        // lastPriv = startKey + totalPoints
        uint256 lastPriv = field_add(startKey, deltaK);
        #pragma unroll
        for (int i = 0; i < 8; ++i) {
            last_private_key[i] = lastPriv.limbs[i];
        }
    }
}







// INSERT KERNEL
kernel void bloom_insert(
    const device uchar *items      [[buffer(0)]],
    constant uint &item_count      [[buffer(1)]],
    device atomic_uint *bits       [[buffer(2)]],
    constant uint &m_bits          [[buffer(3)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= item_count) return;
    
    const device uchar *key = items + (gid * 20); // RIPEMD160 hash is 20 bytes long
    
    uint h1, h2;
    hash_pair_fnv(key, 5, h1, h2); // RIPEMD160 hash is 5 UInt32 long
    
    for (uint i = 0; i < NUMBER_HASHES; i++) {
        // Matching Swift: (h1 + i * h2) % m_bits
        ulong combined = (ulong)h1 + (ulong)i * (ulong)h2;
        uint bit_idx = (uint)(combined % (ulong)m_bits);
        
        uint word_idx = bit_idx >> 5;
        uint bit_mask = 1u << (bit_idx & 31u);
        atomic_fetch_or_explicit(&bits[word_idx], bit_mask, memory_order_relaxed);
    }
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
