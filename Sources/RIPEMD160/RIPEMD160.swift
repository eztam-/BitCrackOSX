import Foundation
import Metal
import Dispatch

class RIPEMD160 {
    
    let pipelineState: MTLComputePipelineState
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let outBuffer : MTLBuffer
    let messagesBuffer : MTLBuffer
    let threadgroupsPerGrid : MTLSize
    let threadsPerThreadgroup: MTLSize
    let batchSize: Int
    
    init(on device: MTLDevice, batchSize: Int) throws {
        self.device = device
        self.batchSize = batchSize
        self.pipelineState = try Helpers.buildPipelineState(kernelFunctionName: "ripemd160_fixed32_kernel")
        
        commandQueue = device.makeCommandQueue()!
        
        
        self.messagesBuffer = device.makeBuffer(length: batchSize*8*MemoryLayout<UInt32>.stride, options: .storageModeShared)!

        
        // output: 5 uints per message
        let outWordCount = batchSize * 5
        self.outBuffer = device.makeBuffer(length: outWordCount * MemoryLayout<UInt32>.stride, options: .storageModeShared)!
        
        (self.threadsPerThreadgroup,  self.threadgroupsPerGrid) = try Helpers.getThreadConfig(
            pipelineState: pipelineState,
            batchSize: batchSize,
            threadsPerThreadgroupMultiplier: 16)
    }
    
 
    
    func run(messagesBuffer: MTLBuffer) -> MTLBuffer {

        let cmdBuf = commandQueue.makeCommandBuffer()!
        let encoder = cmdBuf.makeComputeCommandEncoder()!
        
        encoder.setComputePipelineState(pipelineState)
        encoder.setBuffer(messagesBuffer, offset: 0, index: 0)
        encoder.setBuffer(outBuffer, offset: 0, index: 1)
        var n = UInt32(self.batchSize)
        encoder.setBytes(&n, length: MemoryLayout<UInt32>.stride, index: 2)
        encoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        // Alternatively let Metal find the best number of thread groups
        //encoder.dispatchThreads(MTLSize(width: batchSize, height: 1, depth: 1), threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
        
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
        
        return outBuffer
    }
    
    public func printThreadConf(){
        print(String(format: "    RIPEMD160:    │         %6d │       %6d │             %6d │",
                      threadsPerThreadgroup.width,
                      threadgroupsPerGrid.width,
                      pipelineState.threadExecutionWidth))
    }
    
}
