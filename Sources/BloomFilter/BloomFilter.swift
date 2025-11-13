import Foundation
import Metal

public class BloomFilter {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let insertPipeline: MTLComputePipelineState
    private let queryPipeline: MTLComputePipelineState
    
    private let bitsBuffer: MTLBuffer
    private let bitCount: Int
    private let hashCount: Int
    private let itemU32Length: Int
    
    private var itemsBuffer: MTLBuffer?
    private var resultsBuffer: MTLBuffer?
    let  itemLengthBytes: Int
    
    enum BloomFilterError: Error {
        case initializationFailed
        case bitSizeExceededMax
    }
    
    public convenience init(db: DB) throws {
        print("──────────────────────────────────────────────────")
        print("🚀 Initializing Bloom Filter")
        
        let cnt = try db.getAddressCount()
        if cnt == 0 {
            print("❌ No records found in the database. Please load some addresses first.")
            exit(1)
        }
        try self.init(expectedInsertions: cnt, itemBytes: 20, falsePositiveRate:0.000001)
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
    
    public init(expectedInsertions: Int, itemBytes: Int, falsePositiveRate: Double = 0.0001) throws {
        
        guard itemBytes % 4 == 0 else {
            print("❌ itemBytes must be multiple of 4 for UInt32 alignment")
            throw BloomFilterError.initializationFailed
        }
        
        guard let dev = MTLCreateSystemDefaultDevice(),
              let queue = dev.makeCommandQueue() else {
            print("❌ Failed to create Metal device/queue")
            throw BloomFilterError.initializationFailed
        }
        
        self.device = dev
        self.commandQueue = queue
        self.itemU32Length = itemBytes / 4
        self.itemLengthBytes = itemBytes
        
        // This is a dirty fix, for the issue, that the bloomfilter causes too many false positifes, but only for small datasets
        let numInsertions = expectedInsertions < 100000 ? expectedInsertions * 2 : expectedInsertions
        
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
        
        guard let bits = dev.makeBuffer(length: bufferSize, options: .storageModeShared) else {
            print("Failed to allocate bits buffer")
            throw BloomFilterError.initializationFailed
        }
        memset(bits.contents(), 0, bufferSize)
        self.bitsBuffer = bits
        
        do {
            let library: MTLLibrary! = try? device.makeDefaultLibrary(bundle: Bundle.module)
            
            guard let insertFunc = library.makeFunction(name: "bloom_insert"),
                  let queryFunc = library.makeFunction(name: "bloom_query") else {
                print("Failed to create Metal functions")
                throw BloomFilterError.initializationFailed
            }
            
            self.insertPipeline = try dev.makeComputePipelineState(function: insertFunc)
            self.queryPipeline = try dev.makeComputePipelineState(function: queryFunc)
            
        } catch {
            print("Failed to compile shaders: \(error)")
            throw BloomFilterError.initializationFailed
        }
    }
    
    public func insert(_ items: [Data]) throws {
        guard !items.isEmpty else { return }
        let count = items.count
        let itemBytes = itemU32Length * 4
        let bufferSize = count * itemBytes
        
        if itemsBuffer == nil || itemsBuffer!.length < bufferSize {
            itemsBuffer = device.makeBuffer(length: bufferSize, options: .storageModeShared)
        }
        let ptr = itemsBuffer!.contents().assumingMemoryBound(to: UInt8.self)
        for (i, item) in items.enumerated() {
            let offset = i * itemBytes
            let copyCount = min(item.count, itemBytes)
            item.copyBytes(to: ptr.advanced(by: offset), count: copyCount)
            if copyCount < itemBytes {
                memset(ptr.advanced(by: offset + copyCount), 0, itemBytes - copyCount)
            }
        }
        
        guard let cmdBuffer = commandQueue.makeCommandBuffer(),
              let encoder = cmdBuffer.makeComputeCommandEncoder() else { return }
        var countU = UInt32(count)
        var itemLenU = UInt32(itemU32Length)
        var mBits = UInt32(bitCount)
        var kHashes = UInt32(hashCount)
        
        encoder.setComputePipelineState(insertPipeline)
        encoder.setBuffer(itemsBuffer, offset: 0, index: 0)
        encoder.setBytes(&countU, length: 4, index: 1)
        encoder.setBytes(&itemLenU, length: 4, index: 2)
        encoder.setBuffer(bitsBuffer, offset: 0, index: 3)
        encoder.setBytes(&mBits, length: 4, index: 4)
        encoder.setBytes(&kHashes, length: 4, index: 5)
        
        let w = insertPipeline.threadExecutionWidth
        let threadsPerGroup = MTLSize(width: min(256, w), height: 1, depth: 1)
        let threadgroups = MTLSize(width: (count + threadsPerGroup.width - 1) / threadsPerGroup.width, height: 1, depth: 1)
        encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
        
        cmdBuffer.commit()
        cmdBuffer.waitUntilCompleted()
        
        
    }
    
    public func query(_ itemsBuffer: MTLBuffer, batchSize: Int) -> [Bool] {
        
        
        
        let resultsBufferSize = batchSize * MemoryLayout<UInt32>.stride // TODO why uint? it is bool??? FIXME
        
        
        if resultsBuffer == nil || resultsBuffer!.length < resultsBufferSize {
            resultsBuffer = device.makeBuffer(length: resultsBufferSize, options: .storageModeShared)
        }
        
        
        
        guard let cmdBuffer = commandQueue.makeCommandBuffer(),
              let encoder = cmdBuffer.makeComputeCommandEncoder() else { return [] }
        
        var countU = UInt32(batchSize)
        var itemLenU = UInt32(itemU32Length)
        var mBits = UInt32(bitCount)
        var kHashes = UInt32(hashCount)
        
        encoder.setComputePipelineState(queryPipeline)
        encoder.setBuffer(itemsBuffer, offset: 0, index: 0)
        encoder.setBytes(&countU, length: 4, index: 1)
        encoder.setBytes(&itemLenU, length: 4, index: 2)
        encoder.setBuffer(bitsBuffer, offset: 0, index: 3)
        encoder.setBytes(&mBits, length: 4, index: 4)
        encoder.setBytes(&kHashes, length: 4, index: 5)
        encoder.setBuffer(resultsBuffer, offset: 0, index: 6)
        
        let w = queryPipeline.threadExecutionWidth
        let threadsPerGroup = MTLSize(width: min(256, w), height: 1, depth: 1)
        let threadgroups = MTLSize(width: (batchSize + threadsPerGroup.width - 1) / threadsPerGroup.width, height: 1, depth: 1)
        encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
        
        cmdBuffer.commit()
        cmdBuffer.waitUntilCompleted()
        
        let resultsPtr = resultsBuffer!.contents().bindMemory(to: UInt32.self, capacity: batchSize)
        return (0..<batchSize).map { resultsPtr[$0] != 0 }
    }
}
