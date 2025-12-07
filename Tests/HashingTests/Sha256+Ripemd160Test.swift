import Metal
import Foundation
import Testing

extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}

extension Data {
    /// Initialize Data from a hexadecimal string.
    /// Example: Data(hex: "deadbeef")
    init?(hex: String) {
        let len = hex.count
        if len % 2 != 0 { return nil }

        var data = Data()
        data.reserveCapacity(len / 2)

        var index = hex.startIndex
        for _ in 0..<(len / 2) {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard nextIndex <= hex.endIndex else { return nil }
            let byteString = hex[index..<nextIndex]
            guard let byte = UInt8(byteString, radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        self = data
    }
}


// Helper: bytes -> hex string
extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}



class Sha256Ripemd160Test: TestBase{
    
   
    
    init() {
        super.init(kernelFunctionName: "test_hash160_kernel") 
    }
    
    
    @Test func runTest() throws{
        
        
        // Test pubkey (compressed)
        let pubkeyHex = "039fb8987e3cb30a1174b7d64de26347166841051854696930396502714f6bcf4b"
        let pubkey = Data(hex: pubkeyHex)!   // Add your own hex → Data helper
        let pubkeyLen = UInt32(pubkey.count)

        // Expected HASH160
        let expectedHash160 = "dc53039e721d0d4315c37786b2db113dbaf2e49e"

        
        
        // ------------------------------------------------------------
        // METAL SETUP
        // ------------------------------------------------------------
        
        let queue = device.makeCommandQueue()!
        
        // Buffers
        let pubkeyBuffer = pubkey.withUnsafeBytes { rawPtr in
            device.makeBuffer(bytes: rawPtr.baseAddress!,
                              length: pubkey.count,
                              options: [])!
        }
        
        var lenCopy = pubkeyLen
        let lenBuffer = device.makeBuffer(bytes: &lenCopy,
                                          length: MemoryLayout<UInt32>.size,
                                          options: [])!
        
        let outputBuffer = device.makeBuffer(length: MemoryLayout<UInt32>.size * 5,
                                             options: [])!
        
        // ------------------------------------------------------------
        // DISPATCH KERNEL
        // ------------------------------------------------------------
        let cmd = queue.makeCommandBuffer()!
        let encoder = cmd.makeComputeCommandEncoder()!
        encoder.setComputePipelineState(super.pipelineState)
        encoder.setBuffer(pubkeyBuffer, offset: 0, index: 0)
        encoder.setBuffer(lenBuffer, offset: 0, index: 1)
        encoder.setBuffer(outputBuffer, offset: 0, index: 2)
        
        // 1 thread only
        encoder.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
        encoder.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
        
        // ------------------------------------------------------------
        // READ RESULT
        // ------------------------------------------------------------
        let riWordsPtr = outputBuffer.contents().bindMemory(to: UInt32.self, capacity: 5)
        let riWords = (0..<5).map { riWordsPtr[$0] }
        
        // Convert 5×UInt32 → 20 bytes (little-endian per RIPEMD-160 spec)
        var hash160Bytes = [UInt8]()
        hash160Bytes.reserveCapacity(20)
        
        for w in riWords {
            hash160Bytes.append(UInt8(w & 0xff))
            hash160Bytes.append(UInt8((w >> 8) & 0xff))
            hash160Bytes.append(UInt8((w >> 16) & 0xff))
            hash160Bytes.append(UInt8((w >> 24) & 0xff))
        }
        
        let hash160Hex = Data(hash160Bytes).hex
        print("GPU HASH160 = \(hash160Hex)")
        print("EXPECTED    = \(expectedHash160)")
        
        assert(hash160Hex == expectedHash160)
        
    }
}
