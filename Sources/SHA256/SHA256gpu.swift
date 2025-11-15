import Foundation
import Metal


class SHA256gpu {
    
    let pipeline: MTLComputePipelineState
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let outBuffer: MTLBuffer
    let numMessagesBuffer: MTLBuffer
    let messageSizeBuffer: MTLBuffer
    let threadsPerGrid: MTLSize
    let threadsPerThreadgroup: MTLSize
    
    let batchSize: Int
    
    // Helper: pack several messages into a single byte buffer and meta array
    struct MsgMeta {
        var offset: UInt32
        var length: UInt32
    }
    
    init(on device: MTLDevice, batchSize: Int){
        self.device = device
        self.batchSize = batchSize
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
        
        // Output buffer: uint (32bit) * 8 words per message
        let outWordCount = batchSize * 8
        self.outBuffer = device.makeBuffer(length: outWordCount * MemoryLayout<UInt32>.stride, options: [])!
        
        // numMessages buffer (we pass it as a small uniform buffer)
        var numMessagesUInt32 = UInt32(batchSize)
        self.numMessagesBuffer = device.makeBuffer(bytes: &numMessagesUInt32, length: MemoryLayout<UInt32>.stride, options: [])!
        
        // Message size in bytes (we pass it as a small uniform buffer)
        var messageSizeUInt32 = UInt32(33) // TODO: 33 = compressed 65 = uncompressed
        self.messageSizeBuffer = device.makeBuffer(bytes: &messageSizeUInt32, length: MemoryLayout<UInt32>.stride, options: [])!
        
        
        // dispatch: 1 thread per message
    
        /*
         let threadsPerThreadgroup = MTLSize(width: pipeline.maxTotalThreadsPerThreadgroup, height: 1, depth: 1)
        
         let threadgroups = MTLSize(width: (metas.count + threadsPerThreadgroup.width - 1) / threadsPerThreadgroup.width,
                                    height: 1,
                                    depth: 1)
         let threadsPerGrid = MTLSize(width: metas.count, height: 1, depth: 1)
         */
        
        self.threadsPerGrid = MTLSize(width: batchSize, height: 1, depth: 1)
        self.threadsPerThreadgroup = MTLSize(width: pipeline.threadExecutionWidth, height: 1, depth: 1)

        //print("sha \(threadsPerGrid) \(threadsPerThreadgroup)")
        
    }
    
    func run(publicKeysBuffer: MTLBuffer) -> MTLBuffer {

        let commandBuffer = commandQueue.makeCommandBuffer()!
        let encoder = commandBuffer.makeComputeCommandEncoder()!
        
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(publicKeysBuffer, offset: 0, index: 0)
        encoder.setBuffer(messageSizeBuffer, offset: 0, index: 1)
        encoder.setBuffer(outBuffer, offset: 0, index: 2)
        encoder.setBuffer(numMessagesBuffer, offset: 0, index: 3)
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        return outBuffer
    }
    
    
}
