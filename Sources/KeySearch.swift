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

        // TODO: check for maximum range wich is: 0xFFFF FFFF FFFF FFFF FFFF FFFF FFFF FFFE BAAE DCE6 AF48 A03B BFD2 5E8C D036 4140
        
        //let startKey = "0000000000000000000000000000000000000000000000000001000000000000"
        
        let commandQueue = device.makeCommandQueue()!
        let keyLength = Properties.compressedKeySearch ? 33 : 65 //   keyLength:  33 = compressed;  65 = uncompressed
        
        let keyGen = try KeyGen(device: device, batchSize: privKeyBatchSize, startKeyHex: startHexKey)
        let secp256k1 = try Secp256k1(on:  device, inputBatchSize: privKeyBatchSize, outputBatchSize: pubKeyBatchSize, inputBuffer: keyGen.getOutputBuffer())
        let sha256 = try SHA256(on: device, batchSize: pubKeyBatchSize, inputBuffer: secp256k1.getOutputBuffer(), keyLength: UInt32(keyLength))
        let ripemd160 = try RIPEMD160(on: device, batchSize: pubKeyBatchSize, inputBuffer: sha256.getOutputBuffer())
        // TODO Initialize the bloomfilter from here
        
        try Helpers.printGPUInfo(device: device)
        
        if Properties.verbose {
            print("                  │ Threads per TG │ TGs per Grid │ Thread Exec. Width │")
            keyGen.printThreadConf()
            secp256k1.printThreadConf()
            sha256.printThreadConf()
            ripemd160.printThreadConf()
            bloomFilter.printThreadConf()
            print("")
        }
        
        let compUncomp = Properties.compressedKeySearch ? "compressed" : "uncompressed"
        print("🚀 Starting \(compUncomp) key search from: \(startHexKey)\n")
       
        ui.startLiveStats()
        
        while true {  // TODO: Shall we introduce an end key, if reached then the application stops?
            
            let startTime = CFAbsoluteTimeGetCurrent()
            
            let commandBuffer = commandQueue.makeCommandBuffer()!
            keyGen.appendCommandEncoder(commandBuffer: commandBuffer)
            secp256k1.appendCommandEncoder(commandBuffer: commandBuffer)
            sha256.appendCommandEncoder(commandBuffer: commandBuffer)
            ripemd160.appendCommandEncoder(commandBuffer: commandBuffer)
            bloomFilter.appendCommandEncoder(commandBuffer: commandBuffer, inputBuffer: ripemd160.getOutputBuffer()) // TODO: make this consistent and move inputBuffer to constructor once refactored
            
            // Submit work to GPU
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            
            let start = DispatchTime.now()
            let result = bloomFilter.getResults() //query(ripemd160.getOutputBuffer(), batchSize: pubKeyBatchSize)   
            
            let falsePositiveCnt = checkBloomFilterResults(
                result: result,
                privateKeyBuffer: keyGen.getOutputBuffer(),
                ripemd160Buffer: ripemd160.getOutputBuffer())
            
            ui.bloomFilter = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0
            
            
            let endTime = CFAbsoluteTimeGetCurrent()
            ui.updateStats(totalStartTime: startTime, totalEndTime: endTime, bfFalsePositiveCnt: falsePositiveCnt)
           
            
        }
    }
    
    
    func checkBloomFilterResults(result: [Bool], privateKeyBuffer: MTLBuffer, ripemd160Buffer: MTLBuffer) -> Int {
        var falsePositiveCnt = 0
      
        for privKeyIndex in 0..<privKeyBatchSize {
            for i in 0..<Properties.KEYS_PER_THREAD {
                let pubKeyIndex = privKeyIndex*Properties.KEYS_PER_THREAD + i
                
                if result[pubKeyIndex] {
                    // Get the base private key
                    var privKey = [UInt8](repeating: 0, count: 32)
                    memcpy(&privKey, privateKeyBuffer.contents().advanced(by: privKeyIndex*32), 32)
                    
                    // We only have the base key. We need to add the offset i (key position in secp256k1 thread) to get the real private key
                    let basePrivKeyHex = Data(privKey.reversed()).hexString
                    let privateKey = BInt(basePrivKeyHex, radix: 16)! + BInt(i)
                    var privateKeyStr = privateKey.asString(radix: 16)
                    privateKeyStr = String(repeating: "0", count: max(0, 64 - privateKeyStr.count)) + privateKeyStr
                    
                    // Get the hash160
                    var pubKeyHash = [UInt8](repeating: 0, count: 20)
                    memcpy(&pubKeyHash, ripemd160Buffer.contents().advanced(by: pubKeyIndex*20), 20)
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
                        💰 Private key found: \(privateKeyStr)
                           For addresses:
                            \(addresses.map { $0.address }.joined(separator: "\n    "))
                        --------------------------------------------------------------------------------------
                        """)
                       
                        try! appendToResultFile(text: "Found private key: \(privateKeyStr) for addresses: \(addresses.map(\.address).joined(separator: ", ")) \n")
                        // exit(0) // TODO: do we want to exit? Make this configurable
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









