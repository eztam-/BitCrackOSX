import Metal


public class KeyGen {
    
    let queue: MTLCommandQueue
    let pipelineState: MTLComputePipelineState
    
    var currentKeyBuf: MTLBuffer? = nil
    let outBuf : MTLBuffer
    let batchSizeBuff : MTLBuffer
    
    let threadgroupsPerGrid : MTLSize
    let threadsPerThreadgroup : MTLSize
    
    
    public init(device: MTLDevice, batchSize: Int, startKeyHex: String) throws {
        
        var keyGenBatchSize = batchSize
        
        self.queue = device.makeCommandQueue()!
        self.pipelineState = try Helpers.buildPipelineState(kernelFunctionName: "generate_keys")

        
        // Setting the start key only once. The Metal kernel will then store the current key + 1 in this buffer after the batch succeeded.
        // The next batch run will read its start key again from this buffer and will continue iterating from there.
        // There we are passing the same buffer without any modification to the Kernel
        self.currentKeyBuf = device.makeBuffer(length: 8 * MemoryLayout<UInt32>.stride, options: [.storageModeShared])!
        var startLimbs = Helpers.hex256ToUInt32Limbs(startKeyHex)
        memcpy(self.currentKeyBuf!.contents(), &startLimbs, 8 * MemoryLayout<UInt32>.stride)
        
        // Output buffer: numKeys * 8 limbs * 4 bytes
        let outLen = keyGenBatchSize * 8 * MemoryLayout<UInt32>.stride
        self.outBuf = device.makeBuffer(length: outLen, options: .storageModeShared)! // GPU-only, fastest if you keep on GPU
        
        // Constant buffer for numKeys
        self.batchSizeBuff = device.makeBuffer(bytes: [keyGenBatchSize],
                                              length: MemoryLayout<UInt32>.stride,
                                              options: .storageModeShared)!
        
        
        (self.threadsPerThreadgroup,  self.threadgroupsPerGrid) = try Helpers.getThreadConfig(
            pipelineState: pipelineState,
            batchSize: keyGenBatchSize,
            threadsPerThreadgroupMultiplier: 16)
  
    }
    
    
    public func run(incrementBy: UInt32 = 1) -> MTLBuffer{
        
        let cmdBuf = queue.makeCommandBuffer()!
        let encoder = cmdBuf.makeComputeCommandEncoder()!
        encoder.setComputePipelineState(pipelineState)
        encoder.setBuffer(currentKeyBuf, offset: 0, index: 0)
        encoder.setBuffer(outBuf, offset: 0, index: 1)
        encoder.setBuffer(batchSizeBuff, offset: 0, index: 2)
        
        var incrementByN = UInt32(Properties.KEYS_PER_THREAD) // FIXME: Adds unneccessary CPU overhead (same in some other hosts)
        encoder.setBytes(&incrementByN, length: MemoryLayout<UInt32>.stride, index: 3)
     
        
        encoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        // Alternatively let Metal find the best number of thread groups
        //encoder.dispatchThreads(MTLSize(width: keyGenBatchSize, height: 1, depth: 1), threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
        
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
        
        return outBuf
    }
    
    public func printThreadConf(){
        print(String(format: "    Key Gen:      │         %6d │       %6d │             %6d │",
                      threadsPerThreadgroup.width,
                      threadgroupsPerGrid.width,
                      pipelineState.threadExecutionWidth))
    }
}
