import Foundation


/// A 256-bit unsigned integer type with proper increment functionality
struct UInt256: Equatable, Hashable, Comparable, CustomStringConvertible {
    // Store as 8 x 32-bit words (little-endian: words[0] is least significant)
    private var words: [UInt32]
    
    // MARK: - Initializers
    
    init() {
        self.words = [0, 0, 0, 0, 0, 0, 0, 0]
    }
    
    
    init(_ value: UInt64) {
        let low = UInt32(value & 0xFFFFFFFF)
        let high = UInt32(value >> 32)
        self.words = [low, high, 0, 0, 0, 0, 0, 0]
    }
    
    init(data: Data) {
        self.words = [0, 0, 0, 0, 0, 0, 0, 0]
        
        // Ensure we have exactly 32 bytes
        var paddedData = data
        if paddedData.count < 32 {
            paddedData = Data(repeating: 0, count: 32 - data.count) + data
        } else if paddedData.count > 32 {
            paddedData = paddedData.suffix(32)
        }
        
        // Convert from big-endian to little-endian for internal storage
        paddedData.withUnsafeBytes { buffer in
            let uint32Buffer = buffer.bindMemory(to: UInt32.self)
            for i in 0..<8 {
                // Convert from big-endian to little-endian
                self.words[7 - i] = uint32Buffer[i].bigEndian
            }
        }
    }
    
    init(words: [UInt32]) {
        precondition(words.count == 8, "UInt256 requires exactly 8 words")
        self.words = words
    }

    
    init(hexString: String) {
        var hex = hexString
        if hex.hasPrefix("0x") {
            hex = String(hex.dropFirst(2))
        }
        
        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let endIndex = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            let byteString = hex[index..<endIndex]
            if let byte = UInt8(byteString, radix: 16) {
                data.append(byte)
            }
            index = endIndex
        }
        
        self.init(data: data)
    }
    
    // MARK: - Properties
    
    var isZero: Bool {
        return words.allSatisfy { $0 == 0 }
    }
    
    var description: String {
        return hexString
    }
    
    var hexString: String {
        return "0x" + data.map { String(format: "%02x", $0) }.joined()
    }
    
    var data: Data {
        var result = Data()
        // Convert from little-endian to big-endian for external representation
        for i in (0..<8).reversed() {
            var word = words[i].bigEndian
            result.append(Data(bytes: &word, count: MemoryLayout<UInt32>.size))
        }
        return result
    }
    
    
    // MARK: - Increment Operations
    
    /// Increment by 1, returning true if overflow occurred
    @discardableResult
    mutating func increment() -> Bool {
        var carry: UInt64 = 1 // Start with 1 to increment
        
        for i in 0..<8 {
            let sum = UInt64(words[i]) + carry
            words[i] = UInt32(sum & 0xFFFFFFFF)
            carry = sum >> 32
            
            if carry == 0 {
                break // No more carry to propagate
            }
        }
        
        // Return true if there was a carry out from the most significant word
        return carry > 0
    }
    
    /// Increment by a specific value
    @discardableResult
    mutating func increment(by value: UInt256) -> Bool {
        var carry: UInt64 = 0
        
        for i in 0..<8 {
            let sum = UInt64(words[i]) + UInt64(value.words[i]) + carry
            words[i] = UInt32(sum & 0xFFFFFFFF)
            carry = sum >> 32
        }
        
        return carry > 0
    }
    
    /// Non-mutating increment that returns a new UInt256
    func incremented() -> (value: UInt256, overflow: Bool) {
        var result = self
        let overflow = result.increment()
        return (result, overflow)
    }
    
    // MARK: - Decrement Operations
    
    @discardableResult
    mutating func decrement() -> Bool {
        var borrow: UInt64 = 1 // Start with 1 to decrement
        
        for i in 0..<8 {
            let word = UInt64(words[i])
            if word >= borrow {
                words[i] = UInt32(word - borrow)
                borrow = 0
                break
            } else {
                words[i] = UInt32((word + 0x100000000) - borrow)
                borrow = 1
            }
        }
        
        return borrow > 0 // Underflow occurred
    }
    
    // MARK: - Comparison
    
    static func == (lhs: UInt256, rhs: UInt256) -> Bool {
        return lhs.words == rhs.words
    }
    
    static func < (lhs: UInt256, rhs: UInt256) -> Bool {
        for i in (0..<8).reversed() {
            if lhs.words[i] < rhs.words[i] {
                return true
            } else if lhs.words[i] > rhs.words[i] {
                return false
            }
        }
        return false // Equal
    }
    
    static func <= (lhs: UInt256, rhs: UInt256) -> Bool {
        return lhs < rhs || lhs == rhs
    }
    
    static func > (lhs: UInt256, rhs: UInt256) -> Bool {
        return rhs < lhs
    }
    
    static func >= (lhs: UInt256, rhs: UInt256) -> Bool {
        return rhs <= lhs
    }
    
    // MARK: - Bitwise Operations
    
    static func & (lhs: UInt256, rhs: UInt256) -> UInt256 {
        var result = UInt256()
        for i in 0..<8 {
            result.words[i] = lhs.words[i] & rhs.words[i]
        }
        return result
    }
    
    static func | (lhs: UInt256, rhs: UInt256) -> UInt256 {
        var result = UInt256()
        for i in 0..<8 {
            result.words[i] = lhs.words[i] | rhs.words[i]
        }
        return result
    }
    
    static func ^ (lhs: UInt256, rhs: UInt256) -> UInt256 {
        var result = UInt256()
        for i in 0..<8 {
            result.words[i] = lhs.words[i] ^ rhs.words[i]
        }
        return result
    }
    
    static prefix func ~ (value: UInt256) -> UInt256 {
        var result = UInt256()
        for i in 0..<8 {
            result.words[i] = ~value.words[i]
        }
        return result
    }
}

// MARK: - Arithmetic Operations

extension UInt256 {
    static func + (lhs: UInt256, rhs: UInt256) -> (value: UInt256, overflow: Bool) {
        var result = lhs
        let overflow = result.increment(by: rhs)
        return (result, overflow)
    }
    
    static func - (lhs: UInt256, rhs: UInt256) -> (value: UInt256, overflow: Bool) {
        // Implement subtraction using two's complement
        let negatedRhs = ~rhs + UInt256(1)
        return lhs + negatedRhs.value
    }
}

// MARK: - Bitcoin Private Key Extensions

extension UInt256 {
    /// SECP256k1 curve order
    static let curveOrder: UInt256 = {
        let hex = "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141"
        return UInt256(hexString: hex)
    }()
    
    /// Maximum valid private key (curve order - 1)
    static let maxPrivateKey: UInt256 = {
        let hex = "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364140"
        return UInt256(hexString: hex)
    }()
    
    /// Check if this is a valid Bitcoin private key
    var isValidPrivateKey: Bool {
        return !isZero && self <= UInt256.maxPrivateKey
    }
    
    /// Increment but wrap around to 1 if we exceed maxPrivateKey
    mutating func incrementPrivateKey() {
        if self >= UInt256.maxPrivateKey {
            // Wrap around to 1
            self = UInt256(1)
        } else {
            self.increment()
        }
    }
    
    /// Get the next valid private key in sequence
    func nextPrivateKey() -> UInt256 {
        var result = self
        result.incrementPrivateKey()
        return result
    }
}

// MARK: - Collection Support

extension UInt256 {
    /// Access individual bytes (big-endian)
    subscript(byteIndex: Int) -> UInt8 {
        get {
            precondition(byteIndex >= 0 && byteIndex < 32, "Byte index out of range")
            let wordIndex = 7 - (byteIndex / 4) // Convert to little-endian word index
            let byteInWord = byteIndex % 4
            return UInt8((words[wordIndex] >> (byteInWord * 8)) & 0xFF)
        }
        set {
            precondition(byteIndex >= 0 && byteIndex < 32, "Byte index out of range")
            let wordIndex = 7 - (byteIndex / 4)
            let byteInWord = byteIndex % 4
            let mask: UInt32 = ~(0xFF << (byteInWord * 8))
            let value = UInt32(newValue) << (byteInWord * 8)
            words[wordIndex] = (words[wordIndex] & mask) | value
        }
    }
}

// MARK: - Metal Compatibility

extension UInt256 {
    /// Convert to Metal-compatible structure
    func toMetalUInt256() -> MetalUInt256 {
        return MetalUInt256(d: (
            words[0], words[1], words[2], words[3],
            words[4], words[5], words[6], words[7]
        ))
    }
    
    /// Initialize from Metal structure
    init(metalUInt256: MetalUInt256) {
        self.words = [
            metalUInt256.d.0, metalUInt256.d.1, metalUInt256.d.2, metalUInt256.d.3,
            metalUInt256.d.4, metalUInt256.d.5, metalUInt256.d.6, metalUInt256.d.7
        ]
    }
}

// MARK: - Metal Structure

/// Metal-compatible 256-bit integer structure
struct MetalUInt256 {
    var d: (UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32)
    
    init() {
        self.d = (0, 0, 0, 0, 0, 0, 0, 0)
    }
    
    init(d: (UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32)) {
        self.d = d
    }
}

// MARK: - Usage Examples and Tests

class UInt256Tests {
    static func runTests() {
        print("=== UInt256 Tests ===")
        
        // Test 1: Basic initialization
        let zero = UInt256()
        print("Zero: \(zero.hexString)")
        
        let one = UInt256(1)
        print("One: \(one.hexString)")
        
        // Test 2: Increment
        var testValue = UInt256(1)
        print("Start: \(testValue.hexString)")
        
        testValue.increment()
        print("After increment: \(testValue.hexString)")
        
        // Test 3: Large value
        let largeHex = "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE"
        let largeValue = UInt256(hexString: largeHex)
        print("Large value: \(largeValue.hexString)")
        
        var largeIncremented = largeValue
        let overflow = largeIncremented.increment()
        print("Large + 1: \(largeIncremented.hexString), overflow: \(overflow)")
        
        // Test 4: Bitcoin private key validation
        let validKey = UInt256(hexString: "0000000000000000000000000000000000000000000000000000000000000001")
        let invalidKey = UInt256(hexString: "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364142")
        
        print("Valid key: \(validKey.isValidPrivateKey)")
        print("Invalid key: \(invalidKey.isValidPrivateKey)")
        
        // Test 5: Private key increment with wrap-around
        var maxKey = UInt256.maxPrivateKey
        print("Max private key: \(maxKey.hexString)")
        maxKey.incrementPrivateKey()
        print("After increment (wrapped): \(maxKey.hexString)")
        
        // Test 6: Data conversion
        let testData = Data([0x01, 0x02, 0x03, 0x04])
        let fromData = UInt256(data: testData)
        print("From data: \(fromData.hexString)")
        print("Back to data: \(fromData.data.hex)")
    }
}

// Data extension for hex representation
extension Data {
    var hex: String {
        return map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Iterator for Bitcoin Private Keys

struct BitcoinPrivateKeyIterator: Sequence, IteratorProtocol {
    private var current: UInt256
    private let end: UInt256?
    private var reachedEnd: Bool = false
    
    init(start: UInt256 = UInt256(1), end: UInt256? = UInt256.maxPrivateKey) {
        self.current = start
        self.end = end
    }
    
    mutating func next() -> UInt256? {
        guard !reachedEnd else { return nil }
        
        let result = current
        
        // Check if we've reached the end
        if let end = end, current >= end {
            reachedEnd = true
            return result
        }
        
        current.incrementPrivateKey()
        
        // Check if we've wrapped around to start (shouldn't happen with proper bounds)
        if current == UInt256(1) {
            reachedEnd = true
        }
        
        return result
    }
}

// Usage example
func demonstrateUsage() {
    print("=== Bitcoin Private Key Iterator ===")
    
    // Iterate through a small range of private keys
    let start = UInt256(hexString: "0000000000000000000000000000000000000000000000000000000000000001")
    let end = UInt256(hexString: "0000000000000000000000000000000000000000000000000000000000000005")
    
    let keyIterator = BitcoinPrivateKeyIterator(start: start, end: end)
    
    for (index, privateKey) in keyIterator.enumerated() {
        print("Key \(index + 1): \(privateKey.hexString)")
    }
    
    // Generate keys in batches
    print("\n=== Batch Generation ===")
    var batch: [UInt256] = []
    let batchIterator = BitcoinPrivateKeyIterator(start: UInt256(1))
    
    for key in batchIterator {
        batch.append(key)
        if batch.count >= 10 {
            break
        }
    }
    
    print("Generated \(batch.count) keys")
    for key in batch {
        print("  \(key.hexString)")
    }
}

