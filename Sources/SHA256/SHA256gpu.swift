import Foundation
import Metal


class SHA256gpu {
    
    let pipeline: MTLComputePipelineState
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    
    // Helper: pack several messages into a single byte buffer and meta array
    struct MsgMeta {
        var offset: UInt32
        var length: UInt32
    }
    
    init(on device: MTLDevice){
        self.device = device
        let library: MTLLibrary! = try? device.makeDefaultLibrary(bundle: Bundle.module)
        
        
        // If you prefer to compile shader from source at runtime, you can use device.makeLibrary(source:options:).
        // This example assumes SHA256.metal is compiled into app bundle (add file to Xcode target).
        
        let function = library.makeFunction(name: "sha256_batch_kernel")!
        
        do {
            self.pipeline = try device.makeComputePipelineState(function: function)
        } catch {
            fatalError("Failed to create pipeline state: \(error)")
        }
        commandQueue = device.makeCommandQueue()!
        
    }
    
    func run(batchOfData: [Data]) -> UnsafeMutablePointer<UInt32> {


        
        let (messageBytes, metas) = packMessages(batchOfData)
        
        // Create buffers
        let messageBuffer = device.makeBuffer(bytes: (messageBytes as NSData).bytes, length: messageBytes.count, options: [])!
        
        var metaCpy = metas // copy to mutable
        let metaBuffer = device.makeBuffer(bytes: &metaCpy, length: MemoryLayout<MsgMeta>.stride * metaCpy.count, options: [])!
        
        // Output buffer: uint (32bit) * 8 words per message
        let outWordCount = metas.count * 8
        let outBuffer = device.makeBuffer(length: outWordCount * MemoryLayout<UInt32>.stride, options: [])!
        
        // numMessages buffer (we pass it as a small uniform buffer)
        var numMessagesUInt32 = UInt32(metas.count)
        let numMessagesBuffer = device.makeBuffer(bytes: &numMessagesUInt32, length: MemoryLayout<UInt32>.stride, options: [])!
        
        // encode command
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            fatalError("Failed to create command encoder")
        }
        
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(messageBuffer, offset: 0, index: 0)
        encoder.setBuffer(metaBuffer, offset: 0, index: 1)
        encoder.setBuffer(outBuffer, offset: 0, index: 2)
        encoder.setBuffer(numMessagesBuffer, offset: 0, index: 3)
        
        // dispatch: 1 thread per message
        let threadsPerThreadgroup = MTLSize(width: pipeline.maxTotalThreadsPerThreadgroup, height: 1, depth: 1)
        let threadgroups = MTLSize(width: (metas.count + threadsPerThreadgroup.width - 1) / threadsPerThreadgroup.width,
                                   height: 1,
                                   depth: 1)
        let threadsPerGrid = MTLSize(width: metas.count, height: 1, depth: 1)
        
        //print("sha \(threadsPerGrid) \(threadsPerThreadgroup)")
        
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // Read results
        return outBuffer.contents().assumingMemoryBound(to: UInt32.self)
    }
    
    // TODO: the Sha256.metal implementation has support for different input length per nmessage. We dont need taht. Instread we can define the input length once per batch which is more performant. By that we can also remove this MsgMeta completely.
    // Length can certainly be removed but not sure about offest, because of the multi thread computation
    private func packMessages(_ messages: [Data]) -> (Data, [MsgMeta]) {
        var raw = Data()
        var metas: [MsgMeta] = []
        for msg in messages {
            let offset = UInt32(raw.count)
            metas.append(MsgMeta(offset: offset, length: UInt32(msg.count)))
            raw.append(msg)
        }
        return (raw, metas)
    }
    

    
}
