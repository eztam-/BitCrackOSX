import Foundation
import Metal
import BigNumber
import simd

// TODO: FIXME: If the key range is smaller than the batch size it doesnt work

let BLOOM_MAX_HITS = 100_000   // Maximum number of bloom filter hits supported per batch.

struct HitResult {
    var index: UInt32
    var hash160: (UInt32, UInt32, UInt32, UInt32, UInt32)
}

class KeySearch {

    let maxInFlight = 9  // triple buffering
    struct BatchSlot {
        let bloomFilterHitsBuffer: MTLBuffer
        let hitCountBuffer: MTLBuffer
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
            let hitsBuffer = device.makeBuffer(
                length: BLOOM_MAX_HITS * MemoryLayout<HitResult>.size,
                options: .storageModeShared
            )!
            
            let resultCount: UInt32 = 0
            let resultCountBuffer = device.makeBuffer(
                bytes: [resultCount],
                length: MemoryLayout<UInt32>.size,
                options: .storageModeShared
            )!
            
            return BatchSlot(
                bloomFilterHitsBuffer: hitsBuffer,
                hitCountBuffer: resultCountBuffer
            )
        }
        
    }
    
    func run() throws {
    
        let commandQueue = device.makeCommandQueue()!
        let keySearchMetal = try KeySearchMetalHost(on:  device, compressed: Properties.compressedKeySearch, startKeyHex: startKeyHex)
        
        // 1. Allocate point set
        let pointSet = keySearchMetal.makePointSet(totalPoints: totalPoints, gridSize: Properties.GRID_SIZE)
        let startKeyLE =  Helpers.hex256ToUInt32Limbs(startKeyHex)
        ui.startLiveStats()
        try keySearchMetal.runInitKernel(pointSet: pointSet, startKeyLE: startKeyLE, commandBuffer: commandQueue.makeCommandBuffer()!)
        
        //dumpPoint(0, pointSet: pointSet)

        var appStartNS = DispatchTime.now().uptimeNanoseconds

        for batchCount in 1..<Int.max{ // TODO
            
            let batchStartNS = DispatchTime.now().uptimeNanoseconds
            let slotIndex = batchCount % maxInFlight
            let slot = slots[slotIndex]
            slot.semaphore.wait()
            
            let commandBuffer = commandQueue.makeCommandBuffer()!

            try keySearchMetal.appendStepKernel(pointSet: pointSet,
                                           commandBuffer: commandBuffer,
                                           bloomFilter: bloomFilter,
                                           bloomFilterHitsBuffer: slot.bloomFilterHitsBuffer,
                                           hitCountBuffer: slot.hitCountBuffer)

            // --- Async CPU callback when GPU finishes this batch ---
            commandBuffer.addCompletedHandler { [weak self] _ in
                // Theres no guarantee that CompletedHandlers are executed in the same order of submission (despite the command buffers are always executed in sequence)
                // So we cannot increment the base key from here
                
                let falsePositiveCnt = self!.checkBloomFilterResults(bloomFilterHitsBuffer: slot.bloomFilterHitsBuffer, hitCountBuffer: slot.hitCountBuffer, batchCount: batchCount )
      
                //if falsePositiveCnt > 0 {
                //    self!.ui.printMessage("\(falsePositiveCnt)")
                //}
                self!.ui.bfFalsePositiveCnt.append(falsePositiveCnt)
                
                // RESET BEFORE EACH DISPATCH
                slot.hitCountBuffer.contents().storeBytes(of: 0, as: UInt32.self)
                slot.semaphore.signal()
            }
            commandBuffer.commit()

            let batchEndNS = DispatchTime.now().uptimeNanoseconds
              
            // DON'T REMOVE
            // This prints a smoother longer term MKeys/s figure, for porformance testing. Let it run for 30-60! The normal measure is too jumpy and volatile
            /*
            if batchCount > maxInFlight && batchCount % maxInFlight == 0 {
                let durationSeconds = Double(batchEndNS - appStartNS) / 1_000_000_000.0
                let itemsPerSecond = Double(pubKeyBatchSize * (batchCount - maxInFlight)) / durationSeconds
                let mHashesPerSec = itemsPerSecond / 1_000_000.0
                ui.printMessage("\(mHashesPerSec) M hashes/s")
            } else if batchCount <= maxInFlight {
                appStartNS = DispatchTime.now().uptimeNanoseconds
            }
            */
            
             // TODO make this async
             ui.updateStats(
                 totalStartTime: batchStartNS,
                 totalEndTime: batchEndNS,
                 batchCount: batchCount
             )
        }
    }
    
    
    func checkBloomFilterResults(bloomFilterHitsBuffer: MTLBuffer, hitCountBuffer: MTLBuffer, batchCount: Int) -> Int {
        
        // Get bloom filter hit count
        let hitCount = hitCountBuffer.contents().load(as: UInt32.self)
        if hitCount > BLOOM_MAX_HITS {
            ui.printMessage("WARNING: Bloom filter hit count \(hitCount) exceeds maximum \(BLOOM_MAX_HITS)!")
        }
        let finalCount = Int(min(hitCount, UInt32(BLOOM_MAX_HITS)))
        
        
        let rawPtr = bloomFilterHitsBuffer.contents()
        let hitPtr = rawPtr.bindMemory(to: HitResult.self, capacity: finalCount)

        var falsePositiveCnt = 0
        
        for i in 0..<finalCount {
            let hit = hitPtr[i]
            let hash160String = digestToHexString(hit.hash160)
                        
            let addresses = try! db.getAddresses(for: hash160String)
            
            if addresses.isEmpty {
                falsePositiveCnt += 1
            } else {

                // Calculating the private key
                let batchIndex = batchCount - 1  // because hashes are for previous batch d
                let pointIndex = Int(hit.index)
                let privKeyVal = startKey + BInt(batchIndex) * BInt(Properties.TOTAL_POINTS) + BInt(pointIndex)
                

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

                ui.sendNotification( message: "\(privKeyHex)", title: "Found private key")
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
    
    func digestToHexString(_ dig: (UInt32, UInt32, UInt32, UInt32, UInt32)) -> String {
        let words = [dig.0, dig.1, dig.2, dig.3, dig.4]
        var s = ""
        
        for w in words {
            // w is already big-endian word from the GPU
            s += String(format: "%08x", w)
        }
        
        return s
    }

    
    
    func dumpPoint(_ index: Int, pointSet: KeySearchMetalHost.PointSet) {
        let xPtr = pointSet.xBuffer.contents()
            .bindMemory(to: KeySearchMetalHost.UInt256.self, capacity: Int(totalPoints))
        
        let yPtr = pointSet.yBuffer.contents()
            .bindMemory(to: KeySearchMetalHost.UInt256.self, capacity: Int(totalPoints))
        
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
    
    
    func uint256ToHex2(_ v:  KeySearchMetalHost.UInt256) -> String {
        let arr = [v.limbs.0, v.limbs.1, v.limbs.2, v.limbs.3,
                   v.limbs.4, v.limbs.5, v.limbs.6, v.limbs.7]
        return arr.reversed().map { String(format: "%08x", $0) }.joined()
    }
    
    func limbsToHex(_ v: KeySearchMetalHost.UInt256) -> String {
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

    


