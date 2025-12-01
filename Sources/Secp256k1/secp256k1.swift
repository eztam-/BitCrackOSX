import Metal
import Foundation

public class Secp256k1 {
    
    
    // Metal layout mirrors (match your Metal structs exactly)
    // Metal sizes → uint256: 32, PointJacobian: 100, ThreadState: 132
    // Swift sizes → U256: 32, PointJacobian: 100, ThreadState: 132
    @frozen public struct U256 {
        public var limbs: (UInt32,UInt32,UInt32,UInt32,UInt32,UInt32,UInt32,UInt32)
    }

    @frozen public struct Point {
        public var X: U256
        public var Y: U256
        public var infinity: UInt8              // Metal bool = 1 byte
        public var _pad: (UInt8, UInt8, UInt8)  // pad to 4-byte alignment
    }

    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue

    private let initPipeline: MTLComputePipelineState
    private let processPipeline: MTLComputePipelineState

    private let batchSize: Int
    private var batchSizeU32: UInt32
    private let keysPerThread: Int
    private var keysPerThreadU32: UInt32

    
    private let compressed: Bool
    private let publicKeyLength: Int

    private var basePrivateKeyBuffer: MTLBuffer
    private var basePublicPointsBuffer: MTLBuffer
    private let deltaGBuffer: MTLBuffer
    private let publicKeyBuffer: MTLBuffer
    private let compressedFlagBuffer: MTLBuffer
    let startKeyBuffer: MTLBuffer
    
    private let startKeyHex: String
    let threadsPerThreadgroup: MTLSize
    let threadgroupsPerGrid: MTLSize

    
    public init(on device: MTLDevice, batchSize: Int, keysPerThread: Int, compressed: Bool, startKeyHex: String) throws {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        self.batchSize = batchSize
        self.keysPerThread = keysPerThread
        self.compressed = compressed
        self.publicKeyLength = compressed ? 33 : 65
        self.startKeyHex = startKeyHex
        self.batchSizeU32 = UInt32(batchSize)
        self.keysPerThreadU32 = UInt32(keysPerThread)
        
        self.initPipeline = try Helpers.buildPipelineState(kernelFunctionName: "init_base_points")
        self.processPipeline = try Helpers.buildPipelineState(kernelFunctionName: "process_batch_incremental")

        (threadsPerThreadgroup, threadgroupsPerGrid) = try Helpers.getThreadConfig(
            pipelineState: processPipeline,
            batchSize: batchSize,
            threadsPerThreadgroupMultiplier: 16
        )

        // Buffers
        self.basePrivateKeyBuffer = device.makeBuffer(length: 8 * MemoryLayout<UInt32>.stride, options: .storageModeShared)!
        self.basePublicPointsBuffer = device.makeBuffer(length: batchSize * MemoryLayout<Point>.stride, options: .storageModePrivate)!
        self.deltaGBuffer = device.makeBuffer(length: MemoryLayout<Point>.stride, options: .storageModeShared)!
        self.publicKeyBuffer = device.makeBuffer(length: batchSize * keysPerThread * publicKeyLength, options: Helpers.getStorageModePrivate())! // needed to be public for testing  only
        
        var c = compressed
        self.compressedFlagBuffer = device.makeBuffer(bytes: &c, length: MemoryLayout<Bool>.stride, options: .storageModeShared)!
        
        
        
        let keyLimbs = Helpers.hex256ToUInt32Limbs(startKeyHex) 

        self.startKeyBuffer = device.makeBuffer(
            bytes: keyLimbs,
            length: keyLimbs.count * MemoryLayout<UInt32>.stride,
            options: .storageModeShared
        )!
    }


    public func initializeBasePoints() {
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let encoder = commandBuffer.makeComputeCommandEncoder()!
        encoder.setComputePipelineState(initPipeline)
        encoder.setBytes(&batchSizeU32, length: MemoryLayout<UInt32>.stride, index: 0)
        encoder.setBytes(&keysPerThreadU32, length: MemoryLayout<UInt32>.stride, index: 1)
        encoder.setBuffer(basePrivateKeyBuffer, offset: 0, index: 2)
        encoder.setBuffer(basePublicPointsBuffer, offset: 0, index: 3)
        encoder.setBuffer(deltaGBuffer, offset: 0, index: 4)
        encoder.setBuffer(startKeyBuffer, offset: 0, index: 5)

        encoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }


    public func appendCommandEncoder(commandBuffer: MTLCommandBuffer) {
        let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
        commandEncoder.setComputePipelineState(processPipeline)
        commandEncoder.setBuffer(basePublicPointsBuffer, offset: 0, index: 0)
        commandEncoder.setBuffer(deltaGBuffer, offset: 0, index: 1)
        commandEncoder.setBuffer(publicKeyBuffer, offset: 0, index: 2)
        commandEncoder.setBytes(&batchSizeU32, length: MemoryLayout<UInt32>.stride, index: 3)
        commandEncoder.setBytes(&keysPerThreadU32, length: MemoryLayout<UInt32>.stride, index: 4)
        commandEncoder.setBuffer(compressedFlagBuffer, offset: 0, index: 5)
        //commandEncoder.setBuffer(basePrivateKeyBuffer, offset: 0, index: 6)

        commandEncoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        commandEncoder.endEncoding()
    }

    public func getPublicKeyBuffer() -> MTLBuffer { publicKeyBuffer }
    public func getDeltaGBuffer() -> MTLBuffer { deltaGBuffer }
    public func getBasePrivateKeyBuffer() -> MTLBuffer { basePrivateKeyBuffer }
    
}
