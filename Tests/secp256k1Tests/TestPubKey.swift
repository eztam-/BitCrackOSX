import Metal
import Foundation
import keysearch
import Testing
import P256K
import BigNumber

final class Secp256k1Tests: TestBase {

    init() {
        super.init(kernelFunctionName: "test_field_sub") // dummy
    }

    func cpuCalculateExpectedPublicKey(privKey: BInt, compressed: Bool) -> String {
        if compressed {
            let privateKey = try! P256K.Signing.PrivateKey(
                dataRepresentation: privKeyToData(privKey: privKey),
                format: .compressed
            )
            return privateKey.publicKey.dataRepresentation.hexString.lowercased()
        } else {
            let privateKey = try! P256K.Signing.PrivateKey(
                dataRepresentation: privKeyToData(privKey: privKey),
                format: .uncompressed
            )
            return privateKey.publicKey.dataRepresentation.hexString.lowercased()
        }
    }

@Test func testGPUKeyGenerationMatchesCPU() throws {

        // Small test values
        let batchSize     = 64       // number of threads
        let keysPerThread = 16       // keys per thread
        let compressed    = true
        let pubKeyLength  = compressed ? 33 : 65

        let startKeyHex = Helpers.generateRandom256BitHex()

        let secp = try Secp256k1(
            on: device,
            batchSize: batchSize,
            keysPerThread: keysPerThread,
            compressed: compressed,
            startKeyHex: startKeyHex
        )

        // Step 1: Initialize base points
        secp.initializeBasePoints()

        // Step 2: Run GPU once
        let commandQueue = device.makeCommandQueue()!
        let cmd = commandQueue.makeCommandBuffer()!
        secp.appendCommandEncoder(commandBuffer: cmd)
        cmd.commit()
        cmd.waitUntilCompleted()

        // Step 3: Read GPU public keys
        let gpuBuf = secp.getPublicKeyBuffer()
        let totalKeys = batchSize * keysPerThread

        var gpuHexKeys: [String] = []
        gpuHexKeys.reserveCapacity(totalKeys)

        for i in 0..<totalKeys {
            let ptr = gpuBuf.contents().advanced(by: i * pubKeyLength)
            let raw = UnsafeBufferPointer(
                start: ptr.assumingMemoryBound(to: UInt8.self),
                count: pubKeyLength
            )
            let hex = raw.map { String(format: "%02x", $0) }.joined()
            gpuHexKeys.append(hex.lowercased())
        }

        // ---- Correct scalar sequence ----
        // We *know* the starting scalar from startKeyHex:
        let startKeyBig = BInt(startKeyHex, radix: 16)!

        // Step 4: Compute CPU-side expected public keys with correct mapping
        var cpuHexKeys: [String] = []
        cpuHexKeys.reserveCapacity(totalKeys)

        for pubIndex in 0..<totalKeys {
            // Decode buffer index → (threadIdx, keyRow)
            let threadIdx = pubIndex % batchSize
            let keyRow    = pubIndex / batchSize       // integer division

            // Same formula as in your bloom-filter code:
            // offsetWithinBatch = threadIdx * KEYS_PER_THREAD + keyRow
            let offsetWithinBatch = threadIdx * keysPerThread + keyRow

            let scalar = startKeyBig + BInt(offsetWithinBatch)

            let expected = cpuCalculateExpectedPublicKey(
                privKey: scalar,
                compressed: compressed
            )
            cpuHexKeys.append(expected)
        }

        // Step 5: Compare and print scalar on failure
        for pubIndex in 0..<totalKeys {
            let threadIdx = pubIndex % batchSize
            let keyRow    = pubIndex / batchSize
            let offsetWithinBatch = threadIdx * keysPerThread + keyRow
            let scalar = startKeyBig + BInt(offsetWithinBatch)

            var privHex = scalar.asString(radix: 16)
            if privHex.count < 64 {
                privHex = String(repeating: "0", count: 64 - privHex.count) + privHex
            }

            assert(
                gpuHexKeys[pubIndex] == cpuHexKeys[pubIndex],
                """
                ❌ Mismatch at index \(pubIndex)
                   threadIdx=\(threadIdx), keyRow=\(keyRow), offset=\(offsetWithinBatch)

                   Private Key (hex BE):
                       \(privHex)

                   GPU Public Key:
                       \(gpuHexKeys[pubIndex])

                   Expected CPU Public Key:
                       \(cpuHexKeys[pubIndex])
                """
            )
 
        }
        print("✅ \(totalKeys) keys passed")
    }

    func privKeyToData(privKey: BInt) -> Data {
        // Convert to hex (without 0x)
        var hex = privKey.asString(radix: 16)

        // Pad to 64 hex characters (32 bytes)
        if hex.count < 64 {
            hex = String(repeating: "0", count: 64 - hex.count) + hex
        }

        // Ensure length is exactly 64 (32 bytes)
        if hex.count > 64 {
            fatalError("Private key larger than 256 bits: \(hex)")
        }

        // Convert padded hex to Data
        var data = Data(capacity: 32)
        var index = hex.startIndex

        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            let byteStr = hex[index..<nextIndex]
            let byte = UInt8(byteStr, radix: 16)!
            data.append(byte)
            index = nextIndex
        }

        return data   // big-endian 32-byte data
    }
}
