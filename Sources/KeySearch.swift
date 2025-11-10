import Foundation
import Metal


let device = MTLCreateSystemDefaultDevice()!

// TODO: FIXME: If the key range is smaller than the batch size it doesnt work
// TODO: If the size is smaller, that we run into a memory leak since the garbage collector seem to slow, to free up the memory for the commandBuffers


class KeySearch {

    let bloomFilter: BloomFilter
    let db: DB
    let outputFile: String
    
    public init(bloomFilter: BloomFilter, database: DB, outputFile: String) {
        self.bloomFilter = bloomFilter
        self.db = database
        self.outputFile = outputFile
    }
    
    func run(startKey: String){
        
      
        
        
       // bloomTest()
        //exit(0)
    
        
        
        
        // TODO: check for maximum range wich is: 0xFFFF FFFF FFFF FFFF FFFF FFFF FFFF FFFE BAAE DCE6 AF48 A03B BFD2 5E8C D036 4140
        
        //let startKey = "0000000000000000000000000000000000000000000000000001000000000000"
       
        
        let keyGen = KeyGen(device: device, batchSize: Constants.BATCH_SIZE, startKeyHex: startKey)
        let secp256k1obj = Secp256k1_GPU(on:  device, bufferSize: Constants.BATCH_SIZE)
        let SHA256 = SHA256gpu(on: device, batchSize: Constants.BATCH_SIZE)
        let RIPEMD160 = RIPEMD160(on: device, batchSize: Constants.BATCH_SIZE)
        //let bloomFilter = AddressFileLoader.load(path: "/Users/x/src/CryptKeyFinder/test_files/btc_short.tsv")
        //let bloomFilter = BloomFilter(expectedInsertions: 1, itemBytes: 1)!
        let t = TimeMeasurement.instance
        
        
        
        
        //print("⚡ Running on GPU: \(device.name)\n")
        Helpers.printGPUInfo(device: device)
        print("🚀 Starting key search from: \(startKey)\n")
        
        while true {  // TODO: Shall we introduce an end key, if reached then the application stops?
            
            let startTime = CFAbsoluteTimeGetCurrent()
            
            
            // Generate batch of private keys
            var start = DispatchTime.now()
            let privateKeyBuffer = keyGen.run()
            t.keyGen = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0

            
            
            // Using secp256k1 EC to calculate public keys for the given private keys
            start = DispatchTime.now()
            let (pubKeysCompBuff, pubKeysUncompBuff) = secp256k1obj.generatePublicKeys(privateKeyBuffer: privateKeyBuffer)
            t.secp256k1 = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0
            
            
       
            // Calculate SHA256 for the batch of public keys
            start = DispatchTime.now()
            let sha256Buff = SHA256.run(publicKeysBuffer: pubKeysCompBuff, batchSize: Constants.BATCH_SIZE)
            //printSha256Output(BATCH_SIZE, outPtr)
            t.sha256 = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0
            
            
            
            // Calculate RIPEDM160
            start = DispatchTime.now()
            let ripemd160Buffer = RIPEMD160.run(messagesBuffer: sha256Buff, messageCount: Constants.BATCH_SIZE)
            t.ripemd160 = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0
            
            
            
            // Check RIPEMD160 hashes against the bloom filter
            // Note, we have reverse-calculated BASE58 before inserting addresses into the bloom filter, so we can check directly the RIPEMD160 hashes which is faster.
            start = DispatchTime.now()
            //for i in 0..<BATCH_SIZE {
                
                
           // let ripemd160Array = Helpers.ptrToDataArray(ripemd160_result, itemSize: 20, itemCount: BATCH_SIZE)
            let result = bloomFilter.query(ripemd160Buffer, batchSize: Constants.BATCH_SIZE)   //contains(pointer: ripemd160_result, length: 5, offset: i*5)
          
            for i in 0..<Constants.BATCH_SIZE {
                if result[i] {
                    var privKey = [UInt8](repeating: 0, count: 32)
                    memcpy(&privKey, privateKeyBuffer.contents().advanced(by: i*32), 32)
                    let privKeyHex = Data(privKey.reversed()).hexString
                    
                    var pubKeyHash = [UInt8](repeating: 0, count: 20)
                    memcpy(&pubKeyHash, ripemd160Buffer.contents().advanced(by: i*20), 20)
                    let pubKeyHashHex = Data(pubKeyHash).hexString
                    let addresses = try! db.getAddresses(for: pubKeyHashHex)
                    
                    if addresses.isEmpty {
                        print("False positive bloom filter result")
                    }
                    else {
                        print("---------------------------------------------------------------------")
                        print("💰 Private key found: \(privKeyHex)")
                        print("For addresses:")
                        for addr in addresses{
                            print("   \(addr.address)")
                        }
                        //print("Use any tool like btc_address_dump to get the address for the private key")
                        //print("!!! NOTE !!! At the moment this address is just the RIPEMD160 result, you need to add the address byte and do a base58 decode and a checksum validation to get the actual address.")
                        print("---------------------------------------------------------------------\n")
                       // exit(0) // TODO: do we really want to exit? Make this configurable
                        
                        try!	 appendToResultFile(text: "Found private key: \(privKeyHex) for addresses: \(addresses.map(\.address).joined(separator: ", ")) \n")
                        
                        
                    }
                    
                    
                }
            }
            

          //  }
            t.bloomFilter = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0
            
            
            
            //print("bloomfilter took: \(end.uptimeNanoseconds - start.uptimeNanoseconds)ns")
            // The following would do all the further steps to calculate the address but we don't need it, since the addresses in the bloomfilter
            // are already BASE58 decoded and also the version byte and checksum were removed.
            /*
             // TODO: This is not very performant. Its better adding it in the metal file of ripemd160 at the end
             var versionedRipemd160 = convertPointerToDataArray(ptr:ripemd160_result, count: 5*BATCH_SIZE, dataItemLength: 5)
             for i in 0..<BATCH_SIZE{
             versionedRipemd160[i].insert( 0x00, at: 0) // 0x00 Mainnet
             }
             
             
             // Calculate SHA256 for the RIPEMD160 hashes + version byte
             let sha256_out2 = SHA256.run(batchOfData: versionedRipemd160)
             //printSha256Output(BATCH_SIZE, sha256_out2)
             
             let sha256_out2_data = convertPointerToDataArray2(ptr:sha256_out2, count: 8*BATCH_SIZE, chunkSize: 8)
             //print(sha256_out2_data[0].hex)
             // Calculate a sechond SHA256 on the previous SHA256 hash
             let sha256_out3 = SHA256.run(batchOfData: sha256_out2_data)
             //printSha256Output(BATCH_SIZE, sha256_out3)
             
             
             //for i in stride(from: 0, to: BATCH_SIZE*8, by: 8) {
             for i in 0..<BATCH_SIZE {
             let checksum = sha256_out3[i*8]
             //print(String(format: "Checksum: %08X", checksum.bigEndian))
             
             var bitcoinAddress = Data(versionedRipemd160[i])
             
             bitcoinAddress.append(withUnsafeBytes(of: checksum) { Data($0) })
             let bitcoinAddressStr = Base58.encode(bitcoinAddress)
             //print("Bitcoin Address: \(bitcoinAddressStr)")
             }
             
             */
            
            
            
            let endTime = CFAbsoluteTimeGetCurrent()
            let elapsed = endTime - startTime
            let hashesPerSec = Double(Constants.BATCH_SIZE) / elapsed
            t.keysPerSec = String(format: "----[ %.0f keys/s ]----", hashesPerSec)
            
            
        }
        
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
    
    
    // Convert output words (uint32) to hex string (big-endian per SHA-256 spec)
    func hashWordsToHex(_ words: [UInt32]) -> String {
        // SHA-256 words are stored as big-endian words in the algorithm; the kernel computed in uint (host little-endian).
        // We need to print each word as big-endian bytes in hex.
        let beBytes: [UInt8] = words.flatMap { w -> [UInt8] in
            let be = w // .bigendian
            return [
                UInt8((be >> 24) & 0xff),
                UInt8((be >> 16) & 0xff),
                UInt8((be >> 8) & 0xff),
                UInt8(be & 0xff)
            ]
        }
        return beBytes.map { String(format: "%02x", $0) }.joined()
    }
    
    
    // TEST convert words to little endian
    func toLittleEndian(_ words: [UInt32]) -> Data {
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
        return Data(beBytes)
        //return beBytes.map { String(format: "%02x", $0) }.joined()
    }
    
    
    func printSha256Output(_ BATCH_SIZE: Int, _ outPtr: UnsafeMutablePointer<UInt32>) {
        // Print output
        for i in 0..<BATCH_SIZE {
            var words: [UInt32] = []
            for j in 0..<8 {
                let w = outPtr[i*8 + j].bigEndian // convert to big-endian for correct hex order
                words.append(w)
                
            }
            let hex = hashWordsToHex(words)
            print("Message[\(i)] -> SHA256: \(hex)")
            
        }
    }
    
    
    func printRipemd160Output(_ BATCH_SIZE: Int, _ ripemd160_result: UnsafeMutablePointer<UInt32>) {
        for i in 0..<BATCH_SIZE {
            let base = i * 5
            var words: [UInt32] = []
            for j in 0..<5 {
                words.append(ripemd160_result[base + j])
            }
            let hex = ripemdWordsToHex(words)
            print("Sample[\(i)] -> RIPEMD: \(hex)")
        }
    }
    
    
    func privKeysToHex(_ BATCH_SIZE: Int, _ result: UnsafeMutablePointer<UInt32>) {
        for i in 0..<BATCH_SIZE {
            let base = i * 8
            var words: [UInt32] = []
            for j in 0..<8 {
                words.append(result[base + j])
            }
            let hex = ripemdWordsToHex(words)
            print("Sample[\(i)] -> KEY: \(hex)")
        }
    }
}









