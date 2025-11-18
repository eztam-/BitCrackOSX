import Foundation
import Metal

class RIPEMD160 {
    
    let device: MTLDevice
    let batchSize: Int

    let pipelineState: MTLComputePipelineState
    let inputBuffer: MTLBuffer
    let outBuffer: MTLBuffer
    let threadsPerThreadgroup: MTLSize
    let threadgroupsPerGrid: MTLSize

    
    init(on device: MTLDevice, batchSize: Int, inputBuffer: MTLBuffer) throws {
        self.device = device
        self.batchSize = batchSize
        self.inputBuffer = inputBuffer
        self.pipelineState = try Helpers.buildPipelineState(kernelFunctionName: "ripemd160_fixed32_kernel")
      
        // output: 5 uints per message
        let outWordCountRipemd160 = batchSize * 5
        self.outBuffer = device.makeBuffer(length: outWordCountRipemd160 * MemoryLayout<UInt32>.stride, options: .storageModeShared)!
        
        (self.threadsPerThreadgroup,  self.threadgroupsPerGrid) = try Helpers.getThreadConfig(
            pipelineState: pipelineState,
            batchSize: batchSize,
            threadsPerThreadgroupMultiplier: 16)
    }
    
    
    func appendCommandEncoder(commandBuffer: MTLCommandBuffer){
        let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
        commandEncoder.setComputePipelineState(pipelineState)
        commandEncoder.setBuffer(inputBuffer, offset: 0, index: 0)
        commandEncoder.setBuffer(outBuffer, offset: 0, index: 1)
        var n = UInt32(self.batchSize)
        commandEncoder.setBytes(&n, length: MemoryLayout<UInt32>.stride, index: 2)
        commandEncoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        // Alternatively let Metal find the best number of thread groups
        //commandEncoder.dispatchThreads(MTLSize(width: batchSize, height: 1, depth: 1), threadsPerThreadgroup: threadsPerThreadgroup)
        commandEncoder.endEncoding()
    }
    
    
    func getOutputBuffer() -> MTLBuffer {
        return outBuffer
    }
    
    public func printThreadConf(){
        print(String(format: "    RIPEMD160:    │         %6d │       %6d │             %6d │",
                      threadsPerThreadgroup.width,
                      threadgroupsPerGrid.width,
                      pipelineState.threadExecutionWidth))
    }
}
