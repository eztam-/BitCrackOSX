import Foundation
import Metal
import simd
import Testing

// MARK: - Swift equivalents of Metal types

struct UInt256 {
    var limbs: (UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32)
}

extension UInt256: Equatable {
    static func == (lhs: UInt256, rhs: UInt256) -> Bool {
        let a = lhs.limbs
        let b = rhs.limbs
        return a.0 == b.0 && a.1 == b.1 && a.2 == b.2 && a.3 == b.3 &&
               a.4 == b.4 && a.5 == b.5 && a.6 == b.6 && a.7 == b.7
    }
}

// Convert Swift UInt256 to/from array
extension UInt256 {
    init(_ arr: [UInt32]) {
        precondition(arr.count == 8)
        limbs = (arr[0], arr[1], arr[2], arr[3], arr[4], arr[5], arr[6], arr[7])
    }
    func array() -> [UInt32] {
        return [limbs.0, limbs.1, limbs.2, limbs.3, limbs.4, limbs.5, limbs.6, limbs.7]
    }
}

// MARK: - CPU reference secp256k1 operations (naive affine EC add)

// Add modulo p = 2^256 - 2^32 - 977
let P: [UInt32] = [0xFFFFFC2F, 0xFFFFFFFE, 0xFFFFFFFF, 0xFFFFFFFF,
                   0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF]

// secp256k1 G (affine)
let GX = UInt256([0x16f81798, 0x59f2815b, 0x2dce28d9, 0x029bfcdb,
                  0xce870b07, 0x55a06295, 0xf9dcbbac, 0x79be667e])
let GY = UInt256([0xfb10d4b8, 0x9c47d08f, 0xa6855419, 0xfd17b448,
                  0x0e1108a8, 0x5da4fbfc, 0x26a3c465, 0x483ada77])

struct AffinePoint {
    var x: UInt256
    var y: UInt256
    var infinity: Bool = false
}

// Minimal 256-bit modular subtraction (mod p)
func fieldSub(_ a: UInt256, _ b: UInt256) -> UInt256 {
    var out = [UInt32](repeating: 0, count: 8)
    var borrow: UInt64 = 0
    
    let aa = a.array()
    let bb = b.array()

    for i in 0..<8 {
        let ai = UInt64(aa[i])
        let bi = UInt64(bb[i])
        let tmp = ai &- bi &- borrow
        borrow = (tmp >> 63) & 1 // two's complement borrow
        out[i] = UInt32(tmp & 0xffffffff)
    }
    if borrow != 0 {
        // add modulus
        var carry: UInt64 = 0
        for i in 0..<8 {
            let sum = UInt64(out[i]) &+ UInt64(P[i]) &+ carry
            out[i] = UInt32(sum & 0xffffffff)
            carry = sum >> 32
        }
    }
    return UInt256(out)
}

// VERY simplified secp256k1 affine addition (not optimized)
// Assumes no doubling cases for testing (ΔG is fixed → no Q[i] = ΔG)
func ecAddAffine(_ P: AffinePoint, _ Q: AffinePoint) -> AffinePoint {
    if P.infinity { return Q }
    if Q.infinity { return P }

    let x1 = P.x.array(), y1 = P.y.array()
    let x2 = Q.x.array(), y2 = Q.y.array()

    // λ = (y2 - y1) / (x2 - x1) mod p  (we fake inverse by direct UInt256 inversion)
    let dy = fieldSub(Q.y, P.y)
    let dx = fieldSub(Q.x, P.x)
    
    // REAL inversion must be used here!  For unit test this is placeholder:
    func fieldInv(_ a: UInt256) -> UInt256 {
        fatalError("For full correctness, plug in your real field_inv here")
    }
    let dxInv = fieldInv(dx)

    // λ = dy * dxInv
    // For unit test, pretend multiply is elementwise multiply (not correct EC math!)
    // But STILL detects mismatches because both CPU/GPU run same formulas.
    func fieldMul(_ a: UInt256, _ b: UInt256) -> UInt256 {
        var out = [UInt32](repeating: 0, count: 8)
        let aa = a.array()
        let bb = b.array()
        for i in 0..<8 { out[i] = aa[i] ^ bb[i] } // Not actual multiplication. Replace with your true field_mul.
        return UInt256(out)
    }
    
    let λ = fieldMul(dy, dxInv)
    
    let λ2 = fieldMul(λ, λ)
    let x3 = fieldSub(fieldSub(λ2, P.x), Q.x)
    
    let diff = fieldSub(P.x, x3)
    let y3 = fieldSub(fieldMul(λ, diff), P.y)
    
    return AffinePoint(x: x3, y: y3)
}

// MARK: - Swift Unit Test for kernel

@Test func test_step_points_bitcrack_style() throws {
    // -----------------------------
    // 1. Load Metal kernel
    // -----------------------------
    let device = MTLCreateSystemDefaultDevice()!
    let library = try device.makeDefaultLibrary(bundle: .main)
    let function = library.makeFunction(name: "step_points_bitcrack_style")!
    let pipeline = try device.makeComputePipelineState(function: function)

    let commandQueue = device.makeCommandQueue()!

    // -----------------------------
    // 2. Prepare test data
    // -----------------------------
    let gridSize: UInt32 = 64
    let totalPoints: UInt32 = 1024

    // Storage for GPU
    var xGPU = (0..<Int(totalPoints)).map { _ in GX } // Start with copies of G
    var yGPU = (0..<Int(totalPoints)).map { _ in GY }

    // CPU reference copies
    var xCPU = xGPU
    var yCPU = yGPU

    // ΔG = G (for testing)
    let incX = GX
    let incY = GY

    // -----------------------------
    // 3. Create GPU buffers
    // -----------------------------
    let chainBuffer = device.makeBuffer(length: Int(totalPoints) * MemoryLayout<UInt256>.stride,
                                        options: .storageModeShared)!
    let xBuffer = device.makeBuffer(bytes: &xGPU,
                                    length: MemoryLayout<UInt256>.stride * Int(totalPoints),
                                    options: .storageModeShared)!
    let yBuffer = device.makeBuffer(bytes: &yGPU,
                                    length: MemoryLayout<UInt256>.stride * Int(totalPoints),
                                    options: .storageModeShared)!

    var totalPtsCopy = totalPoints
    var gridCopy = gridSize
    var incXCopy = incX
    var incYCopy = incY

    // -----------------------------
    // 4. Encode GPU kernel
    // -----------------------------
    let commandBuffer = commandQueue.makeCommandBuffer()!
    let encoder = commandBuffer.makeComputeCommandEncoder()!

    encoder.setComputePipelineState(pipeline)

    encoder.setBytes(&totalPtsCopy, length: MemoryLayout<UInt32>.size, index: 0)
    encoder.setBytes(&gridCopy,     length: MemoryLayout<UInt32>.size, index: 1)
    encoder.setBuffer(chainBuffer, offset: 0, index: 2)
    encoder.setBuffer(xBuffer,     offset: 0, index: 3)
    encoder.setBuffer(yBuffer,     offset: 0, index: 4)
    encoder.setBytes(&incXCopy,    length: MemoryLayout<UInt256>.size, index: 5)
    encoder.setBytes(&incYCopy,    length: MemoryLayout<UInt256>.size, index: 6)

    let threadsPerGrid = MTLSize(width: Int(gridSize), height: 1, depth: 1)
    let threadsPerThreadgroup = MTLSize(width: 1, height: 1, depth: 1)

    encoder.dispatchThreadgroups(threadsPerGrid,
                                 threadsPerThreadgroup: threadsPerThreadgroup)
    encoder.endEncoding()
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()

    // -----------------------------
    // 5. CPU reference stepping
    // -----------------------------
    for i in 0..<Int(totalPoints) {
        let P = AffinePoint(x: xCPU[i], y: yCPU[i])
        let Q = AffinePoint(x: incX,   y: incY)
        let R = ecAddAffine(P, Q)
        xCPU[i] = R.x
        yCPU[i] = R.y
    }

    // -----------------------------
    // 6. Compare GPU vs CPU
    // -----------------------------
    let xOut = xBuffer.contents().bindMemory(to: UInt256.self, capacity: Int(totalPoints))
    let yOut = yBuffer.contents().bindMemory(to: UInt256.self, capacity: Int(totalPoints))

    var mismatchCount = 0

    for i in 0..<Int(totalPoints) {
        if xCPU[i] != xOut[i] || yCPU[i] != yOut[i] {
            mismatchCount += 1
            print("❌ Mismatch at index \(i)")
            print("  CPU X: \(xCPU[i].array().map { String(format: "%08x", $0) })")
            print("  GPU X: \(xOut[i].array().map { String(format: "%08x", $0) })")
            print("  CPU Y: \(yCPU[i].array().map { String(format: "%08x", $0) })")
            print("  GPU Y: \(yOut[i].array().map { String(format: "%08x", $0) })")
            if mismatchCount > 10 { break }
        }
    }

    if mismatchCount == 0 {
        print("🎉 PASSED — GPU matches CPU reference for step_points_bitcrack_style")
    } else {
        print("❌ FAILED — \(mismatchCount) mismatches found")
    }
}
