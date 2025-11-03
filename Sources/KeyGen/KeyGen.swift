import Metal


public class KeyGen {
    
    let device: MTLDevice
    let library: MTLLibrary
    var currentKeyBuf: MTLBuffer? = nil
    let queue: MTLCommandQueue
    let pipeline: MTLComputePipelineState
    
    public init(device: MTLDevice, startKeyHex: String){
        
        self.device = device
        self.library = try! device.makeDefaultLibrary(bundle: Bundle.module)
        self.queue = device.makeCommandQueue()!
        let fn = library.makeFunction(name: "generate_keys")!
        self.pipeline = try! device.makeComputePipelineState(function: fn)
        
        
        // Setting the start key only once. The Metal kernel will then store the current key + 1 in this buffer after the batch succeeded.
        // The next batch run will read its start key again from this buffer and will continue iterating from there.
        // There we are passing the same buffer without any modification to the Kernel
        self.currentKeyBuf = device.makeBuffer(length: 8 * MemoryLayout<UInt32>.stride, options: [.storageModeShared])!
        var startLimbs = Helpers.hex256ToUInt32Limbs(startKeyHex)
        memcpy(self.currentKeyBuf!.contents(), &startLimbs, 8 * MemoryLayout<UInt32>.stride)
    }
    
    
    
    public func run(batchSize: Int) -> UnsafeMutablePointer<UInt32>{
        
        // Output buffer: numKeys * 8 limbs * 4 bytes
        let outLen = batchSize * 8 * MemoryLayout<UInt32>.stride
        let outBuf = device.makeBuffer(length: outLen, options: .storageModeShared)! // GPU-only, fastest if you keep on GPU
        
        let numKeys: UInt32 = UInt32(batchSize)
        
        // Constant buffer for numKeys
        let batchSizeBuff = device.makeBuffer(bytes: [numKeys],
                                              length: MemoryLayout<UInt32>.stride,
                                              options: .storageModeShared)!
        
        // If you need CPU readback, create a shared readback buffer and blit, or use .shared for outBuf.
        
        // Dispatch
        let cmdBuf = queue.makeCommandBuffer()!
        let encoder = cmdBuf.makeComputeCommandEncoder()!
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(currentKeyBuf, offset: 0, index: 0)
        encoder.setBuffer(outBuf, offset: 0, index: 1)
        encoder.setBuffer(batchSizeBuff, offset: 0, index: 2)
        
        // Thread sizing - choose based on device
        let threadsPerGrid = MTLSize(width: batchSize, height: 1, depth: 1)
        let w = pipeline.threadExecutionWidth
        let maxT = pipeline.maxTotalThreadsPerThreadgroup
        let tgWidth = min(w, batchSize)
        let threadsPerThreadgroup = MTLSize(width: tgWidth, height: 1, depth: 1)
        
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
        
        // If outBuf is private and CPU needs it, blit to a shared buffer here (not shown).
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
        
        
        //let limbs = Helpers.pointerToLimbs(currentKeyBuf!.contents().assumingMemoryBound(to: UInt32.self))
        //Helpers.printLimbs(limbs: limbs)
        
        
        
        return outBuf.contents().assumingMemoryBound(to: UInt32.self)
        // If using a shared outBuf, you could now read outBuf.contents()
    }
}
