import Foundation
import Metal
import Dispatch

struct RIPEMD160 {
    static func run(on device: MTLDevice) {
        print("Running RIPEMD-160 benchmark...")
        
        // Host for ripemd160_fixed32_kernel
        // - Packs N messages, each exactly 32 bytes (if you have shorter strings, left-pad or right-pad them on the host)
        // - Dispatches GPU kernel and reads back 5 uint words per message.
        // - Converts words to canonical RIPEMD-160 hex (little-endian word order).
        // - Measures GPU execution time for benchmarking.
        

        
        // Convert 5 UInt32 words (as written by kernel) into canonical 20-byte hex string.
        // The kernel produces words in host-endian uints (native endianness). RIPEMD-160 digest bytes are defined
        // as the little-endian concatenation of the 5 32-bit words. So we take each UInt32 and write its bytes LE -> hex.
        func ripemdWordsToHex(_ words: [UInt32]) -> String {
            var bytes: [UInt8] = []
            bytes.reserveCapacity(20)
            for w in words {
                let le = w.littleEndian
                bytes.append(UInt8((le >> 0) & 0xff))
                bytes.append(UInt8((le >> 8) & 0xff))
                bytes.append(UInt8((le >> 16) & 0xff))
                bytes.append(UInt8((le >> 24) & 0xff))
            }
            return bytes.map { String(format: "%02x", $0) }.joined()
        }
        
        // Prepare N 32-byte messages (for benchmark: random or derived from strings)
        func prepareMessages(count: Int) -> Data {
            var d = Data(capacity: count * 32)
            // Example: generate deterministic pseudorandom messages for reproducible benchmarks
            var rng: UInt64 = 0xC0FFEE12345678
            for _ in 0..<count {
                var chunk = [UInt8](repeating: 0, count: 32)
                for i in 0..<32 {
                    // simple xorshift-ish pseudo-randomness
                    rng ^= rng << 13
                    rng ^= rng >> 7
                    rng ^= rng << 17
                    chunk[i] = UInt8(truncatingIfNeeded: rng & 0xFF)
                }
                d.append(contentsOf: chunk)
            }
            return d
        }
        
        // Convenience: create small test messages (pad or truncate to 32 bytes)
        func dataFromStringFixed32(_ s: String) -> Data {
            var d = Data(s.utf8)
            if d.count > 32 {
                d = d.subdata(in: 0..<32)
            } else if d.count < 32 {
                // pad with zero bytes (you may choose different padding)
                d.append(Data(repeating: 0, count: 32 - d.count))
            }
            return d
        }
        
        // ====== Main ======
        
      
        print("Using Metal device:", device.name)
        
        
        
        var library: MTLLibrary! = try? device.makeDefaultLibrary(bundle: Bundle.module)
        
        // If you prefer to compile shader from source at runtime, you can use device.makeLibrary(source:options:).
        // This example assumes SHA256.metal is compiled into app bundle (add file to Xcode target).
        guard let function = library.makeFunction(name: "ripemd160_fixed32_kernel") else {
            fatalError("Failed to load function ripemd160_fixed32_kernel from library")
        }
        
        
        
        let pipeline: MTLComputePipelineState
        do {
            pipeline = try device.makeComputePipelineState(function: function)
        } catch {
            fatalError("Failed to create pipeline state: \(error)")
        }
        let queue = device.makeCommandQueue()!
        
        // Number of messages to benchmark
        let messageCount = 1_000_000 // adjust as needed for your GPU memory and desired runtime
        let messagesData = prepareMessages(count: messageCount)
        
        // Create Metal buffers
        let messagesBuffer = device.makeBuffer(bytes: (messagesData as NSData).bytes, length: messagesData.count, options: [])!
        
        // output: 5 uints per message
        let outWordCount = messageCount * 5
        let outBuffer = device.makeBuffer(length: outWordCount * MemoryLayout<UInt32>.stride, options: .storageModeShared)!
        
        // small numMessages buffer (because Metal disallows scalar [[buffer]]).
        var numMessages: UInt32 = UInt32(messageCount)
        let numMessagesBuffer = device.makeBuffer(bytes: &numMessages, length: MemoryLayout<UInt32>.stride, options: [])!
        
        // Dispatch configuration: choose a reasonable threadgroup size
        let preferredTgSize = min(64, pipeline.maxTotalThreadsPerThreadgroup)
        let threadsPerGrid = MTLSize(width: messageCount, height: 1, depth: 1)
        let threadsPerThreadgroup = MTLSize(width: preferredTgSize, height: 1, depth: 1)
        
        // Build and dispatch
        guard let cmdBuf = queue.makeCommandBuffer(),
              let encoder = cmdBuf.makeComputeCommandEncoder() else {
            fatalError("Failed to create command encoder")
        }
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(messagesBuffer, offset: 0, index: 0)
        encoder.setBuffer(outBuffer, offset: 0, index: 1)
        encoder.setBuffer(numMessagesBuffer, offset: 0, index: 2)
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
        
        let start = CFAbsoluteTimeGetCurrent()
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
        let end = CFAbsoluteTimeGetCurrent()
        let elapsed = end - start
        let mbProcessed = Double(messageCount * 32) / (1024.0*1024.0)
        let hashesPerSec = Double(messageCount) / elapsed
        print(String(format: "GPU elapsed: %.4f s — %0.2f MB processed — %.0f hashes/s", elapsed, mbProcessed, hashesPerSec))
        
        // Read back a few sample results for verification
        let outPtr = outBuffer.contents().bindMemory(to: UInt32.self, capacity: outWordCount)
        for i in 0..<5 {
            let base = i * 5
            var words: [UInt32] = []
            for j in 0..<5 {
                words.append(outPtr[base + j])
            }
            let hex = ripemdWordsToHex(words)
            print("Sample[\(i)] -> \(hex)")
        }
        

        
        // Example of printing a single RIPEMD-160 for a human string padded to 32 bytes
        let exampleData = dataFromStringFixed32("abc") // padded to 32 bytes
        let exampleOffset = 0 // if you want to place at index 0
        
        print("RES: \(exampleData.hex)")
        // (This example program uses prepared deterministic random messages; to test known values,
        // craft the messagesData such that message 0 equals exampleData, then rerun.)
        
        print("Done.")
    }
}
