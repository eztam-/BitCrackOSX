import Foundation

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
    
    
}

