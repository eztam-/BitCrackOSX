import Foundation
import Metal

// TODO: Externalize the DB related stuff it doesn't belog here
// TODO: Create two separate constuctors, one for query the other for insert?
public class BloomFilter {
    
    private let device: MTLDevice
    private let batchSize: Int
    private var mBits: UInt32
    private let bitsBuffer: MTLBuffer
    private let bitCount: Int
    
    private let insertPipeline: MTLComputePipelineState
    private let threadsPerThreadgroup: MTLSize
    private let threadgroupsPerGrid: MTLSize
    private var insertItemsBuffer: MTLBuffer
    private var countBuffer: MTLBuffer
    private var mBitsBuffer: MTLBuffer
    
    enum BloomFilterError: Error {
        case initializationFailed
        case bitSizeExceededMax
    }
    
    public convenience init(db: DB, batchSize: Int) throws {
        
        print("🚀 Initializing Bloom Filter")
        
        let cnt = try db.getAddressCount()
        if cnt == 0 {
            print("❌ No records found in the database. Please load some addresses first.")
            exit(1)
        }
        try self.init(expectedInsertions: cnt, batchSize: batchSize)
        print("\n🌀 Start loading \(cnt) public key hashes from database into the bloom filter.")
        let startTime = CFAbsoluteTimeGetCurrent()
        
        var batch = [Data]()
        let batchSize = 50_000
        let rows = try db.getAllAddresses() // keeping this outside of the loop iterates only over the cursers instead of loading all into the memory?
        for row in rows {
            batch.append(Data(hex: row.publicKeyHash)!)
            if batch.count >= batchSize {
                try self.insert(batch)
                batch.removeAll(keepingCapacity: true)
            }
        }
        if !batch.isEmpty {
            try self.insert(batch)
        }
        let endTime = CFAbsoluteTimeGetCurrent()
        print("   → Initialization with \(cnt) addresses. Took \(Int(endTime-startTime)) seconds.")
        
    }
    
    public init(expectedInsertions: Int, batchSize: Int) throws {
        self.batchSize = batchSize
        self.device = Helpers.getSharedDevice()
        
        // ------------------------------
        // bloom sizing
        // ------------------------------
        let approxBits = expectedInsertions * 32
        let bitCount = BloomFilter.nextPowerOfTwo(approxBits)        // MUST be power-of-two
        self.bitCount = bitCount
        self.mBits = UInt32(bitCount - 1)                // mask = bitCount - 1
        
        let wordCount = bitCount / 32
        let bufferSize = wordCount * MemoryLayout<UInt32>.stride
        
        print("   ▢▢▣▢▣▢▢")
        print("    Insertions  :  \(expectedInsertions)")
        print("    BitCount    :  \(bitCount) bits  (\(bufferSize / 1024) KB)")
        print("    Mask        :  0x\(String(self.mBits, radix:16))")
        
        // ------------------------------
        // Allocate bloom bit array
        // ------------------------------
        let bits = device.makeBuffer(length: bufferSize,
                                     options: .storageModeShared)!
        memset(bits.contents(), 0, bufferSize)
        self.bitsBuffer = bits
        
        // ------------------------------
        // Buffer for items to insert
        // ------------------------------
        self.insertItemsBuffer = device.makeBuffer(length: expectedInsertions * 20,
                                                   options: .storageModeShared)!
        
        self.countBuffer = device.makeBuffer(length: MemoryLayout<UInt32>.size, options: .storageModeShared)!
        
        self.mBitsBuffer = device.makeBuffer(length: MemoryLayout<UInt32>.size, options: .storageModeShared)!
        memcpy(mBitsBuffer.contents(), &mBits, MemoryLayout<UInt32>.size)
        
        // ------------------------------
        // Build compute pipeline
        // ------------------------------
        self.insertPipeline = try Helpers.buildPipelineState(kernelFunctionName: "bloom_insert")
        
        (self.threadsPerThreadgroup,
         self.threadgroupsPerGrid) = try Helpers.getThreadConfig(
            pipelineState: insertPipeline,
            batchSize: batchSize,
            threadsPerThreadgroupMultiplier: 16
         )
    }
    
    
    public func insert(_ items: [Data]) throws {
        guard !items.isEmpty else { return }
        
        // ---------------------------------------
        // Upload items (20-byte hash160 each)
        // ---------------------------------------
        let ptr = insertItemsBuffer.contents().assumingMemoryBound(to: UInt8.self)
        
        for (i, item) in items.enumerated() {
            let offset = i * 20
            let copyCount = min(item.count, 20)
            item.copyBytes(to: ptr.advanced(by: offset), count: copyCount)
            if copyCount < 20 {
                memset(ptr.advanced(by: offset + copyCount), 0, 20 - copyCount)
            }
        }
        
        // ---------------------------------------
        // Dispatch bloom_insert kernel
        // ---------------------------------------
        let queue = device.makeCommandQueue()!
        let cmdBuffer = queue.makeCommandBuffer()!
        let encoder = cmdBuffer.makeComputeCommandEncoder()!
        
        encoder.setComputePipelineState(insertPipeline)
        encoder.setBuffer(insertItemsBuffer, offset: 0, index: 0) // 20-byte inputs
        
        var countU = UInt32(items.count)
        memcpy(countBuffer.contents(), &countU, MemoryLayout<UInt32>.size)
        encoder.setBuffer(countBuffer, offset: 0, index: 1)
        
        encoder.setBuffer(bitsBuffer, offset: 0, index: 2)
        
        // mask
        encoder.setBuffer(mBitsBuffer, offset: 0, index: 3)
        
        encoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
        cmdBuffer.commit()
        cmdBuffer.waitUntilCompleted() // We need to wait here otherwise the bf initialization will overlapp the key search which causes unpredictable side effects because insert+query isn't thread safe
    }
    
    
    private static func nextPowerOfTwo(_ n: Int) -> Int {
        var v = 1
        while v < n { v <<= 1 }
        return v
    }
    
    
    
    public func getBitsBuffer() -> MTLBuffer {
        return bitsBuffer
    }
    
    public func getMbitsBuffer() -> MTLBuffer {
        return mBitsBuffer
    }
    
}
