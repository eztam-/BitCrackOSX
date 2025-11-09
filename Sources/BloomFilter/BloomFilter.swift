import Foundation
import Metal

final class BloomFilter {
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
    }
    
    public convenience init(db: DB) throws{
        
        let cnt = try db.getAddressCount()

        try self.init(expectedInsertions: cnt*100, itemBytes: 20) // TODO: *100 seems to be working well, but this should actuylly be solved by the falsPositiveRate
       
        var batch: [Data] = []
        for row in try db.getAllAddresses() {
            batch.append(Data(hex: row.publicKeyHash)!)
        }
        self.insert(batch)
        print("✅ Bloom filter initialized with \(cnt) addresses from database")

    }
    
    private init(expectedInsertions: Int, itemBytes: Int, falsePositiveRate: Double = 0.001) throws {
        
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
        
        // Match Swift implementation exactly
        let m = ceil(-(Double(expectedInsertions) * log(falsePositiveRate)) / pow(log(2.0), 2.0))
        let k = max(1, Int(round((m / Double(expectedInsertions)) * log(2.0))))
        
        self.bitCount = Int(m)
        self.hashCount = k
        
        let wordCount = (bitCount + 31) / 32
        let bufferSize = wordCount * MemoryLayout<UInt32>.stride
        
        print("📊 Metal Bloom Filter Configuration:")
        print("   Expected insertions: \(expectedInsertions)")
        print("   Bit count: \(bitCount) bits (\(bufferSize / 1024) KB)")
        print("   Hash functions: \(hashCount)")
        print("   Target FPR: \(falsePositiveRate)")
        
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
    
    func insert(_ items: [Data]) {
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
    
    func query(_ itemsBuffer: MTLBuffer, batchSize: Int) -> [Bool] {
        
        
            
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

// ==================== COMPARISON TEST ====================
/*
func bloomTest() {
    print("🔬 Comparing Swift vs Metal Bloom Filter\n")
    
    let capacity = 100_000
    let fpr = 0.0001
    let itemBytes = 20
    
    // Create both filters
    let swiftFilter = BloomFilter2(capacity: capacity, falsePositiveRate: fpr)
    guard let metalFilter = BloomFilter(
        expectedInsertions: capacity,
        itemBytes: itemBytes,
        falsePositiveRate: fpr
    ) else {
        print("Failed to create Metal filter")
        return
    }
    
    print("\n📝 Inserting \(capacity) items into both filters...")
    
    // Generate test data
    var testItems: [Data] = []
    for _ in 0..<capacity {
        let data = Data((0..<itemBytes).map { _ in UInt8.random(in: 0...255) })
        testItems.append(data)
    }
    
    // Insert into both
    for item in testItems {
        swiftFilter.insert(data: item)
    }
    metalFilter.insert(testItems)
    
    print("✅ Insertion complete\n")
    
    // Test positive queries
    print("🔍 Testing inserted items (should all return true)...")
    let metalPositive = metalFilter.query(testItems)
    var swiftPositive = 0
    for item in testItems {
        if swiftFilter.contains(pointer: item.withUnsafeBytes { $0.bindMemory(to: UInt32.self).baseAddress! },
                               length: itemBytes / 4) {
            swiftPositive += 1
        }
    }
    
    print("   Swift: \(swiftPositive)/\(capacity) true")
    print("   Metal: \(metalPositive.filter { $0 }.count)/\(capacity) true\n")
    
    // Test false positives
    print("🎯 Testing false positive rate with 10K random items...")
    var negativeItems: [Data] = []
    for _ in 0..<10_000 {
        let data = Data((0..<itemBytes).map { _ in UInt8.random(in: 0...255) })
        negativeItems.append(data)
    }
    
    let metalNegative = metalFilter.query(negativeItems)
    var swiftFP = 0
    for item in negativeItems {
        if swiftFilter.contains(pointer: item.withUnsafeBytes { $0.bindMemory(to: UInt32.self).baseAddress! },
                               length: itemBytes / 4) {
            swiftFP += 1
        }
    }
    let metalFP = metalNegative.filter { $0 }.count
    
    print("   Swift FPR: \(String(format: "%.4f%%", Double(swiftFP) / 100.0))")
    print("   Metal FPR: \(String(format: "%.4f%%", Double(metalFP) / 100.0))")
    print("   Expected:  \(String(format: "%.4f%%", fpr * 100))")
}

// Run comparison

*/
