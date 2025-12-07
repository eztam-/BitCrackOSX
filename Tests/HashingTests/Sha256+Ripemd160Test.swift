import Testing
import Metal
import CryptoKit   // For SHA256
// Add your own RIPEMD160 implementation (CryptoKit doesn't include it)

final class HashKernelTests: TestBase {

   
    
    init() {
        super.init(kernelFunctionName: "test_hash_kernel")
    }
    
    

    @Test func testBitCrackHashKernel() throws {

        //----------------------------------------------------------------------
        // 1. Create a known compressed public key for testing
        //    This is a real Bitcoin compressed pubkey.
        //----------------------------------------------------------------------
        let pubkeyHex = "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
        let pubkeyBytes = Array<UInt8>(hex: pubkeyHex)
        

        //----------------------------------------------------------------------
        // 2. Build buffers
        //----------------------------------------------------------------------
        let pubkeyBuf = device.makeBuffer(bytes: pubkeyBytes,
                                          length: 33,
                                          options: [])!

        let shaBuf    = device.makeBuffer(length: 8 * MemoryLayout<UInt32>.size, options: [])!
        let rmdTmpBuf = device.makeBuffer(length: 5 * MemoryLayout<UInt32>.size, options: [])!
        let hashBuf   = device.makeBuffer(length: 5 * MemoryLayout<UInt32>.size, options: [])!


        //----------------------------------------------------------------------
        // 4. Encode dispatch
        //----------------------------------------------------------------------
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let encoder = commandBuffer.makeComputeCommandEncoder()!

        encoder.setComputePipelineState(super.pipelineState)
        encoder.setBuffer(pubkeyBuf, offset: 0, index: 0)
        encoder.setBuffer(shaBuf,    offset: 0, index: 1)
        encoder.setBuffer(rmdTmpBuf, offset: 0, index: 2)
        encoder.setBuffer(hashBuf,   offset: 0, index: 3)

        let threads = MTLSize(width: 1, height: 1, depth: 1)
        encoder.dispatchThreads(threads,
            threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))

        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        //----------------------------------------------------------------------
        // 5. CPU Reference Hash160 (Bitcoin Standard)
        //----------------------------------------------------------------------
        // CPU SHA256

        //----------------------------------------------------------------------
        // 6. Read GPU output
        //----------------------------------------------------------------------
        let gpuWords = hashBuf.contents().bindMemory(to: UInt32.self,
                                                     capacity: 5)
        var gpuBytes = Data()
        for i in 0..<5 {
            let w = gpuWords[i]
            // BitCrack’s final output uses endian()
            gpuBytes.append(contentsOf: [
                UInt8((w >> 24) & 0xff),
                UInt8((w >> 16) & 0xff),
                UInt8((w >> 8)  & 0xff),
                UInt8((w      ) & 0xff),
            ])
        }

        //----------------------------------------------------------------------
        // 7. Compare CPU and GPU results
        //----------------------------------------------------------------------
        let expected = "751e76e8199196d454941c45d1b3a323f1433bd6"
        print("GPU HASH160 :", gpuBytes.hexString)
        print("Expected    :", expected)

        assert(gpuBytes.hexString == expected)
    }
}

//
// Helper: Hex decode
//
extension Array where Element == UInt8 {
    init(hex: String) {
        self = []
        var buffer: UInt8?
        for c in hex {
            guard let v = c.hexDigitValue else { continue }
            if let b = buffer {
                self.append(UInt8(b << 4) | UInt8(v))
                buffer = nil
            } else {
                buffer = UInt8(v)
            }
        }
    }
}

//
// Helper: Data → hex string
//

