import Foundation
import Metal
import BigNumber


enum KeySearchError: Error {
    case wrongThreadPerGridMultiple
    case wrongThreadNumber
    case invaliedKeyGenBatchSize
}



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
   

    nonisolated(unsafe) public static var TEST_MODE = false
    
    private static let device : MTLDevice = MTLCreateSystemDefaultDevice()!
    
    public static func printLimbs(limbs: [UInt32]){
        print("Limbs: \(limbs.map { String(format: "0x%08X", $0) })")
    }

    
    // Only use this method to create a device. Only one device should be created and shared.
    // Otherwise it would destroy cache locality and internal driver pooling and even prevent sharing of resources (e.g., buffers and pipelines)
    public static func getSharedDevice() -> MTLDevice{
        return self.device
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
    
    
    public static func printGPUInfo(device: MTLDevice) throws {
        let name = device.name
        let maxThreadsPerThreadgroup = device.maxThreadsPerThreadgroup
        let isLowPower = device.isLowPower
        let hasUnifiedMemory = device.hasUnifiedMemory
        let memoryMB = device.recommendedMaxWorkingSetSize / (1024 * 1024)


        print("""
        
        ⚡ GPU Information
            Name:               \(name)
            Low Power:          \(isLowPower ? "Yes" : "No")
            Unified Memory:     \(hasUnifiedMemory ? "Yes" : "No")
            Max Threads per TG: \(maxThreadsPerThreadgroup.width)
            Recommended Memory: \(memoryMB) MB
        
        """)
    }
    

    /**
        threadsPerThreadgroupMultiplier: Use to fine tune per kernel. If the maximum is exceeded, the number is automatically capped to the max (16 on M1 or 32 on M3,...) Use preferably number that are a power of 2 (2,4,8,16,..)
     */
    public static func getThreadConfig(pipelineState: MTLComputePipelineState, batchSize: Int, threadsPerThreadgroupMultiplier: Int = 1) throws -> (MTLSize, MTLSize)  {
        let threadExecutionWidth = pipelineState.threadExecutionWidth // Might differ from kernel to kernal and also between GPUs but usually 32 on M1
        let maxTotalThreadsPerThreadgroup = pipelineState.maxTotalThreadsPerThreadgroup // Always the same but different on different GPUs (M1=512; M2,M3 = 1024)

        // The threadsPerThreadgroup must not exceed maxTotalThreadsPerThreadgroup
        let threadsPerThreadgroup = min(threadExecutionWidth * threadsPerThreadgroupMultiplier, maxTotalThreadsPerThreadgroup)
        
        // The threadsPerThreadgroup must be a multiple of threadExecutionWidth for best performance!
        assert(threadsPerThreadgroup % threadExecutionWidth == 0)
        if threadsPerThreadgroup % threadExecutionWidth != 0 {
            throw KeySearchError.wrongThreadPerGridMultiple
        }
            
        // For linear structured data like in our case, array processing, we create a 1D threadGroup
        let threadsPerTGSize = MTLSize(width: threadsPerThreadgroup, height: 1, depth: 1)
        
        // classic integer rounding trick to ensure a sufficient number of TGs if the batchSize is not dividable by threadsPerThreadgroup to a integer
        // This is actually not needed since we ensure that the batch size is always a multiple of device.maxThreadsPerThreadgroup.width  but we keep it here for now since it doesn't harm
        let threadgroupsPerGrid = MTLSize(width: (batchSize + threadsPerThreadgroup - 1) / threadsPerThreadgroup, height: 1, depth: 1)
       //let threadgroupsPerGrid = MTLSize(width: 1024, height: 1, depth: 1)
        
        // We could also say batchSize < threadgroupsPerGrid.width * threadsPerTGSize.width if we would allow arbitrary batch sizes that are not a multiple of device.maxThreadsPerThreadgroup.width
        // But keeping it for now !=
        if batchSize > threadgroupsPerGrid.width * threadsPerTGSize.width {
            print("totalThreads isn't equal to (threadgroupsPerGrid.width * threadsPerThreadgroupSize.width)")
            print("\(batchSize) != \(threadgroupsPerGrid.width) * \(threadsPerTGSize.width)")
            throw KeySearchError.wrongThreadNumber
        }
        
        return (threadsPerTGSize, threadgroupsPerGrid)
    }
    
    
    public static func hex256ToLittleEndianLimbs(_ hex: String) -> [UInt32]? {
        // Normalize: remove "0x" prefix and lowercase
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
                          .replacingOccurrences(of: "0x", with: "")
                          .lowercased()
        
        // Must be exactly 64 hex chars (256 bits)
        guard cleaned.count == 64 else {
            print("Error: Hex string must be exactly 64 hex characters (256 bits).")
            return nil
        }

        // Convert to bytes (big-endian hex string)
        var bytes = [UInt8]()
        bytes.reserveCapacity(32)

        var idx = cleaned.startIndex
        for _ in 0..<32 {
            let next = cleaned.index(idx, offsetBy: 2)
            guard let byte = UInt8(cleaned[idx..<next], radix: 16) else { return nil }
            bytes.append(byte)
            idx = next
        }

        // Now convert to 8 UInt32 limbs (little-endian)
        var limbs = [UInt32]()
        limbs.reserveCapacity(8)

        // Every 4 bytes → 1 limb, but reverse the chunks for little-endian
        for i in stride(from: 0, to: 32, by: 4) {
            let b0 = UInt32(bytes[i])
            let b1 = UInt32(bytes[i+1])
            let b2 = UInt32(bytes[i+2])
            let b3 = UInt32(bytes[i+3])
            let limb = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
            limbs.append(limb)
        }

        return limbs
    }

    

    public static func buildPipelineState(kernelFunctionName: String) throws -> MTLComputePipelineState {
        let library: MTLLibrary! = try device.makeDefaultLibrary(bundle: Bundle.module)
        guard let function = library.makeFunction(name: kernelFunctionName) else {
            fatalError("Failed to load function \(kernelFunctionName) from library")
        }
        do {
            return try device.makeComputePipelineState(function: function)
        } catch {
            fatalError("Failed to create pipeline state: \(error)")
        }
    }
    
    

    /// Generate a random 32-byte hex string between two inclusive 256-bit hex bounds
    public static func randomHex256(in range: (String, String)) -> String {
        let (startHex, endHex) = range
        
        guard let start = BInt(startHex, radix: 16),
              let end   = BInt(endHex, radix: 16),
              start < end else {
            fatalError("Invalid range")
        }
        
        let diff = end - start + 1
        
        // Random 256-bit number
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let r = BInt(bytes: bytes)
        
        // Scale into range with modulo (no infinite loop)
        let result = start + (r % diff)
        
        let randomKey = String(result.asString(radix: 16))
        let endKeyStr = end.asString(radix: 16)
        
        print("\n🔑 Generating Random Key in Range")
        print("    Range Start :  \(addTrailingZeros(key: start.asString(radix: 16), totalLength: endKeyStr.count))")
        print("    Random Key  :  \(addTrailingZeros(key: randomKey, totalLength: endKeyStr.count))")
        print("    Range End   :  \(endKeyStr)")
        
        return Helpers.addTrailingZeros(key: randomKey)
    }

    
    
    public static func addTrailingZeros(key: String, totalLength: Int = 64)-> String{
        if key.count < totalLength {
            return String(repeating: "0", count: totalLength - key.count) + key
        }
        return key
    }
    
    public static func getStorageModePrivate() -> MTLResourceOptions {
        return TEST_MODE ? .storageModeShared : .storageModePrivate
    }
}

