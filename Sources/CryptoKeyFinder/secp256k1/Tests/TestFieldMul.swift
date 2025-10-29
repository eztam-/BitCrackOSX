// ==================== SWIFT TEST CODE ====================
// Save this as: TestFieldMul.swift

import Metal
import Foundation

// Helper for string repetition
extension String {
    static func * (left: String, right: Int) -> String {
        return String(repeating: left, count: right)
    }
}

class FieldMulTester {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLComputePipelineState
    
    
    
    
    init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            print("❌ Failed to initialize Metal device")
            return nil
        }
        
        self.device = device
        self.commandQueue = commandQueue
        
        let library: MTLLibrary! = try? device.makeDefaultLibrary(bundle: Bundle.module)
        guard let function = library.makeFunction(name: "test_field_mul") else {
            fatalError("Failed to load function private_to_public_keys from library")
        }
        do {
            self.pipelineState = try device.makeComputePipelineState(function: function)
        } catch {
            fatalError("Failed to create pipeline state: \(error)")
            ///
            
        }
    }
       public func runTests() {
            
            
            
            print("🧪 Testing secp256k1 Field Multiplication")
            print("=" * 60)
            
            // Test cases: (a, b, expected_result)
            let testCases: [(String, String, String)] = [
                // Test 1: 1 * 1 = 1
                (
                    "0000000000000000000000000000000000000000000000000000000000000001",
                    "0000000000000000000000000000000000000000000000000000000000000001",
                    "0000000000000000000000000000000000000000000000000000000000000001"
                ),
                // Test 2: 2 * 3 = 6
                (
                    "0000000000000000000000000000000000000000000000000000000000000002",
                    "0000000000000000000000000000000000000000000000000000000000000003",
                    "0000000000000000000000000000000000000000000000000000000000000006"
                ),
                // Test 3: 2^32 * 2 = 2^33
                (
                    "0000000000000000000000000000000000000000000000000000000100000000",
                    "0000000000000000000000000000000000000000000000000000000000000002",
                    "0000000000000000000000000000000000000000000000000000000200000000"
                ),
                // Test 4: Large number * 2
                (
                    "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF",
                    "0000000000000000000000000000000000000000000000000000000000000002",
                    "00000000000000000000000000000000000000000000000000000002000007A0"  // Computed via Python
                ),
                // Test 5: (P-1) * 2 should = P-2 (mod P)
                (
                    "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2E",
                    "0000000000000000000000000000000000000000000000000000000000000002",
                    "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2D"
                ),
                // Two large numbers
                (
                    "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEB1AED123AF48A03BBFD25E8CD0364140",
                    "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE1AAEDCE6AF48A03BBFD25E8CD0364040",
                    "79C9C34D615F7CBED1C176B50B68C7A02C8998767E8FE1A5BB5E3EA89F8921C3"
                )
            ]
            
            for (index, testCase) in testCases.enumerated() {
                print("\n📋 Test Case \(index + 1):")
                let (aHex, bHex, expectedHex) = testCase
                
                let aLimbs = hexToLimbs(aHex)
                let bLimbs = hexToLimbs(bHex)
                let expectedLimbs = hexToLimbs(expectedHex)
                
                guard let result = multiply(aLimbs, bLimbs) else {
                    print("❌ Test failed - Metal execution error")
                    continue
                }
                
                let passed = result == expectedLimbs
                
                print("  Input A:  \(aHex)")
                print("  Input B:  \(bHex)")
                print("  Expected: \(expectedHex)")
                print("  Got:      \(limbsToHex(result))")
                print("  Status:   \(passed ? "✅ PASS" : "❌ FAIL")")
                
                if !passed {
                    print("  Debug - Expected limbs: \(expectedLimbs.map { String(format: "0x%08X", $0) })")
                    print("  Debug - Got limbs:      \(result.map { String(format: "0x%08X", $0) })")
                }
            }
            
            print("\n" + "=" * 60)
        }
        
        func multiply(_ a: [UInt32], _ b: [UInt32]) -> [UInt32]? {
            let bufferSize = 8 * MemoryLayout<UInt32>.size
            
            guard let bufferA = device.makeBuffer(length: bufferSize, options: .storageModeShared),
                  let bufferB = device.makeBuffer(length: bufferSize, options: .storageModeShared),
                  let bufferOut = device.makeBuffer(length: bufferSize, options: .storageModeShared) else {
                print("❌ Failed to create Metal buffers")
                return nil
            }
            
            // Copy inputs
            let ptrA = bufferA.contents().bindMemory(to: UInt32.self, capacity: 8)
            let ptrB = bufferB.contents().bindMemory(to: UInt32.self, capacity: 8)
            for i in 0..<8 {
                ptrA[i] = a[i]
                ptrB[i] = b[i]
            }
            
            // Execute
            guard let commandBuffer = commandQueue.makeCommandBuffer(),
                  let encoder = commandBuffer.makeComputeCommandEncoder() else {
                print("❌ Failed to create command encoder")
                return nil
            }
            
            encoder.setComputePipelineState(pipelineState)
            encoder.setBuffer(bufferA, offset: 0, index: 0)
            encoder.setBuffer(bufferB, offset: 0, index: 1)
            encoder.setBuffer(bufferOut, offset: 0, index: 2)
            
            let threadGroupSize = MTLSize(width: 1, height: 1, depth: 1)
            let threadGroups = MTLSize(width: 1, height: 1, depth: 1)
            encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
            encoder.endEncoding()
            
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            
            if let error = commandBuffer.error {
                print("❌ Metal command error: \(error)")
                return nil
            }
            
            // Read result
            let ptrOut = bufferOut.contents().bindMemory(to: UInt32.self, capacity: 8)
            var result = [UInt32](repeating: 0, count: 8)
            for i in 0..<8 {
                result[i] = ptrOut[i]
            }
            
            return result
        }
        
        // Convert hex string to little-endian limbs
         func hexToLimbs(_ hex: String) -> [UInt32] {
            var result = [UInt32](repeating: 0, count: 8)
            let clean = hex.replacingOccurrences(of: "0x", with: "")
            let padded = String(repeating: "0", count: max(0, 64 - clean.count)) + clean
            
            // Parse from right to left (little-endian)
            for i in 0..<8 {
                let endIdx = padded.count - (i * 8)
                let startIdx = endIdx - 8
                let start = padded.index(padded.startIndex, offsetBy: startIdx)
                let end = padded.index(padded.startIndex, offsetBy: endIdx)
                let chunk = String(padded[start..<end])
                result[i] = UInt32(chunk, radix: 16) ?? 0
            }
            
            return result
        }
        
        // Convert little-endian limbs to hex string
         func limbsToHex(_ limbs: [UInt32]) -> String {
            var result = ""
            for i in (0..<8).reversed() {
                result += String(format: "%08X", limbs[i])
            }
            return result
        }
    }

    
    

