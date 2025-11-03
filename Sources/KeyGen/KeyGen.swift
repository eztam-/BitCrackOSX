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
        
        
        // Set the start key only once
        self.currentKeyBuf = device.makeBuffer(length: 8 * MemoryLayout<UInt32>.stride,
                                              options: [.storageModeShared])!
       
        var startLimbs = Helpers.hex256ToUInt32Limbs(startKeyHex)
        memcpy(self.currentKeyBuf!.contents(), &startLimbs, 8 * MemoryLayout<UInt32>.stride)
        print("###First batch. Init start key")

    }
    
    

    
    // Utility: build 8-limb little-endian UInt32 array from 32 bytes
    func uint32LimbsFromBytes(_ b: [UInt8]) -> [UInt32] {
        precondition(b.count == 32)
        var arr = [UInt32](repeating: 0, count: 8)
        for i in 0..<8 {
            let base = i * 4
            arr[i] = UInt32(b[base]) | (UInt32(b[base+1]) << 8) | (UInt32(b[base+2]) << 16) | (UInt32(b[base+3]) << 24)
        }
        return arr
    }
    
    public func run(batchSize: Int, firstBatch: Bool) -> UnsafeMutablePointer<UInt32>{
        
       
        
        // Example start key (all zero for demonstration)
        //let startBytes = [UInt8](repeating: 0, count: 32)
        //var startLimbs = uint32LimbsFromBytes(startBytes)
       
        
        //
        // Initially send the start Key to the kernel so that it persists it on the GPU device memory
        // TODO only do this on the first batch
        
        

    
        
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
