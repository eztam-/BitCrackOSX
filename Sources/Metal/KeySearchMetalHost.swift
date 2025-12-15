import Metal
import Foundation

public class KeySearchMetalHost {
    
    
    // Metal layout mirrors (match your Metal structs exactly)
    // Metal sizes → uint256: 32, PointJacobian: 100, ThreadState: 132
    // Swift sizes → U256: 32, PointJacobian: 100, ThreadState: 132
    @frozen public struct UInt256 {
        public var limbs: (UInt32,UInt32,UInt32,UInt32,UInt32,UInt32,UInt32,UInt32)
    }
    
    @frozen public struct Point {
        public var x: UInt256
        public var y: UInt256
        public var infinity: UInt8              // Metal bool = 1 byte
        public var _pad: (UInt8, UInt8, UInt8)  // pad to 4-byte alignment
    }
    
    
    private let device: MTLDevice
    private let initPipeline: MTLComputePipelineState
    private let stepPipeline: MTLComputePipelineState

    private let compressed: Bool
    private let publicKeyLength: Int
    private let startKeyHex: String
    
    public struct PointSet {
        let totalPointsBuffer: MTLBuffer
        let gridSize: Int          // number of threads in grid (1D)
        let xBuffer: MTLBuffer
        let yBuffer: MTLBuffer
        let chainBuffer: MTLBuffer
        let deltaGXBuffer: MTLBuffer
        let deltaGYBuffer: MTLBuffer
        let lastPrivBuffer: MTLBuffer
        let gridSizeBuffer: MTLBuffer
    }
    
    public init(on device: MTLDevice, compressed: Bool, startKeyHex: String) throws {
        self.device = device
        self.compressed = compressed
        self.publicKeyLength = compressed ? 33 : 65
        self.startKeyHex = startKeyHex
        self.initPipeline = try Helpers.buildPipelineState(kernelFunctionName: "init_points")
        self.stepPipeline = try Helpers.buildPipelineState(kernelFunctionName: "step_points")
    }
    
    
    func makePointSet(totalPoints: UInt32, gridSize: Int) -> PointSet {
        // x / y arrays: one UInt256 per point
        let xBuffer = device.makeBuffer(length: Int(totalPoints) * MemoryLayout<UInt256>.stride, options: .storageModePrivate)!
        let yBuffer = device.makeBuffer(length: Int(totalPoints) * MemoryLayout<UInt256>.stride, options: .storageModePrivate)!
        
        // chain size: ceil(totalPoints / gridSize) * gridSize
        let batches = (Int(totalPoints) + gridSize - 1) / gridSize
        let chainCount = batches * gridSize
        let chainBuffer = device.makeBuffer(length: chainCount * MemoryLayout<UInt256>.stride, options: .storageModeShared)!
        
        // single Point for ΔG
        let deltaGXBuffer = device.makeBuffer(length: MemoryLayout<UInt256>.stride, options: .storageModeShared)!
        let deltaGYBuffer = device.makeBuffer(length: MemoryLayout<UInt256>.stride, options: .storageModeShared)!
        
        // 8 limbs (UInt32) for last private key
        let lastPrivBuffer = device.makeBuffer(length: 8 * MemoryLayout<UInt32>.stride, options: .storageModeShared)! // TODO: do we still need this since we calculate the priv key on CPU?
        
        var totalPointsL = totalPoints
        let totalPointsBuffer = device.makeBuffer(length: MemoryLayout<UInt32>.size, options: .storageModeShared)!
        memcpy(totalPointsBuffer.contents(), &totalPointsL, MemoryLayout<UInt32>.size)

        var gridSizeU32 = UInt32(gridSize)
        let gridSizeBuffer = device.makeBuffer(length: MemoryLayout<UInt32>.size, options: .storageModeShared)!
        memcpy(gridSizeBuffer.contents(), &gridSizeU32, MemoryLayout<UInt32>.size)

        return PointSet(
            totalPointsBuffer: totalPointsBuffer,
            gridSize: gridSize,
            xBuffer: xBuffer,
            yBuffer: yBuffer,
            chainBuffer: chainBuffer,
            deltaGXBuffer: deltaGXBuffer,
            deltaGYBuffer: deltaGYBuffer,
            lastPrivBuffer: lastPrivBuffer,
            gridSizeBuffer: gridSizeBuffer
        )
    }
    
    
    /// Initialize the points with a starting private key and compute ΔG.
    ///
    /// `startKeyLE` must be 8×UInt32 in little-endian limb order as expected
    /// by your Metal `field_add` / scalar arithmetic.
    func runInitKernel(pointSet: PointSet, startKeyLE: [UInt32], commandBuffer: MTLCommandBuffer) throws {
        
        precondition(startKeyLE.count == 8)
        
        // Start key buffer (8 limbs)
        let startKeyBuffer = device.makeBuffer(length: 8 * MemoryLayout<UInt32>.stride, options: .storageModeShared)!
        startKeyBuffer.contents().copyMemory(from: startKeyLE, byteCount: 8 * MemoryLayout<UInt32>.stride)
        
        let encoder = commandBuffer.makeComputeCommandEncoder()!
        
        encoder.setComputePipelineState(initPipeline)
        encoder.setBuffer(pointSet.totalPointsBuffer, offset: 0, index: 0)
        encoder.setBuffer(startKeyBuffer, offset: 0, index: 1)
        encoder.setBuffer(pointSet.xBuffer, offset: 0, index: 2)
        encoder.setBuffer(pointSet.yBuffer, offset: 0, index: 3)
        encoder.setBuffer(pointSet.deltaGXBuffer, offset: 0, index: 4)
        encoder.setBuffer(pointSet.deltaGYBuffer, offset: 0, index: 5)
        encoder.setBuffer(pointSet.lastPrivBuffer, offset: 0, index: 6)
        
        // Launch with `gridSize` threads (1D)
        let gridSize = pointSet.gridSize
        let threadsPerThreadgroup = min(initPipeline.maxTotalThreadsPerThreadgroup, gridSize)
        let tgSize = MTLSize(width: threadsPerThreadgroup, height: 1, depth: 1)
        let grid = MTLSize(width: gridSize, height: 1, depth: 1)
        
        encoder.dispatchThreads(grid, threadsPerThreadgroup: tgSize)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
    
    
    /// Read last private key (optional, for bookkeeping)
    func readLastPrivateKey(from pointSet: PointSet) -> [UInt32] {
        let ptr = pointSet.lastPrivBuffer.contents()
        let buffer = ptr.bindMemory(to: UInt32.self, capacity: 8)
        return (0..<8).map { buffer[$0] }
    }
    

    
    /// Perform one  step: Q[i] += ΔG for all points.
    func appendStepKernel(pointSet: PointSet, commandBuffer: MTLCommandBuffer, bloomFilter: BloomFilter, bloomFilterHitsBuffer: MTLBuffer, hitCountBuffer: MTLBuffer) throws {
        let encoder = commandBuffer.makeComputeCommandEncoder()!
        
        encoder.setComputePipelineState(stepPipeline)
        
        encoder.setBuffer(pointSet.totalPointsBuffer, offset: 0, index: 0)
        encoder.setBuffer(pointSet.gridSizeBuffer, offset: 0, index: 1)
        encoder.setBuffer(pointSet.chainBuffer, offset: 0, index: 2)
        encoder.setBuffer(pointSet.xBuffer, offset: 0, index: 3)
        encoder.setBuffer(pointSet.yBuffer, offset: 0, index: 4)
        encoder.setBuffer(pointSet.deltaGXBuffer, offset: 0, index: 5)
        encoder.setBuffer(pointSet.deltaGYBuffer, offset: 0, index: 6)
        encoder.setBuffer(bloomFilter.getBitsBuffer(),  offset: 0, index: 7)
        encoder.setBuffer(bloomFilter.getMbitsBuffer(), offset: 0, index: 8)
        encoder.setBuffer(hitCountBuffer, offset: 0, index: 9)
        encoder.setBuffer(bloomFilterHitsBuffer,    offset: 0, index: 10)
        //var compression: UInt32 = Properties.compressedKeySearch ? 1 : 0
        //encoder.setBytes(&compression, length: MemoryLayout<UInt32>.stride, index: 11)

        // Dispatch exactly gridSize threads (as the kernel expects)
        let gridSize = pointSet.gridSize
        let threadsPerThreadgroup = min(stepPipeline.maxTotalThreadsPerThreadgroup,
                                        gridSize)
        let tgSize = MTLSize(width: threadsPerThreadgroup, height: 1, depth: 1)
        let grid = MTLSize(width: gridSize, height: 1, depth: 1)
        
        encoder.dispatchThreads(grid, threadsPerThreadgroup: tgSize)
        encoder.endEncoding()

    }
    

}


