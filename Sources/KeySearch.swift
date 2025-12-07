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
    let pubKeyBatchSize: Int //=  Helpers.PUB_KEY_BATCH_SIZE // Number of public keys generated per batch
    let ui: UI
    let startKeyHex: String
    var startKey: BInt
    let keyIncrement: BInt
    let totalPoints: UInt32
    
    
    public init(bloomFilter: BloomFilter, database: DB, outputFile: String, startKeyHex: String) {
        self.bloomFilter = bloomFilter
        self.db = database
        self.outputFile = outputFile
        self.startKeyHex = startKeyHex
        self.startKey = BInt(startKeyHex, radix: 16)!
        self.totalPoints = UInt32(Properties.TOTAL_POINTS)
        self.pubKeyBatchSize = Int(Properties.TOTAL_POINTS)
        self.keyIncrement = BInt(pubKeyBatchSize)
        self.ui = UI(batchSize: self.pubKeyBatchSize, startKeyHex: startKeyHex)
        
        // Initialize ring buffer with MTLBuffers
        slots = (0..<maxInFlight).map { _ in
            let resultBuffer = device.makeBuffer(
                length: Int(totalPoints) * MemoryLayout<UInt32>.stride, // TODO why uint? it is bool??? FIXME
                options: [.storageModeShared]
            )!
            
            let ripemd160Buffer = device.makeBuffer(
                length: Int(totalPoints) * 5 * MemoryLayout<UInt32>.stride,   // 20 bytes per hash
                options: [.storageModeShared]
            )!
            
            return BatchSlot(
                bloomFilterOutBuffer: resultBuffer,
                ripemd160OutBuffer: ripemd160Buffer,
            )
        }
        
    }
    
    func run() throws {
    
  
        let commandQueue = device.makeCommandQueue()!
        let keyLength = 33
        let secp256k1 = try BitcrackMetalEngine(on:  device, compressed: Properties.compressedKeySearch, startKeyHex: startKeyHex)
        
        // 1. Allocate point set

        
        let pointSet = secp256k1.makePointSet(totalPoints: totalPoints, gridSize: Properties.GRID_SIZE)
       
        
        let startKeyLE =  Helpers.hex256ToUInt32Limbs(startKeyHex)
       
        ui.startLiveStats()
        
        
        try secp256k1.runInitKernel(pointSet: pointSet, startKeyLE: startKeyLE, commandBuffer: commandQueue.makeCommandBuffer()!)
        
        
        dumpPoint(0, pointSet: pointSet)
        // 3. Now you can repeatedly step:
        for batchCount in 1..<Int.max{ // TODO
            
            let batchStartNS = DispatchTime.now().uptimeNanoseconds
            let slotIndex = batchCount % maxInFlight
            let slot = slots[slotIndex]
            slot.semaphore.wait()
            
            
            let commandBuffer = commandQueue.makeCommandBuffer()!

            try secp256k1.appendStepKernel(pointSet: pointSet, commandBuffer: commandBuffer,bloomFilter: bloomFilter,
                                           bloomFilterResultBuffer: slot.bloomFilterOutBuffer,
                                           hash160OutBuffer: slot.ripemd160OutBuffer)

            
            // --- Async CPU callback when GPU finishes this batch ---
            commandBuffer.addCompletedHandler { [weak self] _ in
                   // Theres no guarantee that CompletedHandlers are executed in the same order of submission (despite the command buffers are always executed in sequence)
                   // So we cannot increment the base key from here
                   
                   let falsePositiveCnt = self!.checkBloomFilterResults(resultBuffer: slot.bloomFilterOutBuffer,ripemd160Buffer: slot.ripemd160OutBuffer, batchCount: batchCount )
                   self!.ui.bfFalePositiveCnt = falsePositiveCnt
                   slot.semaphore.signal()
            }
            
            
            commandBuffer.commit()
            //commandBuffer.waitUntilCompleted()
            
            // TMP DEBUG
            //dumpPoint(0, pointSet: pointSet)
            //var pubKeyHash = [UInt8](repeating: 0, count: 20)
            //memcpy(&pubKeyHash, slots[0].ripemd160OutBuffer.contents().advanced(by: 0 * 20), 20)
            //let pubKeyHashHex = Data(pubKeyHash).hexString
            //print("HASH160: \(pubKeyHashHex)")
            // END TMP DEBUG

            
            
            
            //checkBloomFilterResults(resultBuffer: slots[0].bloomFilterOutBuffer, ripemd160Buffer: slots[0].ripemd160OutBuffer, batchCount: batchCount)

            let batchEndNS = DispatchTime.now().uptimeNanoseconds
                    
             // TODO make this async
             ui.updateStats(
                 totalStartTime: batchStartNS,
                 totalEndTime: batchEndNS,
                 batchCount: batchCount
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

        
        for i in 0..<pubKeyBatchSize {
            
            if bfResults[i] {
               
                // Read 20-byte RIPEMD160 for this pub key
                var pubKeyHash = [UInt8](repeating: 0, count: 20)
                memcpy(&pubKeyHash, ripemd160Buffer.contents().advanced(by: i * 20), 20)
                let pubKeyHashHex = Data(pubKeyHash).hexString
                let addresses = try! db.getAddresses(for: pubKeyHashHex)
                
                
                if addresses.isEmpty {
                    falsePositiveCnt += 1
                } else {
                    
                    
                    
                    
                    let privKeyHex =  "TODO: IMPLEMENT ME"
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
            
            /*
            // key "row"
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
             */
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
    
    
    func dumpPoint(_ index: Int, pointSet: BitcrackMetalEngine.PointSet) {
        let xPtr = pointSet.xBuffer.contents()
            .bindMemory(to: BitcrackMetalEngine.UInt256.self, capacity: Int(pointSet.totalPoints))

        let yPtr = pointSet.yBuffer.contents()
            .bindMemory(to: BitcrackMetalEngine.UInt256.self, capacity: Int(pointSet.totalPoints))

        let x = xPtr[index]
        let y = yPtr[index]

        //Helpers.printLimbs(limbs: [x.limbs.0,x.limbs.1,x.limbs.2,x.limbs.3,x.limbs.4,x.limbs.5,x.limbs.6,x.limbs.7] )
        
    
        
        print("Public Key Point[\(index)] X=\(uint256ToHex2(x)) Y=\(uint256ToHex2(y))")
    }
    
    
    
    func uint256ToHex(leLimbs: [UInt32]) -> String {
        precondition(leLimbs.count == 8)
        var s = ""
        for i in (0..<8).reversed() {           // MS limb first
            s += String(format: "%08x", leLimbs[i])
        }
        return s
    }
    
    
    func uint256ToHex2(_ v:  BitcrackMetalEngine.UInt256) -> String {
        let arr = [v.limbs.0, v.limbs.1, v.limbs.2, v.limbs.3,
                   v.limbs.4, v.limbs.5, v.limbs.6, v.limbs.7]
        return arr.reversed().map { String(format: "%08x", $0) }.joined()
    }

    func limbsToHex(_ v: BitcrackMetalEngine.UInt256) -> String {
        let limbs = [v.limbs.0, v.limbs.1, v.limbs.2, v.limbs.3,
                     v.limbs.4, v.limbs.5, v.limbs.6, v.limbs.7]

        // limbs[0] = least significant → move to the end
        var bytes: [UInt8] = []

        for limb in limbs.reversed() {   // reverse to big-endian word order
            bytes.append(UInt8((limb >> 24) & 0xFF))
            bytes.append(UInt8((limb >> 16) & 0xFF))
            bytes.append(UInt8((limb >>  8) & 0xFF))
            bytes.append(UInt8((limb      ) & 0xFF))
        }

        return bytes.map { String(format:"%02x", $0) }.joined()
    }

    
  
    }

    


