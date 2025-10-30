import Metal
import BigNumber
import Foundation


class Secp256k1MetalTester: TestBase {
    
    
    init?() {
        super.init(kernelFunctionName: "tmp_test_fixes")
    }
    
    func random256(byteLength : Int)-> BInt {
        var bytes = [uint8](repeating: 0, count: 64)
        SecRandomCopyBytes(
            kSecRandomDefault,
            byteLength,
            &bytes
        )
        return BInt(bytes: bytes)
    }
  
    func testMod() {
        /*
        let P = BInt("FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F", radix: 16)!
    
        var dataForGPU = Data () // 512 bit blocks
        
        var hostResults: [BInt] = []
        var input: [UInt32] = [0,0,0,0,0,0,0,0,  0,0,0,0,0,0,0,0]
        
        let numTests = 10;
        for i in 1..<numTests {
            let l = Int.random(in: 32..<64) // mod will only kick in when >256 therefore lets create test numbers between 256 and 512 bits
            let a = random256(byteLength:l)
            //print(a)
            //print(a%P)
            //print("--")
            for by in 0..<64{
                //print("\(by) \(a.getBytes()[by])")
                //input[by]=a.getBytes()[by]
                dataForGPU.append(a.getBytes()[by])
            }
        }
        runGpuTest(
            data: dataForGPU,
            gpuFunction: "tmp_test_fixes",
            inBufferSize: numTests*64*MemoryLayout<UInt8>.size,
            outBufferSize: numTests*32*MemoryLayout<UInt8>.size)
        
        */
        //
        
      
    }
    
    
    
    
    func runGpuTest(data :Data, gpuFunction: String, inBufferSize : Int, outBufferSize : Int){
     
        do {
            guard let library = try? device.makeDefaultLibrary(bundle: Bundle.module) else {
                print("Failed to create default Metal library from module bundle")
                return
            }
            guard let funct: MTLFunction = library.makeFunction(name: gpuFunction) else {
                print("Failed to make function named \(gpuFunction) from Metal library")
                return
            }
            let pipelineState = try device.makeComputePipelineState(function: funct)
            _ = pipelineState // keep local to silence unused warning for now
        } catch {
            print("Failed to create compute pipeline state: \(error)")
            return
        }
           
  
      // Create buffers
       guard let privateKeysBuffer = device.makeBuffer(length: inBufferSize, options: .storageModeShared),
            let debugOutputBuffer = device.makeBuffer(length: outBufferSize, options: .storageModeShared) else {
          print("Failed to create Metal buffers")
          return
      }
      /*
      // Copy test data to input buffer
      let privateKeysPointer = privateKeysBuffer.contents().bindMemory(to: UInt32.self, capacity: keyCount * 8)
      for (keyIndex, privateKey) in testPrivateKeys.enumerated() {
          for (limbIndex, limb) in privateKey.enumerated() {
              privateKeysPointer[keyIndex * 8 + limbIndex] = limb
          }
      }
               */
    
                                                  
    }
    
    
  
    func runTestFixes() {
        

        //testMod()
        

        
        // Test data: private keys in LITTLE-ENDIAN format (limb[0] = LSW)
        let testPrivateKeys: [[UInt32]] = [
            [1, 0, 0, 0, 0, 0, 0, 0],              // Private key = 1
            [2, 0, 0, 0, 0, 0, 0, 0],              // Private key = 2
            [3, 0, 0, 0, 0, 0, 0, 0],              // Private key = 3
            [0xFFFFFFFF, 0, 0, 0, 0, 0, 0, 0]      // Private key = 2^32 - 1
        ]
        
        let keyCount = testPrivateKeys.count
        let privateKeyBufferSize = keyCount * 8 * MemoryLayout<UInt32>.size
        let debugOutputBufferSize = keyCount * 8 * MemoryLayout<UInt32>.size
        
        // Create buffers
        guard let privateKeysBuffer = device.makeBuffer(length: privateKeyBufferSize, options: .storageModeShared),
              let debugOutputBuffer = device.makeBuffer(length: debugOutputBufferSize, options: .storageModeShared) else {
            print("Failed to create Metal buffers")
            return
        }
        
        // Copy test data to input buffer
        let privateKeysPointer = privateKeysBuffer.contents().bindMemory(to: UInt32.self, capacity: keyCount * 8)
        for (keyIndex, privateKey) in testPrivateKeys.enumerated() {
            for (limbIndex, limb) in privateKey.enumerated() {
                privateKeysPointer[keyIndex * 8 + limbIndex] = limb
            }
        }
        
        // Create command buffer and encoder
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let commandEncoder = commandBuffer.makeComputeCommandEncoder() else {
            print("Failed to create command encoder")
            return
        }
        
        // Set up the kernel
        commandEncoder.setComputePipelineState(pipelineState)
        commandEncoder.setBuffer(privateKeysBuffer, offset: 0, index: 0)
        commandEncoder.setBuffer(debugOutputBuffer, offset: 0, index: 1)
        
        // Configure thread execution
        let threadsPerThreadgroup = MTLSize(width: min(pipelineState.maxTotalThreadsPerThreadgroup, keyCount), height: 1, depth: 1)
        let threadgroupsPerGrid = MTLSize(width: (keyCount + threadsPerThreadgroup.width - 1) / threadsPerThreadgroup.width,
                                         height: 1, depth: 1)
        
        // Dispatch the kernel
        commandEncoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        commandEncoder.endEncoding()
        
        // Execute and wait for completion
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // Check for errors
        if let error = commandBuffer.error {
            print("Metal command buffer error: \(error)")
            return
        }
        
        // Read and display results
        let debugOutputPointer = debugOutputBuffer.contents().bindMemory(to: UInt32.self, capacity: keyCount * 8)
        
        print("=== Test Results ===")
        for keyIndex in 0..<keyCount {
            let privateKey = testPrivateKeys[keyIndex]
            
            print("\n--- Test \(keyIndex + 1) ---")
            print("Input Private Key:")
            print("  Little-endian limbs: [\(privateKey.map { String(format: "0x%08X", $0) }.joined(separator: ", "))]")
            print("  As 256-bit hex: \(limbs256ToString(privateKey))")
            
            // Read output limbs
            var outputLimbs = [UInt32](repeating: 0, count: 8)
            for limbIndex in 0..<8 {
                outputLimbs[limbIndex] = debugOutputPointer[keyIndex * 8 + limbIndex]
            }
            
            print("\nOutput (field_inv result):")
            print("  Little-endian limbs: [\(outputLimbs.map { String(format: "0x%08X", $0) }.joined(separator: ", "))]")
            print("  As 256-bit hex: \(limbs256ToString(outputLimbs))")
            
            // For key=2, show expected result
            if keyIndex == 1 {
                print("\n  Expected for inv(2): 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF7FFFFE18")
            }
        }
    }
    
    // Convert little-endian limbs to big-endian hex string
    private func limbs256ToString(_ limbs: [UInt32]) -> String {
        // Limbs are stored little-endian (limbs[0] = least significant)
        // We want to display as big-endian hex (most significant first)
        var result = "0x"
        for i in (0..<8).reversed() {
            result += String(format: "%08X", limbs[i])
        }
        return result
    }
}

// Usage
func runTests() {
    print("Testing Metal secp256k1 implementation...\n")
    
    let tester = Secp256k1MetalTester()
    tester!.runTestFixes()
}

// Helper to convert hex string to little-endian UInt32 array
func hexStringToPrivateKey(_ hexString: String) -> [UInt32] {
    var result = [UInt32](repeating: 0, count: 8)
    let cleanHex = hexString.hasPrefix("0x") ? String(hexString.dropFirst(2)) : hexString
    
    // Pad to 64 characters if needed
    let paddedHex = String(repeating: "0", count: max(0, 64 - cleanHex.count)) + cleanHex
    
    // Convert big-endian hex string to little-endian limbs
    for i in 0..<8 {
        // Read from the right (LSB) going left
        let endOffset = paddedHex.count - (i * 8)
        let startOffset = endOffset - 8
        let startIndex = paddedHex.index(paddedHex.startIndex, offsetBy: startOffset)
        let endIndex = paddedHex.index(paddedHex.startIndex, offsetBy: endOffset)
        let chunk = String(paddedHex[startIndex..<endIndex])
        
        if let value = UInt32(chunk, radix: 16) {
            result[i] = value
        }
    }
    
    return result
}

/*
class Secp256k1MetalTester {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLComputePipelineState
    
    init() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            print("Failed to initialize Metal device")
            //return nil
            
            exit(0)
            // TODO
        }
        
        self.device = device
        self.commandQueue = commandQueue
        
        
        //
        let library: MTLLibrary! = try? device.makeDefaultLibrary(bundle: Bundle.module)
        guard let function = library.makeFunction(name: "tmp_test_fixes") else {
            fatalError("Failed to load function test_fixes from library")
        }
        do {
            self.pipelineState = try device.makeComputePipelineState(function: function)
        } catch {
            fatalError("Failed to create pipeline state: \(error)")
            ///
            
            
        }
    
        
       


    }
    
    func runTestFixes() {
        // Test data: private keys to test
        let testPrivateKeys: [[UInt32]] = [
            [1, 0, 0, 0, 0, 0, 0, 0],  // Private key = 1
            [2, 0, 0, 0, 0, 0, 0, 0],  // Private key = 2
            [3, 0, 0, 0, 0, 0, 0, 0],  // Private key = 3
            [0xFFFFFFFF, 0, 0, 0, 0, 0, 0, 0]  // Private key = 2^32 - 1
        ]
        
        let keyCount = testPrivateKeys.count
        let privateKeyBufferSize = keyCount * 8 * MemoryLayout<UInt32>.size
        let debugOutputBufferSize = keyCount * 8 * MemoryLayout<UInt32>.size
        
        // Create buffers
        guard let privateKeysBuffer = device.makeBuffer(length: privateKeyBufferSize, options: .storageModeShared),
              let debugOutputBuffer = device.makeBuffer(length: debugOutputBufferSize, options: .storageModeShared) else {
            print("Failed to create Metal buffers")
            return
        }
        
        // Copy test data to input buffer
        let privateKeysPointer = privateKeysBuffer.contents().bindMemory(to: UInt32.self, capacity: keyCount * 8)
        for (keyIndex, privateKey) in testPrivateKeys.enumerated() {
            for (limbIndex, limb) in privateKey.enumerated() {
                privateKeysPointer[keyIndex * 8 + limbIndex] = limb
            }
        }
        
        // Create command buffer and encoder
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let commandEncoder = commandBuffer.makeComputeCommandEncoder() else {
            print("Failed to create command encoder")
            return
        }
        
        // Set up the kernel
        commandEncoder.setComputePipelineState(pipelineState)
        commandEncoder.setBuffer(privateKeysBuffer, offset: 0, index: 0)
        commandEncoder.setBuffer(debugOutputBuffer, offset: 0, index: 1)
        
        // Configure thread execution
        let threadsPerThreadgroup = MTLSize(width: min(pipelineState.maxTotalThreadsPerThreadgroup, keyCount), height: 1, depth: 1)
        let threadgroupsPerGrid = MTLSize(width: (keyCount + threadsPerThreadgroup.width - 1) / threadsPerThreadgroup.width,
                                         height: 1, depth: 1)
        
        // Dispatch the kernel
        commandEncoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        commandEncoder.endEncoding()
        
        // Execute and wait for completion
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // Check for errors
        if let error = commandBuffer.error {
            print("Metal command buffer error: \(error)")
            return
        }
        
        // Read and display results
        let debugOutputPointer = debugOutputBuffer.contents().bindMemory(to: UInt32.self, capacity: keyCount * 8)
        
        print("=== Test Results ===")
        for keyIndex in 0..<keyCount {
            let privateKey = testPrivateKeys[keyIndex]
            print("\nPrivate Key: \(formatPrivateKey(privateKey))")
            print("Debug Output (8 limbs):")
            
            for limbIndex in 0..<8 {
                let value = debugOutputPointer[keyIndex * 8 + limbIndex]
                print("  Limb \(limbIndex): 0x\(String(format: "%08X", value))")
            }
            
            // Try to interpret as a single 256-bit number
            let debugValue = limbsToUInt256(debugOutputPointer, keyIndex: keyIndex)
            print("  As 256-bit number: \(debugValue)")
        }
    }
    
    private func formatPrivateKey(_ privateKey: [UInt32]) -> String {
        return privateKey.map { String(format: "%08X", $0) }.reversed().joined()
    }
    
    private func limbsToUInt256(_ pointer: UnsafePointer<UInt32>, keyIndex: Int) -> String {
        var result = ""
        for i in (0..<8).reversed() {
            result += String(format: "%08X", pointer[keyIndex * 8 + i])
        }
        return result
    }
}

    
    private func extractCoordinate(_ pointer: UnsafePointer<UInt32>, keyIndex: Int, offset: Int) -> String {
        var result = ""
        for i in (0..<8).reversed() {
            result += String(format: "%08X", pointer[keyIndex * 16 + offset + i]).lowercased()
        }
        return result
    }


// Usage example
func runTests() {
    print("Testing Metal secp256k1 implementation...")
    
    // First test the field arithmetic fixes
    let tester = Secp256k1MetalTester()
    print("Running field arithmetic tests...")
    tester.runTestFixes()

    
   
}

// Helper to convert hex string to UInt32 array (little-endian limbs)
func hexStringToPrivateKey(_ hexString: String) -> [UInt32] {
    var result = [UInt32](repeating: 0, count: 8)
    let cleanHex = hexString.hasPrefix("0x") ? String(hexString.dropFirst(2)) : hexString
    
    // Process 8 characters (4 bytes) at a time, little-endian
    for i in 0..<8 {
        let startIndex = cleanHex.index(cleanHex.startIndex, offsetBy: i * 8)
        let endIndex = cleanHex.index(startIndex, offsetBy: 8)
        let chunk = String(cleanHex[startIndex..<endIndex])
        
        if let value = UInt32(chunk, radix: 16) {
            result[i] = value
        }
    }
    
    return result
}

// Run the tests

*/
