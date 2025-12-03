import Foundation
import Metal
import BigNumber

// TODO: FIXME: If the key range is smaller than the batch size it doesnt work
// TODO: If the size is smaller, that we run into a memory leak since the garbage collector seem to slow, to free up the memory for the commandBuffers

class KeySearch {

    let maxInFlight = 3  // triple buffering
    struct BatchSlot {
        let bloomFilterOutBuffer: MTLBuffer        // bloom filter results (raw)
        let ripemd160OutBuffer: MTLBuffer          // RIPEMD160 output for that batch
        let semaphore = DispatchSemaphore(value: 1)
    }
    var slots: [BatchSlot] = []
    let bloomFilter: BloomFilter
    let db: DB
    let outputFile: String
    let device = Helpers.getSharedDevice()
    let privKeyBatchSize = Helpers.PRIV_KEY_BATCH_SIZE // Number of base private keys per batch (number of total threads in grid)
    let pubKeyBatchSize =  Helpers.PUB_KEY_BATCH_SIZE // Number of public keys generated per batch
    let ui: UI
    let startKeyHex: String
    var startKey: BInt
    let keyIncrement: BInt
    
    public init(bloomFilter: BloomFilter, database: DB, outputFile: String, startKeyHex: String) {
        self.bloomFilter = bloomFilter
        self.db = database
        self.outputFile = outputFile
        self.ui = UI(batchSize: self.pubKeyBatchSize, startKeyHex: startKeyHex)
        self.startKeyHex = startKeyHex
        self.startKey = BInt(startKeyHex, radix: 16)!
        self.keyIncrement = BInt(pubKeyBatchSize)


        // Initialize ring buffer with MTLBuffers
        slots = (0..<maxInFlight).map { _ in
            let resultBuffer = device.makeBuffer(
                length: pubKeyBatchSize * MemoryLayout<UInt32>.stride, // TODO why uint? it is bool??? FIXME
                options: [.storageModeShared]
            )!
            
            let ripemd160Buffer = device.makeBuffer(
                length: pubKeyBatchSize * 5 * MemoryLayout<UInt32>.stride,   // 20 bytes per hash
                options: [.storageModeShared]
            )!
            
            return BatchSlot(
                bloomFilterOutBuffer: resultBuffer,
                ripemd160OutBuffer: ripemd160Buffer,
            )
        }
        
    }
    
    func run() throws {
        
        //let startKey = "0000000000000000000000000000000000000000000000000001000000000000"
        
        let commandQueue = device.makeCommandQueue()!
        let keyLength = Properties.compressedKeySearch ? 33 : 65 //   keyLength:  33 = compressed;  65 = uncompressed
        
        let secp256k1 = try Secp256k1(on:  device, batchSize: privKeyBatchSize, keysPerThread: Properties.KEYS_PER_THREAD, compressed: Properties.compressedKeySearch, startKeyHex: startKeyHex)
        let sha256 = try Hashing(on: device, batchSize: pubKeyBatchSize, inputBuffer: secp256k1.getPublicKeyBuffer(), keyLength: UInt32(keyLength))
       // let ripemd160 = try RIPEMD160(on: device, batchSize: pubKeyBatchSize, inputBuffer: sha256.getOutputBuffer())
        // TODO Initialize the bloomfilter from here
        
    
        try secp256k1.initializeBasePoints()

        let ui = self.ui
        ui.startLiveStats()
        var batchIndex = 0 // TODO: Could overrun

        while true {
            let batchStartNS = DispatchTime.now().uptimeNanoseconds
            let slotIndex = batchIndex % maxInFlight
            let slot = slots[slotIndex]
            slot.semaphore.wait()
            
            let commandBuffer = commandQueue.makeCommandBuffer()!
            secp256k1.appendCommandEncoder(commandBuffer: commandBuffer)
            sha256.appendCommandEncoder(commandBuffer: commandBuffer, resultBuffer: slot.ripemd160OutBuffer)
           // ripemd160.appendCommandEncoder(commandBuffer: commandBuffer, resultBuffer: slot.ripemd160OutBuffer)
            bloomFilter.appendCommandEncoder(commandBuffer: commandBuffer, inputBuffer: slot.ripemd160OutBuffer, resultBuffer: slot.bloomFilterOutBuffer) // TODO: make this consistent and move inputBuffer to constructor once refactored
            
            // Snapshot the batch index for THIS batch
             let thisBatchIndex = batchIndex
            
            // --- Async CPU callback when GPU finishes this batch ---
            commandBuffer.addCompletedHandler { [weak self] _ in
                // Theres no guarantee that CompletedHandlers are executed in the same order of submission (despite the command buffers are always executed in sequence)
                // So we cannot increment the base key from here
                
                let falsePositiveCnt = self!.checkBloomFilterResults(resultBuffer: slot.bloomFilterOutBuffer,ripemd160Buffer: slot.ripemd160OutBuffer, batchCount: thisBatchIndex )
                self!.ui.bfFalePositiveCnt = falsePositiveCnt
                slot.semaphore.signal()
            }
   
            commandBuffer.commit()  // Submit work to GPU

            batchIndex += 1
            let batchEndNS = DispatchTime.now().uptimeNanoseconds
           
            // TODO make this async
            ui.updateStats(
                totalStartTime: batchStartNS,
                totalEndTime: batchEndNS,
                batchCount: batchIndex
            )
        }
    }
    
    
    func checkBloomFilterResults(resultBuffer: MTLBuffer, ripemd160Buffer: MTLBuffer, batchCount: Int) -> Int {
        
        let resultsPtr = resultBuffer.contents().bindMemory(to: UInt32.self, capacity: pubKeyBatchSize)
        let bfResults: [Bool] = (0..<pubKeyBatchSize).map { resultsPtr[$0] != 0 }
    
        var falsePositiveCnt = 0

        // Rewind to the start key of the *current* batch.
        // init kernel: base = start + Δk
        // process kernel: base += Δk   (Δk = totalKeysPerBatch)
        // so nextBaseKey = start + 2*Δk  -> start = nextBaseKey - 2*Δk
        let startKey = startKey //+ totalKeysPerBatch + totalKeysPerBatch

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
                        let offsetWithinBatch = BInt(threadIdx) * BInt(Properties.KEYS_PER_THREAD) + BInt(i)

                        // Actual private key for this hit
                        let privKeyVal = startKey + keyIncrement * batchCount + offsetWithinBatch

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

