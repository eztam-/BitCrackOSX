import Foundation
import Metal


// TODO: Externalize the DB related stuff it doesn't belog here
// TODO: Create two separate constuctors, one for query the other for insert?
public class BloomFilter {
    
    private let device: MTLDevice
    private let batchSize: Int
    
  
    // Bloom Filter configuration TODO: cleanup
    private var countU: UInt32
    private var mBits: UInt32
    private var kHashes: UInt32
    
    private let bitsBuffer: MTLBuffer
    private let bitCount: Int
    private let hashCount: Int
    private let itemLengthBytes: Int
    
    
    // Insert
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
        try self.init(expectedInsertions: cnt, falsePositiveRate:0.000001, batchSize: batchSize)
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
    
    public init(expectedInsertions: Int, falsePositiveRate: Double = 0.0001, batchSize: Int) throws {
        self.batchSize = batchSize
        self.device = Helpers.getSharedDevice()

      //  self.itemU32Length = 20 / 4
        self.itemLengthBytes = 20
        
        // This is a very dirty fix, for the issue, that the bloomfilter causes too many false positifes, but only for small datasets
        var numInsertions = expectedInsertions < 100000 ? expectedInsertions * 10 : expectedInsertions
        numInsertions = expectedInsertions < 1000 ? expectedInsertions * 100 : numInsertions
        numInsertions = expectedInsertions < 100 ? expectedInsertions * 1000 : numInsertions
        
        // Match Swift implementation exactly
        let m = ceil(-(Double(numInsertions) * log(falsePositiveRate)) / pow(log(2.0), 2.0))
        let k = max(1, Int(round((m / Double(numInsertions)) * log(2.0))))
        
        
        if Int(m) > UInt32.max {
            bitCount = Int(UInt32.max)
            print("❌  WARNING! Bloom filter size exceeds maximum.")
            //print("⚠️  WARNING! Bloom filter size exceeds maximum. Clamped bit count to UInt32.max. This might cause an exessive rate in false positives.")
            throw BloomFilterError.bitSizeExceededMax
        } else{
            self.bitCount = Int(m)
        }
        
        
        self.hashCount = k
        
        let wordCount = (bitCount + 31) / 32
        let bufferSize = wordCount * MemoryLayout<UInt32>.stride
        
       
        print("    Expected insertions: \(numInsertions)")
        print("    Bit count: \(bitCount) bits (\(bufferSize / 1024) KB)")
        print("    Hash functions: \(hashCount)")
        print("    Target FPR: \(falsePositiveRate)")
        
        let bits = device.makeBuffer(length: bufferSize, options: .storageModeShared)!
        memset(bits.contents(), 0, bufferSize)
        self.bitsBuffer = bits
        
       // self.itemLenU = UInt32(itemU32Length)
        self.mBits = UInt32(bitCount)
        self.kHashes = UInt32(hashCount)
        
        
        
        // Intitialization for insert
        insertItemsBuffer = device.makeBuffer(length: bufferSize, options: .storageModeShared)!
        self.insertPipeline = try Helpers.buildPipelineState(kernelFunctionName: "bloom_insert")
        (self.insert_threadsPerThreadgroup,  self.insert_threadgroupsPerGrid) = try Helpers.getThreadConfig(
            pipelineState: insertPipeline,
            batchSize: batchSize,
            threadsPerThreadgroupMultiplier: 16)
        
        
        // Intitialization for query
        self.countU = UInt32(batchSize)
       
        
    }
    
    public func insert(_ items: [Data]) throws {
        guard !items.isEmpty else { return }
        let count = items.count
        let itemBytes = 20
       
        let ptr = insertItemsBuffer.contents().assumingMemoryBound(to: UInt8.self)
        for (i, item) in items.enumerated() {
            let offset = i * itemBytes
            let copyCount = min(item.count, itemBytes)
            item.copyBytes(to: ptr.advanced(by: offset), count: copyCount)
            if copyCount < itemBytes {
                memset(ptr.advanced(by: offset + copyCount), 0, itemBytes - copyCount)
            }
        }
        
        let insertCommandQueue = device.makeCommandQueue()!
        let cmdBuffer = insertCommandQueue.makeCommandBuffer()!
        let encoder = cmdBuffer.makeComputeCommandEncoder()!
        var countU = UInt32(count)
      
        
        encoder.setComputePipelineState(insertPipeline)
        encoder.setBuffer(insertItemsBuffer, offset: 0, index: 0)
        encoder.setBytes(&countU, length: 4, index: 1)
        encoder.setBuffer(bitsBuffer, offset: 0, index: 2)
        encoder.setBytes(&mBits, length: 4, index: 3)
        encoder.setBytes(&kHashes, length: 4, index: 4)
        
       
        encoder.dispatchThreadgroups(insert_threadgroupsPerGrid, threadsPerThreadgroup: insert_threadsPerThreadgroup)
        // Alternatively let Metal find the best number of thread groups
        //encoder.dispatchThreads(MTLSize(width: batchSize, height: 1, depth: 1), threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
        
        cmdBuffer.commit()
        cmdBuffer.waitUntilCompleted()
        
        
    }
        
    
    public func getBitsBuffer() -> MTLBuffer {
            return bitsBuffer
    }
    
    public func getMbits() -> UInt32 {
            return mBits
    }
    
    
    public func getKhashes() -> UInt32 {
            return kHashes
    }
    
    
    

}
