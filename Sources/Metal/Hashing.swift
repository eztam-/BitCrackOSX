import Foundation
import Metal

/// SHA256 batch compute wrapper using a small constants buffer.
/// inputBuffer: device-private buffer with concatenated messages
/// outputBuffer: device-private buffer with 8 * batchSize uint32 words
class Hashing {

    let device: MTLDevice

    let pipelineState: MTLComputePipelineState
    let inputBuffer: MTLBuffer
    let constantsBuffer: MTLBuffer

    let threadgroupsPerGrid: MTLSize
    let threadsPerThreadgroup: MTLSize

    let batchSize: Int

    /// keyLength: 33 = compressed, 65 = uncompressed
    init(on device: MTLDevice,
         batchSize: Int,
         inputBuffer: MTLBuffer,
         keyLength: UInt32) throws {

        self.device = device
        self.batchSize = batchSize
        self.inputBuffer = inputBuffer

        // Build compute pipeline
        self.pipelineState = try Helpers.buildPipelineState(
            kernelFunctionName: "sha256_ripemd160_bloom_query_kernel"
        )

        // Constants buffer: SHA256Constants { uint numMessages; uint messageSize; }
        self.constantsBuffer = device.makeBuffer(
            length: MemoryLayout<UInt32>.stride * 2,
            options: .storageModeShared
        )!

        // Fill constants once
        let ptr = constantsBuffer.contents().bindMemory(to: UInt32.self, capacity: 2)
        ptr[0] = UInt32(batchSize) // numMessages
        ptr[1] = keyLength         // messageSize (33 or 65)

        
        
        // Thread configuration
        (self.threadsPerThreadgroup, self.threadgroupsPerGrid) =
            try Helpers.getThreadConfig(
                pipelineState: pipelineState,
                batchSize: batchSize,
                threadsPerThreadgroupMultiplier: 16
            )
    }

    

    func appendCommandEncoder(commandBuffer: MTLCommandBuffer, bloomResultBuffer: MTLBuffer, bloomFilter: BloomFilter, hash160OutBuffer: MTLBuffer) {
        let encoder = commandBuffer.makeComputeCommandEncoder()!
        encoder.setComputePipelineState(pipelineState)
        encoder.setBuffer(inputBuffer, offset: 0, index: 0)
        encoder.setBuffer(bloomFilter.getBitsBuffer(), offset: 0, index: 1)
        encoder.setBuffer(constantsBuffer, offset: 0, index: 2)
        var mbits = bloomFilter.getMbits()
        encoder.setBytes(&mbits,  length: 4, index: 3)
        encoder.setBuffer(bloomResultBuffer, offset: 0, index: 4)
        encoder.setBuffer(hash160OutBuffer, offset: 0, index: 5)

        encoder.dispatchThreadgroups(threadgroupsPerGrid,threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
    }


   

}
