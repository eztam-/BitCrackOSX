#include <metal_stdlib>
using namespace metal;

#include "secp256k1.metal"
#include "SHA256.metal"
#include "RIPEMD160.metal"
#include "BloomFilter.metal"


constant const uint NUMBER_HASHES = 20;


/**
 Compute the initial base public keys (one per thread) using scalar multiplication.
 Compute the global ΔG = (batchSize × keys_per_thread) × G.
 Store:
 Each thread’s base public key (affine)
 The ΔG point (shared for the entire batch)
 The last private key value used (so the next batch can resume)
 */
/*
kernel void init_base_points(
    constant uint& batchSize             [[buffer(0)]],
    constant uint& keys_per_thread       [[buffer(1)]],
    device uint* base_private_key_out    [[buffer(2)]],
    device Point* base_public_points_out [[buffer(3)]],
    device Point& deltaG_out             [[buffer(4)]],      // will hold ΔG_next (fixed)
    device const uint* start_key_limbs   [[buffer(5)]],
    uint thread_id                       [[thread_position_in_grid]]
)
{
    if (thread_id >= batchSize) return;

    // Load starting scalar
    uint256 startKey;
    for (int i = 0; i < 8; i++) startKey.limbs[i] = start_key_limbs[i];

    // k0 = startKey + thread_id * keys_per_thread
    uint256 offset; for (int i = 0; i < 8; i++) offset.limbs[i] = 0;
    offset.limbs[0] = thread_id * keys_per_thread;
    uint256 k0 = field_add(startKey, offset);

    // P0 = k0 * G
    Point P0 = point_mul(k0, G_TABLE256, G_DOUBLES);
    base_public_points_out[thread_id] = P0;

    // Thread 0: compute ΔG_next and the scalar "last" = startKey + Δk
    if (thread_id == 0) {
        // Δk = batchSize * keys_per_thread
        uint256 deltaK; for (int i = 0; i < 8; i++) deltaK.limbs[i] = 0;
        deltaK.limbs[0] = batchSize * keys_per_thread;

        // Compute ΔG = Δk · G
        Point deltaG_batch = point_mul(deltaK, G_TABLE256, G_DOUBLES);

        // Compute (keys_per_thread − 1) · G  (call it step_m1)
        uint256 kpt_m1; for (int i = 0; i < 8; i++) kpt_m1.limbs[i] = 0;
        kpt_m1.limbs[0] = (keys_per_thread > 0) ? (keys_per_thread - 1) : 0;
        Point step_m1 = point_mul(kpt_m1, G_TABLE256, G_DOUBLES);

        // ΔG_next = ΔG_batch - step_m1  (affine subtraction via add with negated Y)
        // acc = deltaG_batch + (-step_m1)
        PointJacobian acc; acc.infinity = true;
        acc = point_add_mixed_jacobian(acc, deltaG_batch);

        // negate Y: y -> p - y
        uint256 P256; for (int i = 0; i < 8; i++) P256.limbs[i] = P[i];
        Point step_m1_neg = step_m1;
        step_m1_neg.y = field_sub(P256, step_m1.y);

        acc = point_add_mixed_jacobian(acc, step_m1_neg);
        Point deltaG_next = jacobian_to_affine(acc);

        // Store ΔG_next for the process kernel
        deltaG_out = deltaG_next;

        // base_private_key_out = startKey + Δk   (scalar for the host; LE limbs)
        uint256 last = field_add(startKey, deltaK);
        for (int i = 0; i < 8; i++) base_private_key_out[i] = last.limbs[i];
    }
}

*/


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

inline void make_compressed_pubkey(
    const uint256 x,
    const uint256 y,
    thread uchar out[33]
) {
    // prefix: 0x02 if y is even, 0x03 if odd
    uint y0 = y.limbs[0];   // least significant limb
    bool isOdd = (y0 & 1u) != 0u;
    out[0] = isOdd ? (uchar)0x03u : (uchar)0x02u;

    u256_to_be32(x, out + 1);
}

inline void make_uncompressed_pubkey(
    const uint256 x,
    const uint256 y,
    thread uchar out[65]
) {
    out[0] = (uchar)0x04u;
    u256_to_be32(x, out + 1);
    u256_to_be32(y, out + 33);
}


//Adds ΔG to all points each iteration.
//
//  BitCrack-style EC step kernel for Metal
//
//  Performs batch EC addition for ALL points in (xPtr, yPtr) using:
//      Q[i] = Q[i] + ΔG
//  where ΔG = (incX, incY)
//
//  This is directly equivalent to BitCrack’s _stepKernel (minus hashing).
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
kernel void step_points_bitcrack_style(
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
        bool useCompressed = (compression != 0u);
        uchar pk[65];
        uint  pkLen = useCompressed ? 33u : 65u;

        uint256 x = xPtr[iForward];
        uint256 y = yPtr[iForward];

        if (useCompressed) {
            make_compressed_pubkey(x, y, pk);
        } else {
            make_uncompressed_pubkey(x, y, pk);
        }

        uint shaState[8];
        sha256_bytes(pk, pkLen, shaState);

        uint ripemdOut[5];
        ripemd160(shaState, ripemdOut);

        // Store RIPEMD-160
        {
            uint base = iForward * 5u;
            outRipemd160[base + 0u] = ripemdOut[0];
            outRipemd160[base + 1u] = ripemdOut[1];
            outRipemd160[base + 2u] = ripemdOut[2];
            outRipemd160[base + 3u] = ripemdOut[3];
            outRipemd160[base + 4u] = ripemdOut[4];
        }

        // ----- 2) Bloom query -----
        uint h1, h2;
        hash_pair_fnv_words(ripemdOut, 5u, h1, h2);

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
 * BitCrack-style init:
 *
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
kernel void init_points_bitcrack_style(
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




// ============================================================
//  KERNEL 2: process_batch_incremental
// ============================================================
/*
kernel void process_batch_incremental(
    device Point* base_points                [[buffer(0)]],
    device const Point& deltaG               [[buffer(1)]],   // now carries ΔG_next from init
    device uchar* public_keys                [[buffer(2)]],
    constant const uint& batchSize           [[buffer(3)]],
    constant const uint& keys_per_thread     [[buffer(4)]],
    constant const bool& compressed          [[buffer(5)]],
    //device uint* base_private_key            [[buffer(6)]],
    uint thread_id                           [[thread_position_in_grid]]
)
{
    if (thread_id >= batchSize) return;

    constant Point& G = G_POINT;
    int pubKeyLength = compressed ? 33 : 65;

    // Load current base point
    PointJacobian J;
    J.X = base_points[thread_id].x;
    J.Y = base_points[thread_id].y;
    for (int i = 0; i < 8; i++) J.Z.limbs[i] = 0;
    J.Z.limbs[0] = 1;
    J.infinity = false;

    // Scratch buffers
    thread PointJacobian bufJ[MAX_KEYS_PER_THREAD];
    thread uint256 Zs[MAX_KEYS_PER_THREAD];
    thread uint256 invZ[MAX_KEYS_PER_THREAD];
    thread Point bufA[MAX_KEYS_PER_THREAD];

    uint produced = 0;
    while (produced < keys_per_thread) {
        int n = min((uint)MAX_KEYS_PER_THREAD, keys_per_thread - produced);
        bufJ[0] = J;
        Zs[0] = J.Z;

        for (int i = 1; i < n; i++) {
            J = point_add_mixed_jacobian(J, G);
            bufJ[i] = J;
            Zs[i] = J.Z;
        }

        batch_inverse(Zs, invZ, n);
        affine_from_jacobian_batch(bufJ, invZ, bufA, n);

        // --- Coalesced write version ---
        // Layout: keys[i][thread] instead of threads[thread][i]
        // Each iteration i now writes contiguous public keys across threads
        uint produced_base = produced * batchSize;

        for (int i = 0; i < n; ++i) {
            uint out_idx = produced_base + thread_id;  // coalesced across threads

            if (compressed)
                store_public_key_compressed(public_keys, out_idx, bufA[i].x, bufA[i].y);
            else
                store_public_key_uncompressed(public_keys, out_idx, bufA[i].x, bufA[i].y);

            produced_base += batchSize;  // move to next "row"
        }


        produced += n;
    }

    // J is the LAST element of this thread for the batch (= start + (KPT-1)·G).
    // Using ΔG_next here makes: J + ΔG_next = start + ΔG_batch. Correct next base.
    PointJacobian J_next = point_add_mixed_jacobian(J, deltaG);
    base_points[thread_id] = jacobian_to_affine(J_next);

    // Doing this now on host side

}
*/





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

// =======================================
// Test kernel: hash a single message
// buffer(0): device uchar* input
// buffer(1): constant uint& inputLength
// buffer(2): device uint* output (8 words)
// =======================================
kernel void sha256_test_kernel(
    device const uchar*   input      [[buffer(0)]],
    constant uint&        inputLen   [[buffer(1)]],
    device uint*          outState   [[buffer(2)]],
    uint                  tid        [[thread_position_in_grid]]
)
{
    // Only one thread does the work
    if (tid != 0) return;

    // Copy message from device memory into a thread-local array
    // NOTE: for testing we assume a reasonably small message.
    // For "abc" this is obviously fine.
    thread uchar localMsg[128];
    uint len = inputLen;
    if (len > 128u) {
        len = 128u; // clamp to avoid overflow in test
    }

    for (uint i = 0; i < len; ++i) {
        localMsg[i] = input[i];
    }

    uint state[8];
    // Call your existing SHA-256 implementation (unchanged)
    sha256_bytes(localMsg, len, state);

    // Write result to output buffer
    for (uint i = 0; i < 8u; ++i) {
        outState[i] = state[i];
    }
}




//#endif

