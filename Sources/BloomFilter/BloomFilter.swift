import Foundation
import Metal
import CryptoKit

// ================= Helpers =================

@inline(__always)
func roundup(_ x: Int, to multiple: Int) -> Int {
    return (x + multiple - 1) / multiple * multiple
}

// Create a 20-byte key from Data; pad/truncate as needed
func make20(_ d: Data) -> Data {
    var out = Data(count: 20)
    out.replaceSubrange(0..<min(20, d.count), with: d.prefix(20))
    return out
}

// ================= GPU Bloom Filter =================

final class BloomFilter {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let lib: MTLLibrary

    let insertPSO: MTLComputePipelineState
    let queryPSO:  MTLComputePipelineState

    let bitCount: Int         // m_bits
    let kHashes: Int          // k
    let bitWords: Int         // number of 32-bit words in bitset
    let itemBytes: Int

    // Buffers
    let bitsBuffer: MTLBuffer // atomic_uint/uint bitset (same storage, different usage)
    // Reusable staging buffers (grown on demand)
    var itemsBuf: MTLBuffer?
    var outBuf:   MTLBuffer?

    
    
    init?(device: MTLDevice,
             expectedInsertions n: Int,
             itemBytes: Int = 20,
             falsePositiveRate p: Double = 0.001
             )
       {
           self.device = device
           self.itemBytes = itemBytes
           guard let q = device.makeCommandQueue() else { return nil }
           self.queue = q

           // --- Compile kernels ---
           let options = MTLCompileOptions()
           options.languageVersion = .version3_1
           self.lib = try! device.makeDefaultLibrary(bundle: Bundle.module)

           let insertFn = lib.makeFunction(name: "bloom_insert")!
           let queryFn  = lib.makeFunction(name: "bloom_query")!
           self.insertPSO = try! device.makeComputePipelineState(function: insertFn)
           self.queryPSO  = try! device.makeComputePipelineState(function: queryFn)

           // --- Compute optimal size & hash count ---
           // m = - (n * ln(p)) / (ln(2)^2)
           let ln2 = log(2.0)
           var mDouble = -Double(n) * log(p) / (ln2 * ln2)
           // Round up to nearest power of two
           var m = 1
           while Double(m) < mDouble { m <<= 1 }

           // k = (m/n) * ln(2)
           var k = Int(round((Double(m) / Double(n)) * ln2))
           if k < 1 { k = 1 }

           self.bitCount = m
           self.kHashes = k
           self.bitWords = m / 32

           print("Bloom filter size: \(m) bits (\(m/8) bytes), k=\(k), FPR≈\(p)")

           // Allocate shared bit array
           self.bitsBuffer = device.makeBuffer(length: bitWords * MemoryLayout<UInt32>.stride,
                                               options: .storageModeShared)!
           memset(bitsBuffer.contents(), 0, bitWords * MemoryLayout<UInt32>.stride)
       }
    


    // Ensure we have a staging buffer for N items (each 20 bytes)
    private func ensureItemBuffer(for count: Int) {
        let needed = count * 20
        if itemsBuf == nil || itemsBuf!.length < needed {
            itemsBuf = device.makeBuffer(length: needed, options: .storageModeShared)
        }
    }

    private func ensureOutBuffer(for count: Int) {
        let needed = count * MemoryLayout<UInt32>.stride
        if outBuf == nil || outBuf!.length < needed {
            outBuf = device.makeBuffer(length: needed, options: .storageModeShared)
        }
    }

    // Insert a batch of 20-byte items
    func insert(items: [Data]) {
        let count = items.count
        guard count > 0 else { return }

        ensureItemBuffer(for: count)

        // Pack items (20 bytes each) into itemsBuf
        let ptr = itemsBuf!.contents().assumingMemoryBound(to: UInt8.self)
        for (i, d) in items.enumerated() {
            let k = make20(d)
            k.copyBytes(to: ptr.advanced(by: i * 20), count: 20)
        }

        // Setup constants
        var countU = UInt32(count)
        var mBitsU = UInt32(bitCount)
        var kU     = UInt32(kHashes)

        // Encode kernel
        let cmd = queue.makeCommandBuffer()!
        let enc = cmd.makeComputeCommandEncoder()!
        enc.setComputePipelineState(insertPSO)
        enc.setBuffer(itemsBuf,   offset: 0, index: 0)
        enc.setBytes(&countU,     length: MemoryLayout<UInt32>.size, index: 1)
        enc.setBuffer(bitsBuffer, offset: 0, index: 2)
        enc.setBytes(&mBitsU,     length: MemoryLayout<UInt32>.size, index: 3)
        enc.setBytes(&kU,         length: MemoryLayout<UInt32>.size, index: 4)

        // Dispatch
        let w = insertPSO.threadExecutionWidth
        let threadsPerTG = MTLSize(width: min(256, w * 4), height: 1, depth: 1)
        let threadsPerGrid = MTLSize(width: count, height: 1, depth: 1)
        enc.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerTG)
        enc.endEncoding()

        cmd.commit()
        cmd.waitUntilCompleted()
    }

    // Query a batch of 20-byte items; returns array of 0/1 (definitely-not / maybe)
    func query(items: [Data]) -> [UInt32] {
        let count = items.count
        guard count > 0 else { return [] }

        ensureItemBuffer(for: count)
        ensureOutBuffer(for: count)

        // Pack items
        let ptr = itemsBuf!.contents().assumingMemoryBound(to: UInt8.self)
        for (i, d) in items.enumerated() {
            let k = make20(d)
            k.copyBytes(to: ptr.advanced(by: i * 20), count: 20)
        }

        // Setup constants
        var countU = UInt32(count)
        var mBitsU = UInt32(bitCount)
        var kU     = UInt32(kHashes)

        // Encode kernel
        let cmd = queue.makeCommandBuffer()!
        let enc = cmd.makeComputeCommandEncoder()!
        enc.setComputePipelineState(queryPSO)
        enc.setBuffer(itemsBuf,   offset: 0, index: 0)
        enc.setBytes(&countU,     length: MemoryLayout<UInt32>.size, index: 1)
        enc.setBuffer(bitsBuffer, offset: 0, index: 2)
        enc.setBytes(&mBitsU,     length: MemoryLayout<UInt32>.size, index: 3)
        enc.setBytes(&kU,         length: MemoryLayout<UInt32>.size, index: 4)
        enc.setBuffer(outBuf,     offset: 0, index: 5)

        // Dispatch
        let w = queryPSO.threadExecutionWidth
        let threadsPerTG = MTLSize(width: min(256, w * 4), height: 1, depth: 1)
        let threadsPerGrid = MTLSize(width: count, height: 1, depth: 1)
        enc.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerTG)
        enc.endEncoding()

        cmd.commit()
        cmd.waitUntilCompleted()

        // Read back
        let resPtr = outBuf!.contents().bindMemory(to: UInt32.self, capacity: count)
        return Array(UnsafeBufferPointer(start: resPtr, count: count))
    }
}

// ================= Demo =================
public func runBloom(device: MTLDevice){
    


    
    // Design your Bloom filter:
    // Suppose you expect ~1,000,000 inserts with p≈1%
    // m ≈ -n * ln(p) / (ln2)^2  ≈ 9.6e6 bits -> round to power of two for speed (e.g., 1<<24 = 16,777,216)
    let mBits = 1 << 24            // 16,777,216 bits
    let k = 7                      // near-optimal ~ m/n * ln2; tweak for your n
    
    guard let bloom = BloomFilter(device: device, expectedInsertions:10_000, itemBytes: 20, falsePositiveRate: 0.001) else {
        fatalError("Failed to init GPUBloom")
    }
    /*
    init?(device: MTLDevice,
             expectedInsertions n: Int,
             itemBytes: Int = 20,
             falsePositiveRate p: Double = 0.01
    */
    
    // Prepare some sample 20-byte keys
    func key(_ s: String) -> Data {
        // 20 bytes: hash of string
        var h = SHA256.hash(data: s.data(using: .utf8)!)
        // take first 20 bytes
        return Data(h.prefix(20))
    }
    
    // Minimal SHA256 wrapper (since CryptoKit may not be available in all targets)
    
    let inserts: [Data] = (0..<10_000).map { i in key("present-\(i)") }
    let queriesPresent: [Data] = (0..<10_000).map { i in key("present-\(i)") }
    let queriesAbsent:  [Data] = (0..<10_000).map { i in key("absent-\(i)") }
    
    // Insert
    bloom.insert(items: inserts)
    
    // Query (present)
    let resP = bloom.query(items: queriesPresent)
    let hitsP = resP.reduce(0) { $0 + Int($1) }
    print("Present queries: \(hitsP)/\(queriesPresent.count) should be ~all 1s")
    
    // Query (absent)
    let resA = bloom.query(items: queriesAbsent)
    let hitsA = resA.reduce(0) { $0 + Int($1) }
    print("Absent queries: \(hitsA)/\(queriesAbsent.count) (false positives)")
}
