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
    
    init(on device: MTLDevice, batchSize: Int){
        self.device = device
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
    
    
    func run(messagesData: Data, messageCount: Int) -> UnsafeMutablePointer<UInt32> {
        
        // Host for ripemd160_fixed32_kernel
        // - Packs N messages, each exactly 32 bytes (if you have shorter strings, left-pad or right-pad them on the host)
        // - Dispatches GPU kernel and reads back 5 uint words per message.
        // - Converts words to canonical RIPEMD-160 hex (little-endian word order).
        // TODO: don't recreate the buffer each time this is costy
        let messagesBuffer = device.makeBuffer(bytes: (messagesData as NSData).bytes, length: messagesData.count, options: [])!


        

        // Build and dispatch
        let cmdBuf = commandQueue.makeCommandBuffer()!
        let encoder = cmdBuf.makeComputeCommandEncoder()!
        
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(messagesBuffer, offset: 0, index: 0)
        encoder.setBuffer(outBuffer, offset: 0, index: 1)
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
        
       
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
    
        
        let outWordCount = messageCount * 5
        return outBuffer.contents().bindMemory(to: UInt32.self, capacity: outWordCount)

    }
    
    
   
  
    
}
