import Metal
import Foundation

public class Secp256k1 {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLComputePipelineState
    
    private let inputBatchSize: Int // Number of base private keys per batch (number of total threads in grid)
    private let outputBatchSize: Int // Number of public keys generated per batch (batchSize * Properties.KEYS_PER_THREAD)
    
    private let publicKeyBuffer: MTLBuffer
    private let inputBuffer: MTLBuffer
    private let compressedKeySearchBuffer: MTLBuffer
    
    let threadsPerThreadgroup : MTLSize
    let threadgroupsPerGrid : MTLSize
    
    public init(on device: MTLDevice, inputBatchSize : Int, outputBatchSize : Int, inputBuffer: MTLBuffer) throws {
        self.inputBatchSize = inputBatchSize
        self.outputBatchSize = outputBatchSize
        self.inputBuffer = inputBuffer
        
        self.commandQueue = device.makeCommandQueue()!
        self.device = device
        self.pipelineState = try Helpers.buildPipelineState(kernelFunctionName: "private_to_public_keys")
        
        (self.threadsPerThreadgroup,  self.threadgroupsPerGrid) = try Helpers.getThreadConfig(
            pipelineState: pipelineState,
            batchSize: self.inputBatchSize,
            threadsPerThreadgroupMultiplier: 16)
        
        let keyLength = Properties.compressedKeySearch ? 33 : 65 //   keyLength:  33 = compressed;  65 = uncompressed
        
        self.publicKeyBuffer = device.makeBuffer(
                length: MemoryLayout<UInt8>.stride * outputBatchSize * keyLength,
                options: .storageModeShared // TODO: we should mae this private for better performance. And only switch it to shared for unit tests who need that
        )!;
        
       
        var compressedKeySearch = Bool(Properties.compressedKeySearch)
        self.compressedKeySearchBuffer = device.makeBuffer(bytes: &compressedKeySearch, length: MemoryLayout<Bool>.stride, options: .storageModeShared)!
       
    }
    
    
    
    func appendCommandEncoder(commandBuffer: MTLCommandBuffer){
        let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
       
        // Configure the compute pipeline
        commandEncoder.setComputePipelineState(pipelineState)
        commandEncoder.setBuffer(inputBuffer, offset: 0, index: 0)
        commandEncoder.setBuffer(publicKeyBuffer, offset: 0, index: 1)
        commandEncoder.setBuffer(compressedKeySearchBuffer, offset: 0, index: 2)
        var batchSizeU32 = UInt32(self.inputBatchSize)
        commandEncoder.setBytes(&batchSizeU32, length: MemoryLayout<UInt32>.stride, index: 3)
        var keysPerThread = UInt32(Properties.KEYS_PER_THREAD)
        commandEncoder.setBytes(&keysPerThread, length: MemoryLayout<UInt32>.stride, index: 4)
        
        // Dispatch compute threads
        commandEncoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        // Alternatively let Metal find the best number of thread groups
        // commandEncoder.dispatchThreads(MTLSize(width: inputBatchSize, height: 1, depth: 1), threadsPerThreadgroup: threadsPerThreadgroup)
        commandEncoder.endEncoding()
    }
    
    
    public func printThreadConf(){
        print(String(format: "    Secp256k1:    │         %6d │       %6d │             %6d │",
                      threadsPerThreadgroup.width,
                      threadgroupsPerGrid.width,
                      pipelineState.threadExecutionWidth))
    }
    
    func getOutputBuffer() -> MTLBuffer {
        return publicKeyBuffer 
    }
    
}


