import Foundation
import Metal


class SHA256 {
    
    let pipelineState: MTLComputePipelineState
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let outBuffer: MTLBuffer
    let numMessagesBuffer: MTLBuffer
    let messageSizeBuffer: MTLBuffer
    let threadgroupsPerGrid: MTLSize
    let threadsPerThreadgroup: MTLSize
    
    let batchSize: Int
    
    init(on device: MTLDevice, batchSize: Int) throws{
        self.device = device
        self.batchSize = batchSize
        self.pipelineState = try Helpers.buildPipelineState(kernelFunctionName: "sha256_batch_kernel")
        
        (self.threadsPerThreadgroup,  self.threadgroupsPerGrid) = Helpers.getThreadsPerThreadgroup(
            pipelineState: pipelineState,
            batchSize: self.batchSize,
            threadsPerThreadgroupMultiplier: 16)
        
        commandQueue = device.makeCommandQueue()!
        
        // Output buffer: uint (32bit) * 8 words per message
        let outWordCount = batchSize * 8
        self.outBuffer = device.makeBuffer(length: outWordCount * MemoryLayout<UInt32>.stride, options: [])!
        
        // numMessages buffer (we pass it as a small uniform buffer)
        var numMessagesUInt32 = UInt32(batchSize)
        self.numMessagesBuffer = device.makeBuffer(bytes: &numMessagesUInt32, length: MemoryLayout<UInt32>.stride, options: [])!
        
        // Message size in bytes (we pass it as a small uniform buffer)
        var messageSizeUInt32 = UInt32(33) // TODO: 33 = compressed 65 = uncompressed
        self.messageSizeBuffer = device.makeBuffer(bytes: &messageSizeUInt32, length: MemoryLayout<UInt32>.stride, options: [])!
        
    }
    
    func run(publicKeysBuffer: MTLBuffer) -> MTLBuffer {

        let commandBuffer = commandQueue.makeCommandBuffer()!
        let encoder = commandBuffer.makeComputeCommandEncoder()!
        
        encoder.setComputePipelineState(pipelineState)
        encoder.setBuffer(publicKeysBuffer, offset: 0, index: 0)
        encoder.setBuffer(messageSizeBuffer, offset: 0, index: 1)
        encoder.setBuffer(outBuffer, offset: 0, index: 2)
        encoder.setBuffer(numMessagesBuffer, offset: 0, index: 3)
        encoder.dispatchThreads(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        return outBuffer
    }
    
    
}
