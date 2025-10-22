import Foundation
import Metal


struct SHA256gpu {
    static func run(on device: MTLDevice, iterations: Int) {
        print("Running SHA-256 benchmark...")
        
        // === Configuration ===
        let maxMessages = 1_000_000 // not used directly — dynamic
        let device = MTLCreateSystemDefaultDevice()!
        print("Using device: \(device.name)")
        
        guard let library = try? device.makeDefaultLibrary(bundle: .main) else {
            // Fallback: try to load library from the .metal file via source
            fatalError("Failed to make default library. If you run from command line, add the .metal file to a compiled target or use Xcode.")
        }
        
        // If you prefer to compile shader from source at runtime, you can use device.makeLibrary(source:options:).
        // This example assumes SHA256.metal is compiled into app bundle (add file to Xcode target).
        
        guard let function = library.makeFunction(name: "sha256_batch_kernel") else {
            fatalError("Failed to load function sha256_batch_kernel from library")
        }
        
        let pipeline: MTLComputePipelineState
        do {
            pipeline = try device.makeComputePipelineState(function: function)
        } catch {
            fatalError("Failed to create pipeline state: \(error)")
        }
        let commandQueue = device.makeCommandQueue()!
        
        // Helper: pack several messages into a single byte buffer and meta array
        struct MsgMeta {
            var offset: UInt32
            var length: UInt32
        }
        
        func packMessages(_ messages: [Data]) -> (Data, [MsgMeta]) {
            var raw = Data()
            var metas: [MsgMeta] = []
            for msg in messages {
                let offset = UInt32(raw.count)
                metas.append(MsgMeta(offset: offset, length: UInt32(msg.count)))
                raw.append(msg)
            }
            return (raw, metas)
        }
        
        // Convert output words (uint32) to hex string (big-endian per SHA-256 spec)
        func hashWordsToHex(_ words: [UInt32]) -> String {
            // SHA-256 words are stored as big-endian words in the algorithm; the kernel computed in uint (host little-endian).
            // We need to print each word as big-endian bytes in hex.
            let beBytes: [UInt8] = words.flatMap { w -> [UInt8] in
                let be = w.bigEndian
                return [
                    UInt8((be >> 24) & 0xff),
                    UInt8((be >> 16) & 0xff),
                    UInt8((be >> 8) & 0xff),
                    UInt8(be & 0xff)
                ]
            }
            return beBytes.map { String(format: "%02x", $0) }.joined()
        }
        
        
        
        
        // Example usage: hash some strings
        var testStrings = [String]()
        let range = ClosedRange(uncheckedBounds: (lower: 0, upper: iterations))
        for item in range {
            testStrings.append("Some text \(item)")
            //let data = Data("Some text \(item)".utf8)
        }
        let messages = testStrings.map { Data($0.utf8) }
            
            
        let (messageBytes, metas) = packMessages(messages)
        
        // Create buffers
        let messageBuffer = device.makeBuffer(bytes: (messageBytes as NSData).bytes, length: messageBytes.count, options: [])!
        
        var metaCpy = metas // copy to mutable
        let metaBuffer = device.makeBuffer(bytes: &metaCpy, length: MemoryLayout<MsgMeta>.stride * metaCpy.count, options: [])!
        
        // Output buffer: uint (32bit) * 8 words per message
        let outWordCount = metas.count * 8
        let outBuffer = device.makeBuffer(length: outWordCount * MemoryLayout<UInt32>.stride, options: [])!
        
        // numMessages buffer (we pass it as a small uniform buffer)
        var numMessagesUInt32 = UInt32(metas.count)
        let numMessagesBuffer = device.makeBuffer(bytes: &numMessagesUInt32, length: MemoryLayout<UInt32>.stride, options: [])!
        
        // encode command
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            fatalError("Failed to create command encoder")
        }
        
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(messageBuffer, offset: 0, index: 0)
        encoder.setBuffer(metaBuffer, offset: 0, index: 1)
        encoder.setBuffer(outBuffer, offset: 0, index: 2)
        encoder.setBuffer(numMessagesBuffer, offset: 0, index: 3)
        
        // dispatch: 1 thread per message
        let threadsPerThreadgroup = MTLSize(width: pipeline.maxTotalThreadsPerThreadgroup, height: 1, depth: 1)
        let threadgroups = MTLSize(width: (metas.count + threadsPerThreadgroup.width - 1) / threadsPerThreadgroup.width,
                                   height: 1,
                                   depth: 1)
        let threadsPerGrid = MTLSize(width: metas.count, height: 1, depth: 1)
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
        
        let start = CFAbsoluteTimeGetCurrent()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        let end = CFAbsoluteTimeGetCurrent()
        print(String(format: "SHA256 on GPU took: %.4f s", end - start))
        
        // Read results
        /*
        let outPtr = outBuffer.contents().assumingMemoryBound(to: UInt32.self)
        for i in 0..<metas.count {
            var words: [UInt32] = []
            for j in 0..<8 {
                let w = outPtr[i*8 + j].bigEndian // convert to big-endian for correct hex order
                words.append(w)
            }
            let hex = hashWordsToHex(words)
            //print("Message[\(i)] '\(testStrings[i])' -> \(hex)")
        }
         */
        
        
    }
}
