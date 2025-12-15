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
    private let insert_threadsPerThreadgroup: MTLSize
    private let insert_threadgroupsPerGrid: MTLSize
    private var insertItemsBuffer: MTLBuffer
    
    enum BloomFilterError: Error {
        case initializationFailed
        case bitSizeExceededMax
    }
    
    public convenience init(db: DB, batchSize: Int) throws {
        print("──────────────────────────────────────────────────")
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
        print("\n✅ Bloom filter initialized with \(cnt) addresses. Took \(Int(endTime-startTime)) seconds.")
        
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

        print("BloomFilter")
        print("  insertions: \(expectedInsertions)")
        print("  bitCount:   \(bitCount) bits  (\(bufferSize / 1024) KB)")
        print("  mask:       0x\(String(self.mBits, radix:16))")

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

        // ------------------------------
        // Build compute pipeline
        // ------------------------------
        self.insertPipeline = try Helpers.buildPipelineState(kernelFunctionName: "bloom_insert")

        (self.insert_threadsPerThreadgroup,
         self.insert_threadgroupsPerGrid) = try Helpers.getThreadConfig(
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

        var countU = UInt32(items.count)

        encoder.setComputePipelineState(insertPipeline)
        encoder.setBuffer(insertItemsBuffer, offset: 0, index: 0) // 20-byte inputs
        encoder.setBytes(&countU, length: 4, index: 1)
        encoder.setBuffer(bitsBuffer, offset: 0, index: 2)
        encoder.setBytes(&mBits, length: 4, index: 3)              // mask

        encoder.dispatchThreadgroups(insert_threadgroupsPerGrid,
                                     threadsPerThreadgroup: insert_threadsPerThreadgroup)
        encoder.endEncoding()
        cmdBuffer.commit()
    }

    
    private static func nextPowerOfTwo(_ n: Int) -> Int {
        var v = 1
        while v < n { v <<= 1 }
        return v
    }

    
        
    public func getBitsBuffer() -> MTLBuffer {
            return bitsBuffer
    }
    
    public func getMbits() -> UInt32 {
            return mBits
    }
    
}
