import Foundation
import Metal

class SHA256 {
    
    let device: MTLDevice
 
    let pipelineState: MTLComputePipelineState
    let inputBuffer: MTLBuffer
    let outputBuffer: MTLBuffer
    let numMessagesBuffer: MTLBuffer
    let messageSizeBuffer: MTLBuffer
    let threadgroupsPerGrid: MTLSize
    let threadsPerThreadgroup: MTLSize
    

    let batchSize: Int
    
    //   keyLength:  33 = compressed;  65 = uncompressed
    init(on device: MTLDevice, batchSize: Int, inputBuffer: MTLBuffer, keyLength: UInt32) throws {
        
        self.device = device
        self.batchSize = batchSize
        self.inputBuffer = inputBuffer
        self.pipelineState = try Helpers.buildPipelineState(kernelFunctionName: "sha256_batch_kernel")

        // Output buffer: uint (32bit) * 8 words per message
        let outWordCountSha256 = batchSize * 8
        self.outputBuffer = device.makeBuffer(length: outWordCountSha256 * MemoryLayout<UInt32>.stride, options: .storageModePrivate)!
        
        // numMessages buffer (we pass it as a small uniform buffer)
        var numMessagesUInt32 = UInt32(batchSize)
        self.numMessagesBuffer = device.makeBuffer(bytes: &numMessagesUInt32, length: MemoryLayout<UInt32>.stride, options: .storageModeShared)!
        
        self.messageSizeBuffer = device.makeBuffer(length: MemoryLayout<UInt32>.stride,options: .storageModeShared)!
        let ptr = messageSizeBuffer.contents().bindMemory(to: UInt32.self, capacity: 1)
        ptr.pointee = keyLength
        
        (self.threadsPerThreadgroup,  self.threadgroupsPerGrid) = try Helpers.getThreadConfig(
            pipelineState: pipelineState,
            batchSize: batchSize,
            threadsPerThreadgroupMultiplier: 16)
    
    }
    

    func appendCommandEncoder(commandBuffer: MTLCommandBuffer){
        let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
        
        commandEncoder.setComputePipelineState(pipelineState)
        commandEncoder.setBuffer(inputBuffer, offset: 0, index: 0)
        commandEncoder.setBuffer(messageSizeBuffer, offset: 0, index: 1)
        commandEncoder.setBuffer(outputBuffer, offset: 0, index: 2)
        commandEncoder.setBuffer(numMessagesBuffer, offset: 0, index: 3)
        commandEncoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        // Alternatively let Metal find the best number of thread groups
        //commandEncoder.dispatchThreads(MTLSize(width: batchSize, height: 1, depth: 1), threadsPerThreadgroup: threadsPerThreadgroup)
        commandEncoder.endEncoding()
    }

    func getOutputBuffer() -> MTLBuffer {
        return outputBuffer
    }
    
    
    // TODO: this exists in each host class. Move to common super class
    public func printThreadConf(){
        print(String(format: "    SHA256:       │         %6d │       %6d │             %6d │",
                      threadsPerThreadgroup.width,
                      threadgroupsPerGrid.width,
                      pipelineState.threadExecutionWidth))
    }
}
