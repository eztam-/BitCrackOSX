import Foundation

// Base58 encoding implementation
struct Base58 {
    static let alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
    
    static func encode(_ data: Data) -> String {
        var bytes = [UInt8](data)
        var zerosCount = 0
        var length = 0
        var prefix: [Character] = []
        
        // Count leading zeros
        for byte in bytes {
            if byte != 0 { break }
            zerosCount += 1
            prefix.append("1")
        }
        
        // Remove leading zeros
        bytes.removeFirst(zerosCount)
        
        var digits = [0]
        for byte in bytes {
            var carry = Int(byte)
            for j in 0..<digits.count {
                carry += digits[j] << 8
                digits[j] = carry % 58
                carry = carry / 58
            }
            
            while carry > 0 {
                digits.append(carry % 58)
                carry = carry / 58
            }
        }
        
        // Build the result
        var result = prefix
        for digit in digits.reversed() {
            let index = alphabet.index(alphabet.startIndex, offsetBy: digit)
            result.append(alphabet[index])
        }
        
        return String(result)
    }
}


