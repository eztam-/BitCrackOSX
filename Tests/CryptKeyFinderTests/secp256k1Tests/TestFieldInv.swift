import Metal
import Foundation
import Testing


class TestFieldInv : TestBase {

    
    init() {
        super.init(kernelFunctionName: "test_field_inv")!
    }
    
    
    // TODO: add asserts everywhere in all tests so that we can run them quickly after some change to see if anything broke
    @Test func testFieldInv() {
            
            
            print("🧪 Testing secp256k1 Field Multiplication")
            print("=" * 60)
            
            // Test cases: (a, b, expected_result)
            let testCases: [(String, String, String)] = [
                // Test 1: 1 * 1 = 1
                (
                    "0000000000000000000000000000000000000000000000000000000000000002",
                    "0000000000000000000000000000000000000000000000000000000000000000",// not needed for field inv
                    "7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF7FFFFE18"
                ),
                (
                    "00FFFFFFFFFFFFFFFFFFFFFFFFFFFFFE1AAEDCE6AF48A03BBFD25E8CD0364040",
                    "0000000000000000000000000000000000000000000000000000000000000000",// not needed for field inv
                    "af1e0c67b5033f9d518fece24289a9ced91c7f135af23706e5ac9a446b736737"
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

    
    

