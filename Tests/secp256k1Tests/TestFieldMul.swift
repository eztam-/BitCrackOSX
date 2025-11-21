import Metal
import Foundation
import Testing
import Security
import BigNumber
import keysearch

class TestFieldMul: TestBase {
   
    
    init() {
        super.init(kernelFunctionName: "test_field_mul")
    }
    
    @Test func testFieldMulRandomInput() {
        
        let numTests = 1000
        print("Running \(numTests) random number tests. Only printing failed results.")
        
        var numFailedTests = 0
        
        for _ in 0..<numTests {
            let aHex = Helpers.generateRandom256BitHex();
            let bHex = Helpers.generateRandom256BitHex();
            
            let aLimbs = hexToLimbs(aHex)
            let bLimbs = hexToLimbs(bHex)
            
            // Calculate expected result
            let product = BInt(aHex, radix: 16)! * BInt(bHex, radix: 16)!
            let p = BInt("FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F", radix: 16)!
            let expected = product % p
            var expectedHex = expected.asString(radix: 16).uppercased()
            
            // Adding missing trailing zeros
            for _ in expectedHex.count..<64{
                expectedHex = "\(0)\(expectedHex)"
            }
            
            //let expectedLimbs = hexToLimbs(expectedHex)
            
            
            guard let result = multiply(aLimbs, bLimbs) else {
                print("❌ Test failed - Metal execution error")
                continue
            }
            
            let passed = limbsToHex(result) == expectedHex
            
            // Only print failed results
            if !passed {
                numFailedTests+=1
                print("  Input A:  \(aHex)")
                print("  Input B:  \(bHex)")
                print("  Expected: \(expectedHex)")
                print("  Got:      \(limbsToHex(result))")
                print("  Status:   \(passed ? "✅ PASS" : "❌ FAIL")")
            
               // print("  Debug - Expected limbs: \(expectedLimbs.map { String(format: "0x%08X", $0) })")
               // print("  Debug - Got limbs:      \(result.map { String(format: "0x%08X", $0) })")
            }
        }
        print("🧪 \(numFailedTests) of \(numTests) tests have failed")
        assert(numFailedTests==0)
        

    }
    
    @Test func testFieldMul() {
                        
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
                    "00000000000000000000000000000000000000000000000000000002000007A0" 
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
                ),
                // Two large numbers
                (
                    "79C9C34D615F7CBED1C176B50B68C7A02C8998767E8FE1A5BB5E3EA89F8921C3",
                    "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE1AAEDCE6AF48A03BBFD25E8CD0364040",
                    "71a53aefe4a52ec1b67035b21d9eccd9fbbfa2ed9671205282b0dfdb8138946f"
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
                    assertionFailure()
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
            guard let commandBuffer = super.commandQueue.makeCommandBuffer(),
                  let encoder = commandBuffer.makeComputeCommandEncoder() else {
                print("❌ Failed to create command encoder")
                return nil
            }
            
            encoder.setComputePipelineState(super.pipelineState)
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

    
    

