import Metal
import Foundation
import Testing
import Security
import BigNumber
import CryptKeySearch

class TestFieldSub: TestBase {
   
    
    init() {
        super.init(kernelFunctionName: "test_field_sub")!
    }
    
    @Test func testFieldSubRandomInput() {
        
        let numTests = 1000
        print("Running \(numTests) random number tests. Only printing failed results.")
        
        var numFailedTests = 0
        
        for _ in 0..<numTests {
            let aHex = Helpers.generateRandom256BitHex();
            let bHex = Helpers.generateRandom256BitHex();
            
            let aLimbs = hexToLimbs(aHex)
            let bLimbs = hexToLimbs(bHex)
            
            // Calculate expected result
            let res = BInt(aHex, radix: 16)! - BInt(bHex, radix: 16)!
            let p = BInt("FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F", radix: 16)!
            var expected = res % p
            if expected.signum() < 0 {
                expected = expected + p
            }
            var expectedHex = expected.asString(radix: 16).uppercased()
            
            
            // Adding missing trailing zeros
            for i in expectedHex.count..<64{
                expectedHex = "\(0)\(expectedHex)"
            }
            
            let expectedLimbs = hexToLimbs(expectedHex)
            
            
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
    
    @Test func testFieldSub() {
                        
            print("🧪 Testing secp256k1 Field Subtraction")
            print("=" * 60)
            
            // Test cases: (a, b, expected_result)
            let testCases: [(String, String, String)] = [
                (
                    "51aad8b5bdd7a269a553623f93d2c8a709875ed2bad972ca785a9def04a8d01e",
                    "2b330d78bc34a265592692ce84ae67fd0cbe50f6a3a524a59f10a625660c5119",
                    "2677CB3D01A300044C2CCF710F2460A9FCC90DDC17344E24D949F7C99E9C7F05"
                ),
                (
                    "195f2c6c3fd379800ca137162d882ebeef5dc86a33fb3690b332922f56d028b4",
                    "1bbcdac52e0f0f4bf22ccb1c5e3fce110a994549148246144cde6587db0704cb",
                    "FDA251A711C46A341A746BF9CF4860ADE4C483211F78F07C66542CA67BC92018"
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

    
    

