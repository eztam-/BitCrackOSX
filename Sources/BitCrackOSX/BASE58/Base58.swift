import Foundation


private let alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

// Base58 encoding implementation
struct Base58 {
    
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
    
    
    /*
    static func decode(_ data: String) -> Data {
        let characterToValue: [Character: Int] = Dictionary(
            uniqueKeysWithValues: alphabet.enumerated().map { ($1, $0) }
        )
        
        // Convert string to array of numeric values
        guard let values = data.map({ characterToValue[$0] }).compactMap({ $0 }) as [Int]?,
              values.count == data.count else {
            fatalError("Error decoding Base58.")
        }
        
        // Count leading ones
        let leadingOnes = data.prefix { $0 == "1" }.count
        
        // Convert from base58 to base256
        var result: [Int] = []
        for value in values {
            var carry = value
            for j in 0..<result.count {
                carry += result[j] * 58
                result[j] = carry % 256
                carry /= 256
            }
            while carry > 0 {
                result.append(carry % 256)
                carry /= 256
            }
        }
        
        // Convert to bytes and add leading zeros
        let bytes = Array(repeating: 0, count: leadingOnes) + result.reversed().map { UInt8($0) }
        return Data(bytes)
    }*/
    

    // Precomputed lookup table for O(1) character to value conversion
      private static let characterMap: [UInt8] = {
          var map = [UInt8](repeating: 0xFF, count: 128) // ASCII range
          for (index, char) in alphabet.utf8.enumerated() {
              map[Int(char)] = UInt8(index)
          }
          return map
      }()
      
      // MARK: - Ultra High Performance Decoding
      @inlinable
      public static func decode(_ input: String) -> Data? {
          return input.withCString { cString in
              decode(cString: cString, length: input.utf8.count)
          }
      }
      
      @inlinable
      public static func decode(cString: UnsafePointer<CChar>, length: Int) -> Data? {
          guard length > 0 else { return Data() }
          
          // Count leading '1' characters (which represent zeros)
          var leadingZeros = 0
          var ptr = cString
          while leadingZeros < length && ptr.pointee == 0x31 { // '1' in ASCII
              leadingZeros += 1
              ptr += 1
          }
          
          let remaining = length - leadingZeros
          guard remaining > 0 else {
              return Data(repeating: 0, count: leadingZeros)
          }
          
          // Estimate maximum output size (log58(256) ≈ 1.37)
          let maxOutputSize = (remaining * 140) / 100 + 1 // Conservative estimate
          let outputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: maxOutputSize)
          defer { outputBuffer.deallocate() }
          
          var outputSize = 0
          
          // Process each character
          for i in 0..<remaining {
              let char = UInt8(bitPattern: ptr[i])
              
              // Fast bounds check and lookup
              guard char < 128 else { return nil }
              let value = characterMap[Int(char)]
              guard value != 0xFF else { return nil }
              
              var carry = Int(value)
              
              // Multiply through existing digits (base conversion)
              var j = 0
              while j < outputSize {
                  carry += Int(outputBuffer[j]) * 58
                  outputBuffer[j] = UInt8(carry & 0xFF)
                  carry >>= 8
                  j += 1
              }
              
              // Handle remaining carry
              while carry > 0 {
                  guard outputSize < maxOutputSize else { return nil }
                  outputBuffer[outputSize] = UInt8(carry & 0xFF)
                  outputSize += 1
                  carry >>= 8
              }
          }
          
          // Calculate actual result size and prepare final data
          let totalSize = leadingZeros + outputSize
          var result = Data(count: totalSize)
          
          result.withUnsafeMutableBytes { mutableBuffer in
              guard let baseAddress = mutableBuffer.baseAddress else { return }
              let resultPtr = baseAddress.assumingMemoryBound(to: UInt8.self)
              
              // Set leading zeros
              for i in 0..<leadingZeros {
                  resultPtr[i] = 0
              }
              
              // Copy result in reverse (convert from little-endian to big-endian)
              for i in 0..<outputSize {
                  resultPtr[leadingZeros + outputSize - 1 - i] = outputBuffer[i]
              }
          }
          
          return result
      }
 
     
    /// Parallel BASE58 decoding using all available CPU cores (blocking version)
    static func decodeBatchAsync(_ inputs: [String]) -> [Data] {
        let processorCount = ProcessInfo.processInfo.processorCount
        var results = [Data?](repeating: nil, count: inputs.count)
        let lock = NSLock()
        
        // Use concurrentPerform for optimal parallel execution
        DispatchQueue.concurrentPerform(iterations: inputs.count) { index in
            let input = inputs[index]
            let decodedData = decode(input)
            
            // Thread-safe write to results
            lock.lock()
            results[index] = decodedData
            lock.unlock()
        }
        
        // Remove nil values (failed decodings) and return
        return results.compactMap { $0 }
    }

    enum DecodingError: Error, LocalizedError {
        case invalidInput(String)
        
        var errorDescription: String? {
            switch self {
            case .invalidInput(let input):
                return "Failed to decode BASE58 input: \(input)"
            }
        }
    }
    
    
    
}


