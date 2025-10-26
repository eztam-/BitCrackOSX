import Foundation

/// A fast, non-thread-safe Bloom filter for items represented as sequences of UInt32 words.
/// - NOTE: For maximum speed, prefer `bitCapacity` that is a power of two (the initializer will
///         round it up automatically).
public final class BloomFilter {
    /// Number of bits in the filter (power of two)
    public let bitCapacity: UInt64
    /// Mask used for fast modulo (bitCapacity must be power-of-two)
    private let bitMask: UInt64
    /// Number of hash functions
    public let hashCount: Int
    /// Underlying storage as UInt64 words
    private var words: [UInt64]

    /// Create a Bloom filter
    /// - Parameters:
    ///   - bits: requested number of bits (will be rounded up to next power-of-two)
    ///   - hashCount: number of hash functions (k)
    public init(bits: UInt64, hashCount: Int) {
        precondition(hashCount > 0 && hashCount <= 128, "hashCount must be >0 and reasonable")
        let cap = BloomFilter.nextPowerOfTwo(bits)
        self.bitCapacity = cap
        self.bitMask = cap - 1
        self.hashCount = hashCount
        let wordCount = Int((cap + 63) / 64)
        self.words = [UInt64](repeating: 0, count: wordCount)
    }
    
    /// Insert an item described by an UnsafePointer<UInt32>
    /// - Parameters:
    ///   - ptr: pointer to UInt32 array
    ///   - length: number of UInt32 words that describe the item
    ///   - offset: start index inside the pointer (0-based)
    @inline(__always)
    public func insert(ptr: UnsafePointer<UInt32>, length: Int, offset: Int = 0) {
        // compute base hashes
        let (h1, h2) = BloomFilter.hashPair(ptr: ptr, length: length, offset: offset)
        var base = h1
        var step = h2
        // generate k indices and set bits
        // using (h1 + i * h2) & mask  (double-hashing)
        for i in 0..<hashCount {
            let idx = (base & bitMask)
            setBit(at: idx)
            base = base &+ step // wrapping add is fine
        }
    }

    /// Test whether an item (described by a pointer) is in the Bloom filter.
    /// Returns `true` if *probably* present; `false` if definitely absent.
    ///
    /// This is the hot path — heavily optimized: no allocations, inlined hashing functions,
    /// power-of-two modulo via bitmask, and UInt64 word-level bit ops.
    @inline(__always)
    public func contains(ptr: UnsafePointer<UInt32>, length: Int, offset: Int = 0) -> Bool {
        // compute two 64-bit hashes
        let (h1, h2) = BloomFilter.hashPair(ptr: ptr, length: length, offset: offset)
        var base = h1
        let step = h2
        // check k bits
        for _ in 0..<hashCount {
            let idx = base & bitMask
            if !testBit(at: idx) { return false }
            base = base &+ step
        }
        return true
    }

    /// Clear the filter (set all bits to zero)
    public func clear() {
        for i in words.indices { words[i] = 0 }
    }

    /// Expose words (read-only) for debugging / external storage if needed
    public func getWords() -> [UInt64] {
        return words
    }

    // MARK: - Private helpers

    @inline(__always)
    private func setBit(at bitIndex: UInt64) {
        let wordIndex = Int(bitIndex >> 6) // divide by 64
        let bitOffset = Int(bitIndex & 63)
        words[wordIndex] |= (1 as UInt64) << bitOffset
    }

    @inline(__always)
    private func testBit(at bitIndex: UInt64) -> Bool {
        let wordIndex = Int(bitIndex >> 6)
        let bitOffset = Int(bitIndex & 63)
        return (words[wordIndex] & ((1 as UInt64) << bitOffset)) != 0
    }

    // MARK: - Hashing (fast, non-cryptographic)

    /// Produce two 64-bit values for double hashing:
    /// - h1: FNV-1a-like 64-bit over the UInt32 words.
    /// - h2: splitmix64(h1) derived value.
    @inline(__always)
    private static func hashPair(ptr: UnsafePointer<UInt32>, length: Int, offset: Int) -> (UInt64, UInt64) {
        // FNV-1a 64-bit parameters
        // (Using multiplication & xor mixing; very fast)
        var hash: UInt64 = 0xcbf29ce484222325 // FNV offset basis
        let prime: UInt64 = 0x100000001b3

        // Read words; unroll loop a bit for speed. The pointer arithmetic uses offset.
        var p = ptr.advanced(by: offset)
        var remaining = length

        // Fast loop over 8 words at a time
        while remaining >= 8 {
            // unrolled 8x
            var w0 = UInt64(p.pointee); p = p.advanced(by: 1)
            var w1 = UInt64(p.pointee); p = p.advanced(by: 1)
            var w2 = UInt64(p.pointee); p = p.advanced(by: 1)
            var w3 = UInt64(p.pointee); p = p.advanced(by: 1)
            var w4 = UInt64(p.pointee); p = p.advanced(by: 1)
            var w5 = UInt64(p.pointee); p = p.advanced(by: 1)
            var w6 = UInt64(p.pointee); p = p.advanced(by: 1)
            var w7 = UInt64(p.pointee); p = p.advanced(by: 1)

            // mix each word into hash
            hash = (hash ^ (w0 &* 0x9e3779b97f4a7c15)) &* prime
            hash = (hash ^ (w1 &* 0x9e3779b97f4a7c15)) &* prime
            hash = (hash ^ (w2 &* 0x9e3779b97f4a7c15)) &* prime
            hash = (hash ^ (w3 &* 0x9e3779b97f4a7c15)) &* prime
            hash = (hash ^ (w4 &* 0x9e3779b97f4a7c15)) &* prime
            hash = (hash ^ (w5 &* 0x9e3779b97f4a7c15)) &* prime
            hash = (hash ^ (w6 &* 0x9e3779b97f4a7c15)) &* prime
            hash = (hash ^ (w7 &* 0x9e3779b97f4a7c15)) &* prime

            remaining -= 8
        }

        // leftover words
        while remaining > 0 {
            let w = UInt64(p.pointee)
            p = p.advanced(by: 1)
            hash = (hash ^ (w &* 0x9e3779b97f4a7c15)) &* prime
            remaining -= 1
        }

        // final mix (xorshift + multiply)
        var h1 = hash &+ 0x9e3779b97f4a7c15
        h1 = (h1 ^ (h1 >> 30)) &* 0xbf58476d1ce4e5b9
        h1 = (h1 ^ (h1 >> 27)) &* 0x94d049bb133111eb
        h1 = h1 ^ (h1 >> 31)

        // h2 from splitmix64 of h1
        var z = h1 &+ 0x9e3779b97f4a7c15
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        z = z ^ (z >> 31)
        let h2 = z | 1  // make odd to ensure full period

        return (h1, h2)
    }

    // MARK: - Utility

    /// Round up to next power of two (>= 1)
    @inline(__always)
    private static func nextPowerOfTwo(_ v: UInt64) -> UInt64 {
        var x = v
        if x == 0 { return 1 }
        x -= 1
        x |= x >> 1
        x |= x >> 2
        x |= x >> 4
        x |= x >> 8
        x |= x >> 16
        x |= x >> 32
        return x + 1
    }
}

