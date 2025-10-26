import Foundation

final class BloomFilter2 {
    private let bitCount: Int
    private let hashCount: Int
    private let bitArray: UnsafeMutablePointer<UInt8>

    init(capacity: Int, falsePositiveRate: Double) {
        // Formula: m = - (n * ln(p)) / (ln(2)^2)
        let m = ceil(-(Double(capacity) * log(falsePositiveRate)) / pow(log(2.0), 2.0))
        bitCount = Int(m)
        // Formula: k = (m / n) * ln(2)
        hashCount = max(1, Int(round((m / Double(capacity)) * log(2.0))))
        
        // Allocate byte array (ceil(m/8))
        let byteCount = (bitCount + 7) / 8
        bitArray = UnsafeMutablePointer<UInt8>.allocate(capacity: byteCount)
        bitArray.initialize(repeating: 0, count: byteCount)
    }

    deinit {
        bitArray.deallocate()
    }

    // MARK: - Public API

    func insert(pointer: UnsafePointer<UInt32>, length: Int, offset: Int = 0) {
        let (h1, h2) = hashPair(pointer: pointer, length: length, offset: offset)
        for i in 0..<hashCount {
            let bitIndex = Int((UInt64(h1) &+ UInt64(i) &* UInt64(h2)) % UInt64(bitCount))
            setBit(bitIndex)
        }
    }

    func insert(data: Data) {
        data.withUnsafeBytes { rawPtr in
            let count = rawPtr.count / MemoryLayout<UInt32>.size
            rawPtr.bindMemory(to: UInt32.self).baseAddress.map { basePtr in
                insert(pointer: basePtr, length: count)
            }
        }
    }
    
    func contains(pointer: UnsafePointer<UInt32>, length: Int, offset: Int = 0) -> Bool {
        let (h1, h2) = hashPair(pointer: pointer, length: length, offset: offset)
        for i in 0..<hashCount {
            let bitIndex = Int((UInt64(h1) &+ UInt64(i) &* UInt64(h2)) % UInt64(bitCount))
            if !getBit(bitIndex) {
                return false
            }
        }
        return true
    }

    // MARK: - Bit Operations

    @inline(__always)
    private func setBit(_ bitIndex: Int) {
        let byteIndex = bitIndex >> 3
        let mask = UInt8(1 << (bitIndex & 7))
        bitArray[byteIndex] |= mask
    }

    @inline(__always)
    private func getBit(_ bitIndex: Int) -> Bool {
        let byteIndex = bitIndex >> 3
        let mask = UInt8(1 << (bitIndex & 7))
        return (bitArray[byteIndex] & mask) != 0
    }

    // MARK: - Hashing

    /// Double-hash generation using FNV-1a + mix
    @inline(__always)
    private func hashPair(pointer: UnsafePointer<UInt32>, length: Int, offset: Int) -> (UInt32, UInt32) {
        var h1: UInt32 = 0x811C9DC5
        var h2: UInt32 = 0xABC98388
        
        let p = pointer.advanced(by: offset)
        for i in 0..<length {
            let val = p[i]
            h1 = (h1 ^ val) &* 0x01000193
            h2 = (h2 &+ (val &* 0x9E3779B1)) ^ (h2 >> 13)
        }
        return (h1, h2)
    }
}
