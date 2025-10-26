import Foundation
import P256K
import Metal


let device = MTLCreateSystemDefaultDevice()!
let ITERATIONS = 10000




@main
struct BitCrackOSX {
   
    
    static func main() {
        BitCrackOSX().run()
    }
    
    func run(){
        let SHA256 = SHA256gpu(on: device)
        let RIPEMD160 = RIPEMD160(on: device)
        
        print("Starting \(ITERATIONS) iterations benchmarks on GPU: \(device.name)\n")

        loadAddressFile(path: "/Users/x/Downloads/bitcoin_short.tsv")
        
        //------------------------
        // secp256k1 benchmark
        //------------------------
        
        // Run UInt256 tests and demonstration
        // UInt256Tests.runTests()
        // demonstrateUsage()
  
        
        // Iterate through a range of private keys
        let start = UInt256(hexString: "0000000000000000000000000000000000000000000000000000000000000001")
        let end = UInt256(hexString: "000000000000000000000000000000000000000000000000000000000001000A")
      

        // Generate keys in batches
        print("\n=== Batch Generation ===")
        var batch: [Data] = []
        let batchIterator = BitcoinPrivateKeyIterator(start: start, end: end)

        for privateKey: UInt256 in batchIterator {
            // We are running the secp256k1 calculations on the CPU which is very slow.
            // TODO: Do secp256k1 calculations on GPU
            let privateKeyCompressed = try! P256K.Signing.PrivateKey(dataRepresentation: privateKey.data, format: .compressed)
            let privateKey = try! P256K.Signing.PrivateKey(dataRepresentation: privateKey.data, format: .uncompressed)
            
            // Public key
            // TODO: add option to add uncompressed keys
            let pubKey = privateKeyCompressed.publicKey.dataRepresentation
            //print("Private Key Compressed: = \(privateKeyCompressed.dataRepresentation.hex) Pub Key:  \(pubKey.hex)")
            batch.append(pubKey)
            //print("  Public Key:  \(String(bytes: privateKey.publicKey.dataRepresentation))")
            //print("  Public Key Compressed:  \(String(bytes: privateKeyCompressed.publicKey.dataRepresentation))")
           
            // Send data batch wise to the GPU for SHA256 hashing
            let BATCH_SIZE = 10000
            if batch.count == BATCH_SIZE {
                let startTime = CFAbsoluteTimeGetCurrent()

                
                // Calculate SHA256 for the batch of public keys on the GPU
                let outPtr = SHA256.run(batchOfData: batch)
                //printSha256Output(BATCH_SIZE, outPtr)
             
                let ripemd160_input_data = Data(bytesNoCopy: outPtr, count: BATCH_SIZE*32, deallocator: .custom({ (ptr, size) in ptr.deallocate() }))
                //let ripemd160_input_data = Data(bytes: outPtr, count: BATCH_SIZE*32) // Is an alternative, but copies the data and therefore is slower
               
                let ripemd160_result = RIPEMD160.run(messagesData: ripemd160_input_data, messageCount: BATCH_SIZE)
                //printRipemd160Output(BATCH_SIZE, ripemd160_result)
                
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
                //let mbProcessed = Double(BATCH_SIZE * 32) / (1024.0*1024.0)
                let hashesPerSec = Double(BATCH_SIZE) / elapsed
                print(String(format: "GPU elapsed: %.4f s — %.0f hashes/s", elapsed, hashesPerSec))
                
            
           
               
                
                batch = []  //clearing batch
            }
            
 
        }
        
        //print("Generated \(batch.count) keys")

    }
    
    
    
    func loadAddressFile(path: String) {
        
        let BATCH_SIZE = 1000
        print("Loading address file")
        
        // First we only need to count the relevant addresses, so that we can initialize the BloomFilter with the right capacity
        var validAddrCount: Int = 0
        guard let file = freopen(path, "r", stdin) else {
            print("Error opening file")
            return // TODO: throw
        }
        defer {
            fclose(file)
        }
        while let line = readLine() {
            if line.starts(with: "1") { // Legacy address
                validAddrCount+=1;
            }
            else if line.starts(with: "3"){ // P2SH address
                // NOT SUPPORTED YET
            }
            else if line.starts(with: "bc1q"){ // Segwit Bech32 address
                // NOT SUPPORTED YET
            }
            else if line.starts(with: "bc1p"){ // Taproot address
                // NOT SUPPORTED YET
            }
            
        }
     
        
        var bloomFilter = BloomFilter2(capacity: validAddrCount, falsePositiveRate: 0.001)

        
        // Opening the same file again to populate the bloomfilter
        guard let file = freopen(path, "r", stdin) else {
            print("Error opening file")
            return // TODO: throw
        }
        defer {
            fclose(file)
        }
        
        print("Building bloom filter")
        var progressCnt:Int = 1;
        var lastPerc :Int = 0
        
        var addrBatch: [String] = [];
        while let line = readLine() {
         
          
            if line.starts(with: "1") { // Legacy address
                     
     
                // ASYNC Version
                /*
                var nanoTime: UInt64 = 0
                
                // Async batch version
                addrBatch.append(line.trimmingCharacters(in: .whitespaces))
                if addrBatch.count > BATCH_SIZE {
                    let start = DispatchTime.now()
                    let decodedAddresses = Base58.decodeBatchAsync(addrBatch)
                    for i in decodedAddresses {
                        bloomFilter.insert(data: i)
                    }
                    let end = DispatchTime.now()
                    nanoTime = end.uptimeNanoseconds - start.uptimeNanoseconds // <<<<< Difference in nano seconds (UInt64)

                   
                            
                    addrBatch = []
                
                
                    
                    
                    progressCnt+=BATCH_SIZE
                    var procressPercent = Int((100.0/Double(validAddrCount))*Double(progressCnt))
                    if lastPerc < procressPercent{
                        print("Progress: \(procressPercent)%")
                        //print("Bloom \(nanoTime2)")
                        print("BASE58 \(nanoTime/UInt64(BATCH_SIZE))")
                        lastPerc = procressPercent
                    }
                }
            */
                
                //---------------------
                
             
                let start = DispatchTime.now()
                var decodedAddress = Base58.decode(line.trimmingCharacters(in: .whitespaces))
                let end = DispatchTime.now()
                let nanoTime = end.uptimeNanoseconds - start.uptimeNanoseconds // <<<<< Difference in nano seconds (UInt64)

               
                
                decodedAddress = decodedAddress.unsafelyUnwrapped.dropFirst(1).dropLast(4) // Removing the addres byte and checksum
                
                let start2 = DispatchTime.now()

                bloomFilter.insert(data: decodedAddress.unsafelyUnwrapped)
                let end2 = DispatchTime.now()
                let nanoTime2 = end2.uptimeNanoseconds - start2.uptimeNanoseconds // <<<<< Difference in nano seconds (UInt64)


                progressCnt+=1
                var procressPercent = Int((100.0/Double(validAddrCount))*Double(progressCnt))
                if lastPerc < procressPercent{
                    print("Progress: \(procressPercent)%")
                    //print("Bloom \(nanoTime2)")
                    print("BASE58 \(nanoTime)")
                    lastPerc = procressPercent
                }
                
                
                
                //print("Addr \(line)   \(decodedAddress.hex)")
            }
            else if line.starts(with: "3"){ // P2SH address
                // NOT SUPPORTED YET
            }
            else if line.starts(with: "bc1q"){ // Segwit Bech32 address
                // NOT SUPPORTED YET
            }
            else if line.starts(with: "bc1p"){ // Taproot address
                // NOT SUPPORTED YET
            }
            
            
            
        }
        
        print("Inserted \(validAddrCount) supoorted addresses into the bloom filter")
        
       /*
        if bloomFilter.contains("ssss"){
            print("yes")
        }
        print("no")
        */
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
}







