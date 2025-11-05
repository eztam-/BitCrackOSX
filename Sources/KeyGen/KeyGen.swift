import Metal


public class KeyGen {
    
    let device: MTLDevice
    let library: MTLLibrary
    var currentKeyBuf: MTLBuffer? = nil
    let queue: MTLCommandQueue
    let pipeline: MTLComputePipelineState
    
    let outBuf : MTLBuffer
    
    // Constant buffer for numKeys
    let batchSizeBuff : MTLBuffer
    
    let threadsPerGrid : MTLSize
    let threadsPerThreadgroup : MTLSize
    
    public init(device: MTLDevice, batchSize: Int, startKeyHex: String){
        
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
        
        // Output buffer: numKeys * 8 limbs * 4 bytes
        let outLen = batchSize * 8 * MemoryLayout<UInt32>.stride
        self.outBuf = device.makeBuffer(length: outLen, options: .storageModeShared)! // GPU-only, fastest if you keep on GPU
        
        // Constant buffer for numKeys
        self.batchSizeBuff = device.makeBuffer(bytes: [batchSize],
                                              length: MemoryLayout<UInt32>.stride,
                                              options: .storageModeShared)!
        
        
        
        

        
        
        // Thread sizing - choose based on device
        self.threadsPerGrid = MTLSize(width: batchSize, height: 1, depth: 1)
        let w = pipeline.threadExecutionWidth
        let maxT = pipeline.maxTotalThreadsPerThreadgroup
        let tgWidth = min(w, batchSize)
        self.threadsPerThreadgroup = MTLSize(width: tgWidth, height: 1, depth: 1)
        
        
        
    }
    
    
    
    public func run() -> MTLBuffer{
        
        
        // Dispatch
        let cmdBuf = queue.makeCommandBuffer()!
        let encoder = cmdBuf.makeComputeCommandEncoder()!
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(currentKeyBuf, offset: 0, index: 0)
        encoder.setBuffer(outBuf, offset: 0, index: 1)
        encoder.setBuffer(batchSizeBuff, offset: 0, index: 2)
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()

        //print("keyg \(threadsPerGrid) \(threadsPerThreadgroup)")
        
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
        
        //let limbs = Helpers.pointerToLimbs(currentKeyBuf!.contents().assumingMemoryBound(to: UInt32.self))
        //Helpers.printLimbs(limbs: limbs)
        
        return outBuf
    }
}
