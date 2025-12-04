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



// ============================================================
//  KERNEL 2: process_batch_incremental
// ============================================================
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
    /*
    // ---- Thread 0 updates base private key in place (scalar += batchSize*keys_per_thread) ----
    if (thread_id == 0) {
        uint256 k; for (int i = 0; i < 8; i++) k.limbs[i] = base_private_key[i];

        uint256 delta; for (int i = 0; i < 8; i++) delta.limbs[i] = 0;
        delta.limbs[0] = batchSize * keys_per_thread;

        uint carry = 0;
        uint256 result;
        for (int i = 0; i < 8; i++) {
            ulong sum = (ulong)k.limbs[i] + (ulong)delta.limbs[i] + (ulong)carry;
            result.limbs[i] = (uint)sum;
            carry = (uint)(sum >> 32);
        }
        for (int i = 0; i < 8; i++) base_private_key[i] = result.limbs[i];
    }
     */
}





// Fused: SHA-256 -> RIPEMD-160 -> Bloom query
//
// Inputs:
//   buffer(0): messages          (uchar*)   numMessages * messageSize bytes
//   buffer(1): bits              (uint*)    bloom filter bit array
//   buffer(2): SHA256Constants   { numMessages, messageSize }
//   buffer(3): m_bits            (uint)     bloom bit count
//
// Outputs:
//   buffer(4): bloomResults      (uint*)    0 or 1 per message
//   buffer(5): outRipemd160      (uint*)    5 uints per message
//
kernel void sha256_ripemd160_bloom_query_kernel(
    const device uchar*         messages       [[ buffer(0) ]],
    const device uint*          bits           [[ buffer(1) ]],
    constant SHA256Constants&   c              [[ buffer(2) ]],
    constant uint&              m_bits         [[ buffer(3) ]],
    device uint*                bloomResults   [[ buffer(4) ]],
    device uint*                outRipemd160   [[ buffer(5) ]],
    uint                        gid            [[ thread_position_in_grid ]]
)
{
    if (gid >= c.numMessages) return;

    uint offset = gid * c.messageSize;

    // ---- SHA-256(message) ----
    uint shaState[8];
    sha256(messages, offset, c.messageSize, shaState);

    // ---- RIPEMD-160(SHA-256(message)) ----
    uint ripemdOut[5];
    ripemd160(shaState, ripemdOut);
    // ripemdOut now contains the 20-byte hash as 5×uint32

    // ---- Store RIPEMD-160 to output buffer ----
    {
        uint base = gid * 5u;
        outRipemd160[base + 0u] = ripemdOut[0];
        outRipemd160[base + 1u] = ripemdOut[1];
        outRipemd160[base + 2u] = ripemdOut[2];
        outRipemd160[base + 3u] = ripemdOut[3];
        outRipemd160[base + 4u] = ripemdOut[4];
    }

    // ---- Bloom query on ripemdOut ----
    uint h1, h2;
    hash_pair_fnv_words(ripemdOut, 5u, h1, h2);  // 5x uint32 = 20 bytes

    for (uint i = 0; i < NUMBER_HASHES; i++) {
        ulong combined = (ulong)h1 + (ulong)i * (ulong)h2;
        uint bit_idx = (uint)(combined % (ulong)m_bits);

        uint word_idx = bit_idx >> 5;
        uint bit_mask = 1u << (bit_idx & 31u);

        if ((bits[word_idx] & bit_mask) == 0u) {
            bloomResults[gid] = 0u;
            return;
        }
    }

    // If all bloom bits were set → mark as probable hit
    bloomResults[gid] = 1u;
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
//#endif

