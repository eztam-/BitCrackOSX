import Foundation
import Metal

// Extension for hex string conversion
extension Data {
    public var hexString: String {
        return map { String(format: "%02x", $0) }.joined()
    }
    
    init?(hex: String) {
        let len = hex.count / 2
        var data = Data(capacity: len)
        var index = hex.startIndex

        for _ in 0..<len {
            let nextIndex = hex.index(index, offsetBy: 2)
            if nextIndex > hex.endIndex { return nil }

            let byteString = hex[index..<nextIndex]
            if let byte = UInt8(byteString, radix: 16) {
                data.append(byte)
            } else {
                return nil
            }

            index = nextIndex
        }
        self = data
    }
}



public class Helpers{
   
    public static func printLimbs(limbs: [UInt32]){
        print("Limbs: \(limbs.map { String(format: "0x%08X", $0) })")
    }


    /// Converts a 256-bit hex string into 8 UInt32 limbs (little-endian, least-significant limb first).
    ///
    /// - Parameter hex: A 64-character hexadecimal string (case-insensitive)
    /// - Returns: Array of 8 UInt32 values, where limbs[0] is least significant.
    /// - Throws: If the hex string length is invalid or contains non-hex characters.
    public static func hex256ToUInt32Limbs(_ hex: String) -> [UInt32] {
        var result = [UInt32](repeating: 0, count: 8)
        let clean = hex.replacingOccurrences(of: "0x", with: "")
        let padded = String(repeating: "0", count: max(0, 64 - clean.count)) + clean
        
        // Parse from right to left (little-endian)
        for i in 0..<8 {
            let endIdx = padded.count - (i * 8)
            let startIdx = endIdx - 8
            let start = padded.index(padded.startIndex, offsetBy: startIdx)
            let end = padded.index(padded.startIndex, offsetBy: endIdx)
            let chunk = String(padded[start..<end])
            result[i] = UInt32(chunk, radix: 16) ?? 0
        }
        
        return result
    }

    
    // Convert UnsafeMutablePointer<UInt32> to 8 UInt32 limbs
    public static func pointerToLimbs(_ pointer: UnsafeMutablePointer<UInt32>, limbCount: Int = 8) -> [UInt32] {
        var limbs = [UInt32](repeating: 0, count: limbCount)
        
        for i in 0..<limbCount {
            limbs[i] = pointer[i]
        }
        
        return limbs
    }
    
    // Pointer to data
    public static func createData(from pointer: UnsafePointer<UInt32>, offset: Int, length: Int) -> Data {
        let startPointer = pointer.advanced(by: offset)
        let buffer = UnsafeBufferPointer(start: startPointer, count: length)
        
        return Data(buffer: buffer)
    }
    
    
    // Utility: build 8-limb little-endian UInt32 array from 32 bytes
    public static func uint32LimbsFromBytes(_ b: [UInt8]) -> [UInt32] {
        precondition(b.count == 32)
        var arr = [UInt32](repeating: 0, count: 8)
        for i in 0..<8 {
            let base = i * 4
            arr[i] = UInt32(b[base]) | (UInt32(b[base+1]) << 8) | (UInt32(b[base+2]) << 16) | (UInt32(b[base+3]) << 24)
        }
        return arr
    }
    
    
    public static func generateRandom256BitHex() -> String {
        var bytes = [UInt8](repeating: 0, count: 32) // 32 bytes = 256 bits
        let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard result == errSecSuccess else {
            fatalError("Failed to generate secure random bytes")
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
    
    
    public static func ptrToDataArray(_ ptr: UnsafeMutablePointer<UInt32>,
                              itemSize: Int,
                              itemCount: Int) -> [Data] {

        let rawPtr = UnsafeRawPointer(ptr)
        var result: [Data] = []
        result.reserveCapacity(itemCount)

        for i in 0..<itemCount {
            let itemPtr = rawPtr.advanced(by: i * itemSize)
            let data = Data(bytes: itemPtr, count: itemSize)
            result.append(data)
        }

        return result
    }
    
    
    public static func printGPUInfo(device: MTLDevice) {
        let name = device.name
        let maxThreadsPerThreadgroup = device.maxThreadsPerThreadgroup
        let registryID = device.registryID
        let isLowPower = device.isLowPower
        let hasUnifiedMemory = device.hasUnifiedMemory
        let recommendedMaxWorkingSetSize = device.recommendedMaxWorkingSetSize
        let memoryMB = recommendedMaxWorkingSetSize / (1024 * 1024)

        print("""
        
        ⚡ GPU Information
            Name:               \(name)
            Registry ID:        \(registryID)
            Low Power:          \(isLowPower ? "Yes" : "No")
            Unified Memory:     \(hasUnifiedMemory ? "Yes" : "No")
            Max Threads:        \(maxThreadsPerThreadgroup.width) x \(maxThreadsPerThreadgroup.height) x \(maxThreadsPerThreadgroup.depth)
            Recommended Memory: \(memoryMB) MB
        
        """)
    }
    
    
    actor SafeQueue<T: Sendable> {
        private var items: [T] = []

        func enqueue(_ item: T) { items.append(item) }

        func dequeue() -> T? {
            guard !items.isEmpty else { return nil }
            return items.removeFirst()
        }

        var count: Int { items.count }
    }

    

    
}

