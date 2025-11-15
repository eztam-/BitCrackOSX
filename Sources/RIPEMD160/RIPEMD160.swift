import Foundation
import Metal
import Dispatch

class RIPEMD160 {
    
    let pipelineState: MTLComputePipelineState
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let outBuffer : MTLBuffer
    let messagesBuffer : MTLBuffer
    let threadsPerGrid : MTLSize
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
        
        // Dispatch configuration: choose a reasonable threadgroup size
        let preferredTgSize = min(64, pipelineState.maxTotalThreadsPerThreadgroup)
        self.threadsPerGrid = MTLSize(width: batchSize, height: 1, depth: 1)
        self.threadsPerThreadgroup = MTLSize(width: preferredTgSize, height: 1, depth: 1)
        
    }
    
    
    func run(messagesBuffer: MTLBuffer) -> MTLBuffer {

        let cmdBuf = commandQueue.makeCommandBuffer()!
        let encoder = cmdBuf.makeComputeCommandEncoder()!
        
        encoder.setComputePipelineState(pipelineState)
        encoder.setBuffer(messagesBuffer, offset: 0, index: 0)
        encoder.setBuffer(outBuffer, offset: 0, index: 1)
        var n = UInt32(self.batchSize)
        encoder.setBytes(&n, length: MemoryLayout<UInt32>.stride, index: 2)
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
        
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
        
        return outBuffer
    }
    
    
}
