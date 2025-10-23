import Foundation
import Metal
import Dispatch

class RIPEMD160 {
    
    
    
    let pipeline: MTLComputePipelineState
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    
    
    init(on device: MTLDevice){
        self.device = device
        let library: MTLLibrary! = try? device.makeDefaultLibrary(bundle: Bundle.module)
        
        // If you prefer to compile shader from source at runtime, you can use device.makeLibrary(source:options:).
        // This example assumes XXX.metal is compiled into app bundle (add file to Xcode target).
        guard let function = library.makeFunction(name: "ripemd160_fixed32_kernel") else {
            fatalError("Failed to load function ripemd160_fixed32_kernel from library")
        }
        do {
            self.pipeline = try device.makeComputePipelineState(function: function)
        } catch {
            fatalError("Failed to create pipeline state: \(error)")
        }
        commandQueue = device.makeCommandQueue()!
        
    }
    
    
    
    
    
    
    
    func run(inputData: Data) {
        print("Running RIPEMD-160 benchmark...")
        
        // Host for ripemd160_fixed32_kernel
        // - Packs N messages, each exactly 32 bytes (if you have shorter strings, left-pad or right-pad them on the host)
        // - Dispatches GPU kernel and reads back 5 uint words per message.
        // - Converts words to canonical RIPEMD-160 hex (little-endian word order).
        // - Measures GPU execution time for benchmarking.
        
        print("Using Metal device:", device.name)
      
        let queue = device.makeCommandQueue()!
        
        // test messages confirmed to work
        //let messageCount = 2 // adjust as needed for your GPU memory and desired runtime
        //var messagesData = UInt256(hexString: "22a3c85609d4d626bc01cd87df71d01f6bb9a62efce214d37b0d4faf4f3ebb74").data  // Str Hex values length 32 This is what I need but from bytes
        //messagesData.append(Data("xyzaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".utf8)) // other example with Direct String hashing (length 32)
        ////let messagesData = prepareMessages(count: messageCount)
        
        let messageCount = 10
        let messagesData = inputData
        
        
        
        
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
        for i in 0..<messageCount {
            let base = i * 5
            var words: [UInt32] = []
            for j in 0..<5 {
                words.append(outPtr[base + j])
            }
            let hex = ripemdWordsToHex(words)
            print("Sample[\(i)] -> RIPEMD: \(hex)")
        }
        

        // (This example program uses prepared deterministic random messages; to test known values,
        // craft the messagesData such that message 0 equals exampleData, then rerun.)
        
        print("Done.")
    }
    
    
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
    
  
    
}
