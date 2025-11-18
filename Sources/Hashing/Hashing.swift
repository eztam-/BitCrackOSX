import Foundation
import Metal

// Calculates SHA256 followed by RIPEMD160 for a batch of public keys
class Hashing {
    
    // General
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    
    // SHA256
    let pipelineStateSha256: MTLComputePipelineState
    let outBufferSha256: MTLBuffer
    let numMessagesBufferSha256: MTLBuffer
    let messageSizeBufferSha256: MTLBuffer
    let threadgroupsPerGridSha256: MTLSize
    let threadsPerThreadgroupSha256: MTLSize
    
    // RIPEMD160
    let pipelineStateRipemd160: MTLComputePipelineState
    let outBufferRipemd160: MTLBuffer
    let threadsPerThreadgroupRipemd160: MTLSize
    let threadgroupsPerGridRipemd160: MTLSize
    
    
    let batchSize: Int
    
    // Helper: pack several messages into a single byte buffer and meta array
    struct MsgMeta {
        var offset: UInt32
        var length: UInt32
    }
    
    init(on device: MTLDevice, batchSize: Int) throws {
        self.device = device
        self.batchSize = batchSize
        self.pipelineStateSha256 = try Helpers.buildPipelineState(kernelFunctionName: "sha256_batch_kernel")
 
        
        // SHA256
        // --------------------------------------------------
        commandQueue = device.makeCommandQueue()!
        
        // Output buffer: uint (32bit) * 8 words per message
        let outWordCountSha256 = batchSize * 8
        self.outBufferSha256 = device.makeBuffer(length: outWordCountSha256 * MemoryLayout<UInt32>.stride, options: .storageModePrivate)!
        
        // numMessages buffer (we pass it as a small uniform buffer)
        var numMessagesUInt32 = UInt32(batchSize)
        self.numMessagesBufferSha256 = device.makeBuffer(bytes: &numMessagesUInt32, length: MemoryLayout<UInt32>.stride, options: .storageModeShared)!
        
        // Message size in bytes (we pass it as a small uniform buffer)
       // var messageSizeUInt32 = UInt32(33) // TODO: 33 = compressed 65 = uncompressed
        //self.messageSizeBuffer = device.makeBuffer(bytes: &messageSizeUInt32, length: MemoryLayout<UInt32>.stride, options: [])!
        
        self.messageSizeBufferSha256 = device.makeBuffer(length: MemoryLayout<UInt32>.stride,options: .storageModeShared)!
          
        
        (self.threadsPerThreadgroupSha256,  self.threadgroupsPerGridSha256) = try Helpers.getThreadConfig(
            pipelineState: pipelineStateSha256,
            batchSize: batchSize,
            threadsPerThreadgroupMultiplier: 16)
        
    
        
        // RIPEMD160
        // --------------------------------------------------
        self.pipelineStateRipemd160 = try Helpers.buildPipelineState(kernelFunctionName: "ripemd160_fixed32_kernel")
      
        // output: 5 uints per message
        let outWordCountRipemd160 = batchSize * 5
        self.outBufferRipemd160 = device.makeBuffer(length: outWordCountRipemd160 * MemoryLayout<UInt32>.stride, options: .storageModeShared)!
        
        (self.threadsPerThreadgroupRipemd160,  self.threadgroupsPerGridRipemd160) = try Helpers.getThreadConfig(
            pipelineState: pipelineStateRipemd160,
            batchSize: batchSize,
            threadsPerThreadgroupMultiplier: 16)
        
        
    }
    

    /**
        keyLength:  33 = compressed;  65 = uncompressed
     */
    func run(publicKeysBuffer: MTLBuffer, keyLength: UInt32) -> MTLBuffer {

        let commandBuffer = commandQueue.makeCommandBuffer()!
        let encoderSha256 = commandBuffer.makeComputeCommandEncoder()!
        
        let ptr = messageSizeBufferSha256.contents().bindMemory(to: UInt32.self, capacity: 1)
        ptr.pointee = keyLength
        
        encoderSha256.setComputePipelineState(pipelineStateSha256)
        encoderSha256.setBuffer(publicKeysBuffer, offset: 0, index: 0)
        encoderSha256.setBuffer(messageSizeBufferSha256, offset: 0, index: 1)
        encoderSha256.setBuffer(outBufferSha256, offset: 0, index: 2)
        encoderSha256.setBuffer(numMessagesBufferSha256, offset: 0, index: 3)
        encoderSha256.dispatchThreadgroups(threadgroupsPerGridSha256, threadsPerThreadgroup: threadsPerThreadgroupSha256)
        // Alternatively let Metal find the best number of thread groups
        //encoder.dispatchThreads(MTLSize(width: batchSize, height: 1, depth: 1), threadsPerThreadgroup: threadsPerGroup)
        encoderSha256.endEncoding()
        
        
        // RIPEMD160
      
        let encoderRipemd160 = commandBuffer.makeComputeCommandEncoder()!
        
        encoderRipemd160.setComputePipelineState(pipelineStateRipemd160)
        encoderRipemd160.setBuffer(outBufferSha256, offset: 0, index: 0)
        encoderRipemd160.setBuffer(outBufferRipemd160, offset: 0, index: 1)
        var n = UInt32(self.batchSize)
        encoderRipemd160.setBytes(&n, length: MemoryLayout<UInt32>.stride, index: 2)
        encoderRipemd160.dispatchThreadgroups(threadgroupsPerGridRipemd160, threadsPerThreadgroup: threadsPerThreadgroupRipemd160)
        // Alternatively let Metal find the best number of thread groups
        //encoder.dispatchThreads(MTLSize(width: batchSize, height: 1, depth: 1), threadsPerThreadgroup: threadsPerGroup)
        encoderRipemd160.endEncoding()
        
        
        // Submit work for both SHA256 and RIPEMD160
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        return outBufferRipemd160
    }
    
    // TODO: this exists in each host class. Move to common super class
    public func printThreadConf(){
        print(String(format: "    SHA256:       │         %6d │       %6d │             %6d │",
                      threadsPerThreadgroupSha256.width,
                      threadgroupsPerGridSha256.width,
                      pipelineStateSha256.threadExecutionWidth))
    }
    
}
