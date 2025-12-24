import Foundation
import Metal
import BigNumber
import simd

// TODO: FIXME: If the key range is smaller than the batch size it doesnt work

// This needs to be exactly aligned with the corresponding value on host side!
// Maximum number of bloom filter hits supported per batch. To save memory we cannot make this the full size of totalPoints
public let BLOOM_MAX_HITS = 100_000


public struct HitResult {
    var index: UInt32
    var hash160: (UInt32, UInt32, UInt32, UInt32, UInt32)
}

class KeySearch {
    
    struct BatchSlot {
        let bloomFilterHitsBuffer: MTLBuffer
        let hitCountBuffer: MTLBuffer
        let semaphore = DispatchSemaphore(value: 1)
    }
    var slots: [BatchSlot] = []
    
    let bloomFilter: BloomFilter
    let device = Helpers.getSharedDevice()
    let ui: UI

    let keyIncrement: BInt
    let totalPoints: Int = Properties.TOTAL_POINTS
    let maxInFlight: Int
    let runConfig: RunConfig
    
    public init(bloomFilter: BloomFilter, runConfig: RunConfig) {
        self.runConfig = runConfig
        self.bloomFilter = bloomFilter
        self.keyIncrement = BInt(totalPoints)
        self.ui = UI(batchSize: totalPoints, runConfig: runConfig)
        self.maxInFlight = Properties.RING_BUFFER_SIZE
        
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
        let keySearchMetal = try KeySearchMetal(on:  device, compressed: Properties.compressedKeySearch, totalPoints: totalPoints, gridSize: Properties.GRID_SIZE)
        try keySearchMetal.runInitKernel(startKeyHex: runConfig.startKeyStr , commandBuffer: commandQueue.makeCommandBuffer()!)
        ui.startLiveStats()

        //dumpPoint(0, pointSet: pointSet)
        //var appStartNS = DispatchTime.now().uptimeNanoseconds
        
        var batchCount = 1  // TODO: Use larger type to avoid overrun
        while true {
            
            let batchStartNS = DispatchTime.now().uptimeNanoseconds
            let slotIndex = batchCount % maxInFlight
            let slot = slots[slotIndex]
            slot.semaphore.wait()
            
            let commandBuffer = commandQueue.makeCommandBuffer()!
            let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
            
            // To reduce CPU overhead for faster GPUs (not a problem on M1 Pro) we could submit several steps per commandEncoder.
            // This should work fine, only the MKey/s ui value would need to be calculated differnetly
            //let STEPS_PER_BATCH = 4
            //for _ in 0..<STEPS_PER_BATCH {
                //let slotIndex = batchCount % maxInFlight
                //let slot = slots[slotIndex]
                try keySearchMetal.appendStepKernel(
                    commandEncoder: commandEncoder,
                    bloomFilter: bloomFilter,
                    hitsBuffer: slot.bloomFilterHitsBuffer,
                    hitCountBuffer: slot.hitCountBuffer)
                
                addCompletionHandler(slot, batchCount, commandBuffer: commandBuffer)
               
                
            // batchCount += 1
            //}
            commandEncoder.endEncoding()
            commandBuffer.commit()
     
            let batchEndNS = DispatchTime.now().uptimeNanoseconds
            
            ui.updateStats(
                totalStartTime: batchStartNS,
                totalEndTime: batchEndNS,
                batchCount: batchCount
            )
            batchCount += 1
        }
    }
    
    fileprivate func addCompletionHandler(_ slot: KeySearch.BatchSlot, _ batchCount: Int, commandBuffer: MTLCommandBuffer) {
        
        // Async CPU callback when GPU finishes this batch
        commandBuffer.addCompletedHandler { [weak self] _ in
            // Theres no guarantee that CompletedHandlers are executed in the same order of submission (despite the command buffers are always executed in sequence)
            // So we cannot increment the base key from here
            
            let falsePositiveCnt = self!.checkBloomFilterResults(
                bloomFilterHitsBuffer: slot.bloomFilterHitsBuffer,
                hitCountBuffer: slot.hitCountBuffer,
                batchCount: batchCount
            )
            
            // TODO: It's costy doing the EMA math for each result. At the moment it seems to be still fine on M1 Pro since it is async but might become an issue.
            _ = self!.ui.bfFalsePositiveRateEma.add(Double(falsePositiveCnt))

            // RESET BEFORE EACH DISPATCH
            slot.hitCountBuffer.contents().storeBytes(of: 0, as: UInt32.self)
            
            
            if commandBuffer.status != .completed {
                print("INIT status:", commandBuffer.status.rawValue, "error:", String(describing: commandBuffer.error))
                exit(-1)
            }
            slot.semaphore.signal()
        }
    }
    
    func checkBloomFilterResults(bloomFilterHitsBuffer: MTLBuffer, hitCountBuffer: MTLBuffer, batchCount: Int) -> Int {
        
        // Get bloom filter hit count
        let hitCount: UInt32 = hitCountBuffer.contents().load(as: UInt32.self)
        if hitCount > BLOOM_MAX_HITS - 1 {
            ui.printMessage("WARNING: Bloom filter hit count \(hitCount) exceeds maximum \(BLOOM_MAX_HITS)! Uptime: \(ui.elapsedTimeString()) batchCnt: \(batchCount)" )
        }
        let finalCount = Int(min(hitCount, UInt32(BLOOM_MAX_HITS - 1)))
        
        
        let rawPtr = bloomFilterHitsBuffer.contents()
        let hitPtr = rawPtr.bindMemory(to: HitResult.self, capacity: finalCount)
        
        var falsePositiveCnt = 0
        
        for i in 0..<finalCount {
            let hit = hitPtr[i]
            let hash160String = digestToHexString(hit.hash160)
            
            let addresses = try! runConfig.db.getAddresses(for: hash160String)
            
            if addresses.isEmpty {
                falsePositiveCnt += 1
            }
            else {
                let (privKeyHex, _) = runConfig.calcCurrentKey(batchIndex: batchCount - 1, offset: Int(hit.index))
                ui.printMessage(
                    """
                    ──────────────────────────────────────────────────────────────────────────────────────
                    💰 Private key found: \(privKeyHex)
                       For addresses:
                        \(addresses.map { $0.address }.joined(separator: "\n    "))
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
        let filePath = self.runConfig.outputFile
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
    
    
    
    func dumpPoint(_ index: Int, pointSet: KeySearchMetal.PointSet) {
        let xPtr = pointSet.xBuffer.contents()
            .bindMemory(to: KeySearchMetal.UInt256.self, capacity: totalPoints)
        
        let yPtr = pointSet.yBuffer.contents()
            .bindMemory(to: KeySearchMetal.UInt256.self, capacity: totalPoints)
        
        let x = xPtr[index]
        let y = yPtr[index]
        
        //Helpers.printLimbs(limbs: [x.limbs.0,x.limbs.1,x.limbs.2,x.limbs.3,x.limbs.4,x.limbs.5,x.limbs.6,x.limbs.7] )
        
        print("Public Key Point[\(index)] X=\(uint256ToHex(x)) Y=\(uint256ToHex(y))")
    }
    
    
    
    func uint256ToHex(_ v:  KeySearchMetal.UInt256) -> String {
        let arr = [v.limbs.0, v.limbs.1, v.limbs.2, v.limbs.3,
                   v.limbs.4, v.limbs.5, v.limbs.6, v.limbs.7]
        return arr.reversed().map { String(format: "%08x", $0) }.joined()
    }
    
    func limbsToHex(_ v: KeySearchMetal.UInt256) -> String {
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




