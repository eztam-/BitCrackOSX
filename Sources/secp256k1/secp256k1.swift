import Metal
import Foundation

public class Secp256k1_GPU {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLComputePipelineState
    private let bufferSize: Int // Number of private keys per batch
    
    //private let privateKeyBuffer: MTLBuffer
    private let publicKeyBufferComp: MTLBuffer
    private let publicKeyBufferUncomp: MTLBuffer
    
    let threadsPerThreadgroup : MTLSize
    let threadgroupsPerGrid : MTLSize
    
    public init(on device: MTLDevice, bufferSize : Int) {
        self.bufferSize = bufferSize
        let commandQueue = device.makeCommandQueue()!
        
        self.device = device
        self.commandQueue = commandQueue
        
        
        let library: MTLLibrary! = try? device.makeDefaultLibrary(bundle: Bundle.module)
        guard let function = library.makeFunction(name: "private_to_public_keys") else {
            fatalError("Failed to load function private_to_public_keys from library")
        }
        do {
            self.pipelineState = try device.makeComputePipelineState(function: function)
        } catch {
            fatalError("Failed to create pipeline state: \(error)")
        }
        
        
        // Create Metal buffers
        //let privateKeyBuffer = device.makeBuffer(
        //    length: MemoryLayout<UInt32>.stride * bufferSize * 8,
        //    options: .storageModeShared
        //)!;
        let publicKeyBufferComp = device.makeBuffer(
                length: MemoryLayout<UInt8>.stride * bufferSize * 33, // Compressed public key is 256 bits + 8 bits = 33 bytes
                options: .storageModeShared // TODO: we should mae this private for better performance. And only switch it to shared for unit tests who need that
        )!;
        let publicKeyBufferUncomp = device.makeBuffer(
                length: MemoryLayout<UInt8>.stride * bufferSize * 65, // Uncompressed public key is 512 bits + 8 bits = 65 bytes
                options: .storageModeShared // TODO: we should mae this private for better performance. And only switch it to shared for unit tests who need that
        )!;
        
       // self.privateKeyBuffer = privateKeyBuffer
        self.publicKeyBufferComp = publicKeyBufferComp
        self.publicKeyBufferUncomp = publicKeyBufferUncomp
        
    
        
        // Calculate thread execution width
        self.threadsPerThreadgroup = MTLSize(
            width: min(pipelineState.threadExecutionWidth, bufferSize),
            height: 1,
            depth: 1
        )
        self.threadgroupsPerGrid = MTLSize(
            width: (bufferSize + threadsPerThreadgroup.width - 1) / threadsPerThreadgroup.width,
            height: 1,
            depth: 1
        )
     
        
    }
    
    
    public func generatePublicKeys(privateKeyBuffer: MTLBuffer) -> (MTLBuffer, MTLBuffer) {

        // Create command buffer and encoder
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
        
        // Configure the compute pipeline
        commandEncoder.setComputePipelineState(pipelineState)
        commandEncoder.setBuffer(privateKeyBuffer, offset: 0, index: 0)
        commandEncoder.setBuffer(publicKeyBufferComp, offset: 0, index: 1)
        commandEncoder.setBuffer(publicKeyBufferUncomp, offset: 0, index: 2)
        
        
        // Dispatch compute threads
        commandEncoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        commandEncoder.endEncoding()
        

        // Execute and wait for completion
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    
        
        return (publicKeyBufferComp, publicKeyBufferUncomp)
    }
}


