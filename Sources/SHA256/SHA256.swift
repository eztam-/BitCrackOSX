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
    
    // Helper: pack several messages into a single byte buffer and meta array
    struct MsgMeta {
        var offset: UInt32
        var length: UInt32
    }
    
    init(on device: MTLDevice, batchSize: Int) throws {
        self.device = device
        self.batchSize = batchSize
        self.pipelineState = try Helpers.buildPipelineState(kernelFunctionName: "sha256_batch_kernel")
 
        
        
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
        
        (self.threadsPerThreadgroup,  self.threadgroupsPerGrid) = try Helpers.getThreadConfig(
            pipelineState: pipelineState,
            batchSize: batchSize,
            threadsPerThreadgroupMultiplier: 16)
        
    }
    

    
    func run(publicKeysBuffer: MTLBuffer) -> MTLBuffer {

        let commandBuffer = commandQueue.makeCommandBuffer()!
        let encoder = commandBuffer.makeComputeCommandEncoder()!
        
        encoder.setComputePipelineState(pipelineState)
        encoder.setBuffer(publicKeysBuffer, offset: 0, index: 0)
        encoder.setBuffer(messageSizeBuffer, offset: 0, index: 1)
        encoder.setBuffer(outBuffer, offset: 0, index: 2)
        encoder.setBuffer(numMessagesBuffer, offset: 0, index: 3)
        encoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        // Alternatively let Metal find the best number of thread groups
        //encoder.dispatchThreads(MTLSize(width: batchSize, height: 1, depth: 1), threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        return outBuffer
    }
    
    // TODO: this exists in each host class. Move to common super class
    public func printThreadConf(){
        print(String(format: "    SHA256:       │         %6d │       %6d │             %6d │",
                      threadsPerThreadgroup.width,
                      threadgroupsPerGrid.width,
                      pipelineState.threadExecutionWidth))
    }
    
}
