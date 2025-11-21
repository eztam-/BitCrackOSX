import keysearch
import Foundation
import Testing
import Metal

class BloomFilterTest : TestBase {
    
    
    init() {
        super.init(kernelFunctionName: "bloom_query")
    }
    
    /*
    @Test func bloomTest() {
        print("🔬 Comparing Swift vs Metal Bloom Filter\n")
        
        let capacity = 32*1024
        let fpr = 0.0001
        let itemBytes = 20
        
        let metalFilter = try! BloomFilter(
            expectedInsertions: capacity,
            falsePositiveRate: fpr,
            batchSize: capacity
        )
        
        print("\n📝 Inserting \(capacity) items into bloom filter...")
        
        // Generate test data
        var testItems: [Data] = []
        var testItems2: Data = Data()
        for _ in 0..<capacity {
            let data = Data((0..<itemBytes).map { _ in UInt8.random(in: 0...255) })
            testItems.append(data)
            testItems2.append(data)
        }
        try! metalFilter.insert(testItems)
        print("✅ Insertion complete\n")
        
        // Test positive queries
        print("🔍 Testing inserted items (should all return true)...")
        
        // Create MTLBuffer from the flattened array
        let testItemsBuffer = device.makeBuffer(bytes: testItems2.bytes,
                                                length: testItems.count * 32 * MemoryLayout<UInt8>.stride,
                                                options: .storageModeShared)!
        
        let metalResult = metalFilter.query(testItemsBuffer, batchSize: testItems.count)
        var positiveCount = 0
        for p in metalResult{
            if p {
                positiveCount+=1
            }
        }
        print("Positive results: \(positiveCount) of \(capacity) inserted items\n")
        assert(positiveCount == capacity)
        
        // Test false positives
        print("🎯 Testing false positive rate with 10K random items...")
        var negativeItems: [Data] = []
        var negativeItems2: Data = Data()
        for _ in 0..<10_000 {
            let data = Data((0..<itemBytes).map { _ in UInt8.random(in: 0...255) })
            negativeItems.append(data)
            negativeItems2.append(data)
        }
        
        
        // Create MTLBuffer from the flattened array
        let negativeItemsBuffer = device.makeBuffer(bytes: negativeItems2.bytes,
                                                length: negativeItems2.count * 32 * MemoryLayout<UInt8>.stride,
                                                options: .storageModeShared)!
        let metalNegative = metalFilter.query(negativeItemsBuffer, batchSize: negativeItems.count)
        let metalFP = metalNegative.filter { !$0 }.count
        print("   Negative results: \(metalFP)")
        print("   Metal FPR: \(String(format: "%.4f%%", Double(metalFP) / 100.0))")
        print("   Expected:  \(String(format: "%.4f%%", fpr * 100))")
        
        assert(metalFP <= negativeItems.count && metalFP > negativeItems.count - 10) // 10 is just a guess and might fails since it is probabalistic
    }
     */

}
