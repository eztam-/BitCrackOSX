import Foundation
import Metal
import Testing



class Sha256Test: TestBase{
    
    init() {
        super.init(kernelFunctionName: "sha256_test_kernel")
    }
    
    @Test func runSha256Test() throws {
               
        let commandQueue = device.makeCommandQueue()!
        
        // Test message: "abc"
        let messageBytes = Array("abc".utf8)  // [0x61, 0x62, 0x63]
        let msgLen = UInt32(messageBytes.count)
        
        // Buffers
        let inputBuffer = device.makeBuffer(bytes: messageBytes,
                                            length: messageBytes.count,
                                            options: .storageModeShared)!
        
        var lenCopy = msgLen
        let lengthBuffer = device.makeBuffer(bytes: &lenCopy,
                                             length: MemoryLayout<UInt32>.size,
                                             options: .storageModeShared)!
        
        let outputBuffer = device.makeBuffer(length: MemoryLayout<UInt32>.size * 8,
                                             options: .storageModeShared)!
        
        // Encode command buffer
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw NSError(domain: "SHA256Test", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create command buffer or encoder"])
        }
        
        encoder.setComputePipelineState(super.pipelineState)
        encoder.setBuffer(inputBuffer,  offset: 0, index: 0)
        encoder.setBuffer(lengthBuffer, offset: 0, index: 1)
        encoder.setBuffer(outputBuffer, offset: 0, index: 2)
        
        // Launch exactly 1 thread
        let threadsPerGrid = MTLSize(width: 1, height: 1, depth: 1)
        let threadsPerThreadgroup = MTLSize(width: 1, height: 1, depth: 1)
        encoder.dispatchThreads(threadsPerGrid,
                                threadsPerThreadgroup: threadsPerThreadgroup)
        
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // Read back 8 x UInt32 state
        let ptr = outputBuffer.contents().bindMemory(to: UInt32.self, capacity: 8)
        var words = [UInt32](repeating: 0, count: 8)
        for i in 0..<8 {
            words[i] = ptr[i]
        }
        
        // Convert to 32 bytes (big-endian per word)
        var digestBytes = [UInt8]()
        digestBytes.reserveCapacity(32)
        for w in words {
            digestBytes.append(UInt8((w >> 24) & 0xff))
            digestBytes.append(UInt8((w >> 16) & 0xff))
            digestBytes.append(UInt8((w >>  8) & 0xff))
            digestBytes.append(UInt8( w        & 0xff))
        }
        
        let expected = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        let digestData = Data(digestBytes)
        let digestHex = digestData.hexString
        print("SHA256(\"abc\") = \(digestHex)")
        print("Expected       = \(expected)")
        
        assert(digestHex == expected)
    }

    
}
