import Foundation
import Metal
import Dispatch

class RIPEMD160 {
    
    let pipeline: MTLComputePipelineState
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let outBuffer : MTLBuffer
    let messagesBuffer : MTLBuffer
    let threadsPerGrid : MTLSize
    let threadsPerThreadgroup: MTLSize
    let batchSize: Int
    
    init(on device: MTLDevice, batchSize: Int){
        self.device = device
        self.batchSize = batchSize
        
        let library: MTLLibrary! = try? device.makeDefaultLibrary(bundle: Bundle.module)
        
        // If you prefer to compile shader from source at runtime, you can use device.makeLibrary(source:options:).
        // This example assumes XXX.metal is compiled into app bundle (add file to Xcode target).
        guard let function = library.makeFunction(name: "ripemd160_fixed32_kernel") else {
            fatalError("Failed to load function ripemd160_fixed32_kernel from library")
        }
        do {
            self.pipeline = try device.makeComputePipelineState(function: function)
        } catch {
            fatalError("Failed to create pipeline state: \(error)")
        }
        commandQueue = device.makeCommandQueue()!
        
        
        self.messagesBuffer = device.makeBuffer(length: batchSize*8*MemoryLayout<UInt32>.stride, options: .storageModeShared)!

        
        // output: 5 uints per message
        let outWordCount = batchSize * 5
        self.outBuffer = device.makeBuffer(length: outWordCount * MemoryLayout<UInt32>.stride, options: .storageModeShared)!
        
        // Dispatch configuration: choose a reasonable threadgroup size
        let preferredTgSize = min(64, pipeline.maxTotalThreadsPerThreadgroup)
        self.threadsPerGrid = MTLSize(width: batchSize, height: 1, depth: 1)
        self.threadsPerThreadgroup = MTLSize(width: preferredTgSize, height: 1, depth: 1)
        
    }
    
    
    func run(messagesBuffer: MTLBuffer) -> MTLBuffer {

        let cmdBuf = commandQueue.makeCommandBuffer()!
        let encoder = cmdBuf.makeComputeCommandEncoder()!
        
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(messagesBuffer, offset: 0, index: 0)
        encoder.setBuffer(outBuffer, offset: 0, index: 1)
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
        
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
        
        return outBuffer
    }
    
    
}
