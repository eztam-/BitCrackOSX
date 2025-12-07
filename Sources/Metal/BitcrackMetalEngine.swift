import Metal
import Foundation

public class BitcrackMetalEngine {
    
    
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
   // private let hashPipeline: MTLComputePipelineState
    
  //  private var batchSizeU32: UInt32
    //private let keysPerThread: Int
   // private var keysPerThreadU32: UInt32
    
    
    private let compressed: Bool
    private let publicKeyLength: Int
    
    
    private let startKeyHex: String
    
    public struct PointSet {
        let totalPoints: UInt32
        let gridSize: Int          // number of threads in grid (1D)
        let xBuffer: MTLBuffer
        let yBuffer: MTLBuffer
        let chainBuffer: MTLBuffer
        let deltaGBuffer: MTLBuffer
        let lastPrivBuffer: MTLBuffer
    }
    
    public init(on device: MTLDevice, compressed: Bool, startKeyHex: String) throws {
        self.device = device
    //    self.keysPerThread = keysPerThread
        self.compressed = compressed
        self.publicKeyLength = compressed ? 33 : 65
        self.startKeyHex = startKeyHex
        //self.batchSizeU32 = UInt32(batchSize)
   //     self.keysPerThreadU32 = UInt32(keysPerThread)
        
        self.initPipeline = try Helpers.buildPipelineState(kernelFunctionName: "init_points_bitcrack_style")
        self.stepPipeline = try Helpers.buildPipelineState(kernelFunctionName: "step_points_bitcrack_style")
        //self.hashPipeline = try Helpers.buildPipelineState(kernelFunctionName: "sha256_ripemd160_bloom_query_kernel")
        
    

    }
    
    
    func makePointSet(totalPoints: UInt32,
                      gridSize: Int) -> PointSet {
        // x / y arrays: one UInt256 per point
        let xBuffer = device.makeBuffer(length: Int(totalPoints) * MemoryLayout<UInt256>.stride,
                                        options: .storageModeShared)!
        let yBuffer = device.makeBuffer(length: Int(totalPoints) * MemoryLayout<UInt256>.stride,
                                        options: .storageModeShared)!
        
        // chain size: ceil(totalPoints / gridSize) * gridSize
        let batches = (Int(totalPoints) + gridSize - 1) / gridSize
        let chainCount = batches * gridSize
        let chainBuffer = device.makeBuffer(length: chainCount * MemoryLayout<UInt256>.stride,
                                            options: .storageModeShared)!
        
        // single Point for ΔG
        let deltaGBuffer = device.makeBuffer(length: MemoryLayout<Point>.stride,
                                             options: .storageModeShared)!
        
        // 8 limbs (UInt32) for last private key
        let lastPrivBuffer = device.makeBuffer(length: 8 * MemoryLayout<UInt32>.stride,
                                               options: .storageModeShared)!
        
        return PointSet(
            totalPoints: totalPoints,
            gridSize: gridSize,
            xBuffer: xBuffer,
            yBuffer: yBuffer,
            chainBuffer: chainBuffer,
            deltaGBuffer: deltaGBuffer,
            lastPrivBuffer: lastPrivBuffer
        )
    }
    
    
    /// Initialize the points with a starting private key and compute ΔG.
    ///
    /// `startKeyLE` must be 8×UInt32 in little-endian limb order as expected
    /// by your Metal `field_add` / scalar arithmetic.
    func runInitKernel(pointSet: PointSet,
                       startKeyLE: [UInt32], commandBuffer: MTLCommandBuffer) throws {
        precondition(startKeyLE.count == 8)
        
        var totalPoints = pointSet.totalPoints
        
        // Start key buffer (8 limbs)
        let startKeyBuffer = device.makeBuffer(length: 8 * MemoryLayout<UInt32>.stride,
                                               options: .storageModeShared)!
        startKeyBuffer.contents()
            .copyMemory(from: startKeyLE,
                        byteCount: 8 * MemoryLayout<UInt32>.stride)
        
        
        let encoder = commandBuffer.makeComputeCommandEncoder()!
        
        encoder.setComputePipelineState(initPipeline)
        
        // buffer(0): totalPoints (by value)
        encoder.setBytes(&totalPoints,
                         length: MemoryLayout<UInt32>.stride,
                         index: 0)
        
        // buffer(1): start_key_limbs
        encoder.setBuffer(startKeyBuffer, offset: 0, index: 1)
        
        // buffer(2): xPtr
        encoder.setBuffer(pointSet.xBuffer, offset: 0, index: 2)
        
        // buffer(3): yPtr
        encoder.setBuffer(pointSet.yBuffer, offset: 0, index: 3)
        
        // buffer(4): deltaG_out
        encoder.setBuffer(pointSet.deltaGBuffer, offset: 0, index: 4)
        
        // buffer(5): last_private_key (8 × uint)
        encoder.setBuffer(pointSet.lastPrivBuffer, offset: 0, index: 5)
        
        // Launch with `gridSize` threads (1D)
        let gridSize = pointSet.gridSize
        let threadsPerThreadgroup = min(initPipeline.maxTotalThreadsPerThreadgroup,
                                        gridSize)
        let tgSize = MTLSize(width: threadsPerThreadgroup, height: 1, depth: 1)
        let grid = MTLSize(width: gridSize, height: 1, depth: 1)
        
        encoder.dispatchThreads(grid, threadsPerThreadgroup: tgSize)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
    
    /// Read ΔG (increment point) after init.
    func readDeltaG(from pointSet: PointSet) -> Point {
        let ptr = pointSet.deltaGBuffer.contents()
        return ptr.load(as: Point.self)
    }
    
    /// Read last private key (optional, for bookkeeping)
    func readLastPrivateKey(from pointSet: PointSet) -> [UInt32] {
        let ptr = pointSet.lastPrivBuffer.contents()
        let buffer = ptr.bindMemory(to: UInt32.self, capacity: 8)
        return (0..<8).map { buffer[$0] }
    }
    
    
    
    /// Perform one BitCrack-style step: Q[i] += ΔG for all points.
    func appendStepKernel(pointSet: PointSet, commandBuffer: MTLCommandBuffer, bloomFilter: BloomFilter, bloomFilterResultBuffer: MTLBuffer, hash160OutBuffer: MTLBuffer) throws {
        var totalPoints = pointSet.totalPoints
        var gridSizeU32 = UInt32(pointSet.gridSize)
        
        // Read ΔG from init kernel
        var deltaG = readDeltaG(from: pointSet)
        var incX = deltaG.x
        var incY = deltaG.y
        
        
        let encoder = commandBuffer.makeComputeCommandEncoder()!
        
        encoder.setComputePipelineState(stepPipeline)
        
        // buffer(0): totalPoints
        encoder.setBytes(&totalPoints, length: MemoryLayout<UInt32>.stride, index: 0)
        
        // buffer(1): gridSize
        encoder.setBytes(&gridSizeU32, length: MemoryLayout<UInt32>.stride, index: 1)
        
        // buffer(2): chain
        encoder.setBuffer(pointSet.chainBuffer, offset: 0, index: 2)
        
        // buffer(3): xPtr
        encoder.setBuffer(pointSet.xBuffer, offset: 0, index: 3)
        
        // buffer(4): yPtr
        encoder.setBuffer(pointSet.yBuffer, offset: 0, index: 4)
        
        // buffer(5): incX (uint256)
        encoder.setBytes(&incX, length: MemoryLayout<UInt256>.stride, index: 5)
        
        // buffer(6): incY (uint256)
        encoder.setBytes(&incY, length: MemoryLayout<UInt256>.stride, index: 6)
        
        
        
        // new:
        encoder.setBuffer(bloomFilter.getBitsBuffer(),  offset: 0, index: 7)
        var mBits = bloomFilter.getMbits()
        encoder.setBytes(&mBits,            length: MemoryLayout<UInt32>.stride, index: 8)
        encoder.setBuffer(bloomFilterResultBuffer, offset: 0, index: 9)
        encoder.setBuffer(hash160OutBuffer,    offset: 0, index: 10)
        var compression: UInt32 = Properties.compressedKeySearch ? 1 : 0
        encoder.setBytes(&compression, length: MemoryLayout<UInt32>.stride, index: 11)

        

        
        
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


