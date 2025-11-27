import Foundation
import Metal
import BigNumber

// TODO: FIXME: If the key range is smaller than the batch size it doesnt work
// TODO: If the size is smaller, that we run into a memory leak since the garbage collector seem to slow, to free up the memory for the commandBuffers

class KeySearch {

    let bloomFilter: BloomFilter
    let db: DB
    let outputFile: String
    let device = Helpers.getSharedDevice()
    let privKeyBatchSize = Helpers.PRIV_KEY_BATCH_SIZE // Number of base private keys per batch (number of total threads in grid)
    let pubKeyBatchSize =  Helpers.PUB_KEY_BATCH_SIZE // Number of public keys generated per batch
    let ui: UI
    
    public init(bloomFilter: BloomFilter, database: DB, outputFile: String) {
        self.bloomFilter = bloomFilter
        self.db = database
        self.outputFile = outputFile
        self.ui = UI(batchSize: self.pubKeyBatchSize)
    }
    
    func run(startHexKey: String) throws {
        
        //let startKey = "0000000000000000000000000000000000000000000000000001000000000000"
        
        let commandQueue = device.makeCommandQueue()!
        let keyLength = Properties.compressedKeySearch ? 33 : 65 //   keyLength:  33 = compressed;  65 = uncompressed
        
        let secp256k1 = try Secp256k1(on:  device, batchSize: privKeyBatchSize, keysPerThread: Properties.KEYS_PER_THREAD, compressed: Properties.compressedKeySearch, startKeyHex: startHexKey)
        let sha256 = try SHA256(on: device, batchSize: pubKeyBatchSize, inputBuffer: secp256k1.getPublicKeyBuffer(), keyLength: UInt32(keyLength))
        let ripemd160 = try RIPEMD160(on: device, batchSize: pubKeyBatchSize, inputBuffer: sha256.getOutputBuffer())
        // TODO Initialize the bloomfilter from here
        
        
        secp256k1.initializeBasePoints()
        
        try Helpers.printGPUInfo(device: device)
        
        if Properties.verbose {
            print("                  │ Threads per TG │ TGs per Grid │ Thread Exec. Width │")
            //secp256k1.printThreadConf()
            sha256.printThreadConf()
            ripemd160.printThreadConf()
            bloomFilter.printThreadConf()
            print("")
        }
        
        let compUncomp = Properties.compressedKeySearch ? "compressed" : "uncompressed"
        print("🚀 Starting \(compUncomp) key search\n")
       
        ui.startHexKey = startHexKey
        ui.startLiveStats()
        var nextBasePrivKey = [UInt8](repeating: 0, count: 32)
        
        while true {
            
            let startTotal = DispatchTime.now()
            let commandBuffer = commandQueue.makeCommandBuffer()!
            secp256k1.appendCommandEncoder(commandBuffer: commandBuffer)
            sha256.appendCommandEncoder(commandBuffer: commandBuffer)
            ripemd160.appendCommandEncoder(commandBuffer: commandBuffer)
            bloomFilter.appendCommandEncoder(commandBuffer: commandBuffer, inputBuffer: ripemd160.getOutputBuffer()) // TODO: make this consistent and move inputBuffer to constructor once refactored
            
            
            // Submit work to GPU
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()

            let start = DispatchTime.now()
            
            
            // Get the base private key TODO: make this async
            memcpy(&nextBasePrivKey, secp256k1.getBasePrivateKeyBuffer().contents(), 32)
            
            let falsePositiveCnt = checkBloomFilterResults(
                resultBuffer: bloomFilter.getOutputBuffer(),
                nextBasePrivKey: nextBasePrivKey,
                ripemd160Buffer: ripemd160.getOutputBuffer())
          
            ui.updateStats(totalStartTime: startTotal.uptimeNanoseconds, totalEndTime: DispatchTime.now().uptimeNanoseconds, bfFalsePositiveCnt: falsePositiveCnt, nextBasePrivKey: nextBasePrivKey)

            ui.bloomFilter = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0
                
        }
    }
    
    
    func checkBloomFilterResults(resultBuffer: MTLBuffer, nextBasePrivKey: [UInt8], ripemd160Buffer: MTLBuffer) -> Int {
        
       
        let resultsPtr = resultBuffer.contents().bindMemory(to: UInt32.self, capacity: pubKeyBatchSize)
        let bfResults: [Bool] = (0..<pubKeyBatchSize).map { resultsPtr[$0] != 0 }
    
        
        
        var falsePositiveCnt = 0

        // Total number of keys produced in one batch = batchSize * KEYS_PER_THREAD
        let totalKeysPerBatch = BInt(privKeyBatchSize) * BInt(Properties.KEYS_PER_THREAD)

        // Convert GPU-updated "next base key" (after process kernel) from LE bytes to BInt
        let nextBaseKeyHex = Data(nextBasePrivKey.reversed()).hexString
        let nextBaseKey = BInt(nextBaseKeyHex, radix: 16)!

        // Rewind to the start key of the *current* batch.
        // init kernel: base = start + Δk
        // process kernel: base += Δk   (Δk = totalKeysPerBatch)
        // so nextBaseKey = start + 2*Δk  -> start = nextBaseKey - 2*Δk
        let startKey = nextBaseKey - totalKeysPerBatch - totalKeysPerBatch

        for i in 0..<Properties.KEYS_PER_THREAD {                // key "row"
            for threadIdx in 0..<privKeyBatchSize {              // thread "column"
                // New storage order (coalesced): [key][thread]
                let pubKeyIndex = i * privKeyBatchSize + threadIdx

                if bfResults[pubKeyIndex] {
                    // Read 20-byte RIPEMD160 for this pub key
                    var pubKeyHash = [UInt8](repeating: 0, count: 20)
                    memcpy(&pubKeyHash, ripemd160Buffer.contents().advanced(by: pubKeyIndex * 20), 20)
                    let pubKeyHashHex = Data(pubKeyHash).hexString
                    let addresses = try! db.getAddresses(for: pubKeyHashHex)

                    if addresses.isEmpty {
                        falsePositiveCnt += 1
                    } else {
                        // IMPORTANT: scalar offset within the batch is still thread-major
                        // offset = threadIdx * KEYS_PER_THREAD + i
                        let offsetWithinBatch = BInt(threadIdx) * BInt(Properties.KEYS_PER_THREAD) + BInt(i)

                        // Actual private key for this hit
                        let privKeyVal = startKey + offsetWithinBatch

                        var privKeyHex = privKeyVal.asString(radix: 16)
                        privKeyHex = String(repeating: "0", count: max(0, 64 - privKeyHex.count)) + privKeyHex

                        ui.printMessage(
                        """
                        --------------------------------------------------------------------------------------
                        💰 Private key found: \(privKeyHex)
                           For addresses:
                            \(addresses.map { $0.address }.joined(separator: "\n    "))
                        --------------------------------------------------------------------------------------
                        """)
                       
                        try! appendToResultFile(
                            text: "Found private key: \(privKeyHex) for addresses: \(addresses.map(\.address).joined(separator: ", ")) \n"
                        )
                    }
                }
            }
        }

        return falsePositiveCnt
    }
	
    
    func appendToResultFile(text: String) throws {
        let filePath = self.outputFile
        let url = URL(fileURLWithPath: filePath)
        if FileManager.default.fileExists(atPath: url.path) {
            let fileHandle = try FileHandle(forWritingTo: url)
            defer { fileHandle.closeFile() }
            fileHandle.seekToEndOfFile()
            if let data = text.data(using: .utf8) {
                fileHandle.write(data)
            }
        } else {
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
    
    
}









