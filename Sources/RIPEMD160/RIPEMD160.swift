import Foundation
import Metal
import Dispatch

class RIPEMD160 {
    
    let pipeline: MTLComputePipelineState
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    
    
    init(on device: MTLDevice){
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
        
    }
    
    
    func run(messagesData: Data, messageCount: Int) -> UnsafeMutablePointer<UInt32> {
        
        // Host for ripemd160_fixed32_kernel
        // - Packs N messages, each exactly 32 bytes (if you have shorter strings, left-pad or right-pad them on the host)
        // - Dispatches GPU kernel and reads back 5 uint words per message.
        // - Converts words to canonical RIPEMD-160 hex (little-endian word order).

        let queue = device.makeCommandQueue()!
        
        let messagesBuffer = device.makeBuffer(bytes: (messagesData as NSData).bytes, length: messagesData.count, options: [])!
        
        // output: 5 uints per message
        let outWordCount = messageCount * 5
        let outBuffer = device.makeBuffer(length: outWordCount * MemoryLayout<UInt32>.stride, options: .storageModeShared)!
        
        // small numMessages buffer (because Metal disallows scalar [[buffer]]).
        var numMessages: UInt32 = UInt32(messageCount)
        let numMessagesBuffer = device.makeBuffer(bytes: &numMessages, length: MemoryLayout<UInt32>.stride, options: [])!
        
        // Dispatch configuration: choose a reasonable threadgroup size
        let preferredTgSize = min(64, pipeline.maxTotalThreadsPerThreadgroup)
        let threadsPerGrid = MTLSize(width: messageCount, height: 1, depth: 1)
        let threadsPerThreadgroup = MTLSize(width: preferredTgSize, height: 1, depth: 1)
        
        // Build and dispatch
        guard let cmdBuf = queue.makeCommandBuffer(),
              let encoder = cmdBuf.makeComputeCommandEncoder() else {
            fatalError("Failed to create command encoder")
        }
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(messagesBuffer, offset: 0, index: 0)
        encoder.setBuffer(outBuffer, offset: 0, index: 1)
        encoder.setBuffer(numMessagesBuffer, offset: 0, index: 2)
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
        
       // let start = CFAbsoluteTimeGetCurrent()
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
       // let end = CFAbsoluteTimeGetCurrent()
       // let elapsed = end - start
       // let mbProcessed = Double(messageCount * 32) / (1024.0*1024.0)
      //  let hashesPerSec = Double(messageCount) / elapsed
        //print(String(format: "GPU elapsed: %.4f s — %0.2f MB processed — %.0f hashes/s", elapsed, mbProcessed, hashesPerSec))
        
        
        return outBuffer.contents().bindMemory(to: UInt32.self, capacity: outWordCount)

    }
    
    
   
  
    
}
