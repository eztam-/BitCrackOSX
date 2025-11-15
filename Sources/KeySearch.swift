import Foundation
import Metal


let device = MTLCreateSystemDefaultDevice()!


// Shouldn't make a hige difference in performance, but having the batch size as a multiple of maxThreadsPerThreadgroup will utilize each thread group fully.
// (otherwise the last one might be just partially used).
// This might also be a nice way, to chose larger batch sized for faster GPUs (TBC)
// Keep this private since each of the cimpute classes should get it per init(). This allows test cases to work with smaller batch sizes
private let BATCH_SIZE = device.maxThreadsPerThreadgroup.width * 512 



// TODO: FIXME: If the key range is smaller than the batch size it doesnt work
// TODO: If the size is smaller, that we run into a memory leak since the garbage collector seem to slow, to free up the memory for the commandBuffers


class KeySearch {
    
    let bloomFilter: BloomFilter
    let db: DB
    let outputFile: String
    let ui: UI = UI(batchSize: BATCH_SIZE)
    
    public init(bloomFilter: BloomFilter, database: DB, outputFile: String) {
        self.bloomFilter = bloomFilter
        self.db = database
        self.outputFile = outputFile
    }
    
    func run(startKey: String) throws {

        // TODO: check for maximum range wich is: 0xFFFF FFFF FFFF FFFF FFFF FFFF FFFF FFFE BAAE DCE6 AF48 A03B BFD2 5E8C D036 4140
        
        //let startKey = "0000000000000000000000000000000000000000000000000001000000000000"
        
        
        let keyGen = try KeyGen(device: device, batchSize: BATCH_SIZE, startKeyHex: startKey)
        let secp256k1obj = try Secp256k1_GPU(on:  device, batchSize: BATCH_SIZE)
        let SHA256 = try SHA256(on: device, batchSize: BATCH_SIZE)
        let RIPEMD160 = try RIPEMD160(on: device, batchSize: BATCH_SIZE)
        
        
        try Helpers.printGPUInfo(device: device)
        print("🚀 Starting key search from: \(startKey)\n")
       
        
        while true {  // TODO: Shall we introduce an end key, if reached then the application stops?
            
            let startTime = CFAbsoluteTimeGetCurrent()
            
            
            // Generate batch of private keys
            var start = DispatchTime.now()
            let privateKeyBuffer = keyGen.run()
            ui.keyGen = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0
            
            
            
            // Using secp256k1 EC to calculate public keys for the given private keys
            start = DispatchTime.now()
            let (pubKeysCompBuff, pubKeysUncompBuff) = secp256k1obj.generatePublicKeys(privateKeyBuffer: privateKeyBuffer)
            ui.secp256k1 = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0
            
            
            
            // Calculate SHA256 for the batch of public keys
            start = DispatchTime.now()
            let sha256Buff = SHA256.run(publicKeysBuffer: pubKeysCompBuff)
            //printSha256Output(BATCH_SIZE, outPtr)
            ui.sha256 = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0
            
            
            
            // Calculate RIPEDM160
            start = DispatchTime.now()
            let ripemd160Buffer = RIPEMD160.run(messagesBuffer: sha256Buff)
            ui.ripemd160 = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0
            
            
            
            // Check RIPEMD160 hashes against the bloom filter
            // Note, we have reverse-calculated BASE58 before inserting addresses into the bloom filter, so we can check directly the RIPEMD160 hashes which is faster.
            start = DispatchTime.now()
            let result = bloomFilter.query(ripemd160Buffer, batchSize: BATCH_SIZE)   //contains(pointer: ripemd160_result, length: 5, offset: i*5)
            
            let falsePositiveCnt = checkBloomFilterResults(
                result: result,
                privateKeyBuffer: privateKeyBuffer,
                ripemd160Buffer: ripemd160Buffer)
            
            ui.bloomFilter = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0
            
            
            let endTime = CFAbsoluteTimeGetCurrent()
            ui.updateStats(totalStartTime: startTime, totalEndTime: endTime, bfFalsePositiveCnt: falsePositiveCnt)
           
            
        }
    }
    
    
    func checkBloomFilterResults(result: [Bool], privateKeyBuffer: MTLBuffer, ripemd160Buffer: MTLBuffer) -> Int {
        var falsePositiveCnt = 0
        for i in 0..<BATCH_SIZE {
            if result[i] {
                var privKey = [UInt8](repeating: 0, count: 32)
                memcpy(&privKey, privateKeyBuffer.contents().advanced(by: i*32), 32)
                let privKeyHex = Data(privKey.reversed()).hexString
                
                var pubKeyHash = [UInt8](repeating: 0, count: 20)
                memcpy(&pubKeyHash, ripemd160Buffer.contents().advanced(by: i*20), 20)
                let pubKeyHashHex = Data(pubKeyHash).hexString
                let addresses = try! db.getAddresses(for: pubKeyHashHex)
                
                if addresses.isEmpty {
                    falsePositiveCnt+=1
                    //print("False positive bloom filter result")
                }
                else {
                    ui.printMessage(
                    """
                    --------------------------------------------------------------------------------------
                    💰 Private key found: \(privKeyHex)
                       For addresses:
                        \(addresses.map { $0.address }.joined(separator: "\n    "))
                    --------------------------------------------------------------------------------------
                    """)
                   
                    try! appendToResultFile(text: "Found private key: \(privKeyHex) for addresses: \(addresses.map(\.address).joined(separator: ", ")) \n")
                    // exit(0) // TODO: do we want to exit? Make this configurable
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
    
    
    /// Converts a pointer to UInt32 values into an array of `Data` objects.
    /// Each `Data` chunk will contain `chunkSize` UInt32 values (default: 4).
    func convertPointerToDataArray2(
        ptr: UnsafeMutablePointer<UInt32>,
        count: Int,
        chunkSize: Int
    ) -> [Data] {
        precondition(chunkSize > 0, "chunkSize must be greater than zero")
        precondition(count % chunkSize == 0, "count must be a multiple of chunkSize")
        
        var result: [Data] = []
        result.reserveCapacity(count / chunkSize)
        
        for i in stride(from: 0, to: count, by: chunkSize) {
            let chunkPtr = ptr.advanced(by: i)
            let data = Data(bytes: chunkPtr, count: chunkSize * MemoryLayout<UInt32>.size)
            result.append(data)
        }
        return result
    }
    
    func convertPointerToDataArray(ptr: UnsafeMutablePointer<UInt32>, count: Int, dataItemLength: Int) -> [Data] {
        
        var result: [Data] = []
        result.reserveCapacity(count / dataItemLength)
        
        for i in stride(from: 0, to: count, by: dataItemLength) {
            // Create a raw pointer for the dateItemLength UInt32 words
            let chunkPtr = ptr.advanced(by: i)
            
            // Create Data directly from memory (no copy)
            let data = Data(bytes: chunkPtr, count: dataItemLength * MemoryLayout<UInt32>.size)
            result.append(data)
        }
        
        return result
    }
    
}









