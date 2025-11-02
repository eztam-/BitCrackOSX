import Metal


public class KeyGen {
    
    let device: MTLDevice
    let library: MTLLibrary
    
    public init(library: MTLLibrary, device: MTLDevice){
        self.library = library
        self.device = device
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
    
    public func run(startKeyHex: String, batchSize: Int) -> UnsafeMutablePointer<UInt32>{
        
        let queue = device.makeCommandQueue()!
        
        let fn = library.makeFunction(name: "generate_keys_256_offset")!
        let pipeline = try? device.makeComputePipelineState(function: fn)
        
        // Example start key (all zero for demonstration)
        //let startBytes = [UInt8](repeating: 0, count: 32)
        //var startLimbs = uint32LimbsFromBytes(startBytes)
        var startLimbs = Helpers.hex256ToUInt32Limbs(startKeyHex)
        
        let startBuf = device.makeBuffer(bytes: &startLimbs,
                                         length: MemoryLayout<UInt32>.stride * 8,
                                         options: .storageModeShared)!
        
        // Example arbitrary 256-bit offset (here: small number in limb0, rest 0)
        var offsetLimbs: [UInt32] = [0x0, 0, 0, 0, 0, 0, 0, 0] // add 16 for example
        let offsetBuf = device.makeBuffer(bytes: &offsetLimbs,
                                          length: MemoryLayout<UInt32>.stride * 8,
                                          options: .storageModeShared)!
        
        // Output buffer: numKeys * 8 limbs * 4 bytes
        let outLen = batchSize * 8 * MemoryLayout<UInt32>.stride
        let outBuf = device.makeBuffer(length: outLen, options: .storageModeShared)! // GPU-only, fastest if you keep on GPU
        
        // If you need CPU readback, create a shared readback buffer and blit, or use .shared for outBuf.
        
        // Dispatch
        let cmdBuf = queue.makeCommandBuffer()!
        let encoder = cmdBuf.makeComputeCommandEncoder()!
        encoder.setComputePipelineState(pipeline!)
        encoder.setBuffer(startBuf, offset: 0, index: 0)
        encoder.setBuffer(offsetBuf, offset: 0, index: 1)
        encoder.setBuffer(outBuf, offset: 0, index: 2)
        
        // Thread sizing - choose based on device
        let threadsPerGrid = MTLSize(width: batchSize, height: 1, depth: 1)
        let w = pipeline!.threadExecutionWidth
        let maxT = pipeline!.maxTotalThreadsPerThreadgroup
        let tgWidth = min(w, batchSize)
        let threadsPerThreadgroup = MTLSize(width: tgWidth, height: 1, depth: 1)
        
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
        
        // If outBuf is private and CPU needs it, blit to a shared buffer here (not shown).
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
        
        return outBuf.contents().assumingMemoryBound(to: UInt32.self)
        // If using a shared outBuf, you could now read outBuf.contents()
    }
}
