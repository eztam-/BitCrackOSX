import Foundation
import Metal

// Calculates SHA256 followed by RIPEMD160 for a batch of public keys
class SHA256 {
    
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    
    let pipelineStateSha256: MTLComputePipelineState
    let outBufferSha256: MTLBuffer
    let numMessagesBufferSha256: MTLBuffer
    let messageSizeBufferSha256: MTLBuffer
    let threadgroupsPerGridSha256: MTLSize
    let threadsPerThreadgroupSha256: MTLSize
    
    let ripemd160: RIPEMD160
    
    
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
        
        
        self.ripemd160 = try RIPEMD160(on: device, batchSize: batchSize, inputBuffer: outBufferSha256)
        
    }
    

    /**
        keyLength:  33 = compressed;  65 = uncompressed
     */
    func run(publicKeysBuffer: MTLBuffer, keyLength: UInt32) -> MTLBuffer {

        let commandBuffer = commandQueue.makeCommandBuffer()!
        appendSha256Encoder(commandBuffer: commandBuffer, inputBuffer: publicKeysBuffer, keyLength: keyLength)
        ripemd160.appendRipemd160Encoder(commandBuffer: commandBuffer)
        
        // Submit work for both SHA256 and RIPEMD160
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        return ripemd160.getOutputBuffer()
    }
    
    // TODO: this exists in each host class. Move to common super class
    public func printThreadConf(){
        print(String(format: "   Hashing:       │         %6d │       %6d │             %6d │",
                      threadsPerThreadgroupSha256.width,
                      threadgroupsPerGridSha256.width,
                      pipelineStateSha256.threadExecutionWidth))
    }
    
    
    func appendSha256Encoder(commandBuffer: MTLCommandBuffer, inputBuffer: MTLBuffer, keyLength: UInt32){
        let encoderSha256 = commandBuffer.makeComputeCommandEncoder()!
        
        let ptr = messageSizeBufferSha256.contents().bindMemory(to: UInt32.self, capacity: 1)
        ptr.pointee = keyLength
        
        encoderSha256.setComputePipelineState(pipelineStateSha256)
        encoderSha256.setBuffer(inputBuffer, offset: 0, index: 0)
        encoderSha256.setBuffer(messageSizeBufferSha256, offset: 0, index: 1)
        encoderSha256.setBuffer(outBufferSha256, offset: 0, index: 2)
        encoderSha256.setBuffer(numMessagesBufferSha256, offset: 0, index: 3)
        encoderSha256.dispatchThreadgroups(threadgroupsPerGridSha256, threadsPerThreadgroup: threadsPerThreadgroupSha256)
        // Alternatively let Metal find the best number of thread groups
        //encoder.dispatchThreads(MTLSize(width: batchSize, height: 1, depth: 1), threadsPerThreadgroup: threadsPerGroup)
        encoderSha256.endEncoding()
    }

    
}
