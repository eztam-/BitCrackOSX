import Foundation
import P256K
import Metal


let device = MTLCreateSystemDefaultDevice()!
let ITERATIONS = 10000




@main
struct BitCrackOSX {
   
    
    static func main() {

        let SHA256 = SHA256gpu(on: device)
        let RIPEMD160 = RIPEMD160(on: device)
        
        print("Starting \(ITERATIONS) iterations benchmarks on GPU: \(device.name)\n")

        
        
        //------------------------
        // secp256k1 benchmark
        //------------------------
        
        // Run UInt256 tests and demonstration
        // UInt256Tests.runTests()
        // demonstrateUsage()
  
        
        // Iterate through a range of private keys
        let start = UInt256(hexString: "0000000000000000000000000000000000000000000000000000000000000001")
        let end = UInt256(hexString: "000000000000000000000000000000000000000000000000000000000000000A")
      
    
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
            print("Private Key Compressed: = \(privateKeyCompressed.dataRepresentation.hex) Pub Key:  \(pubKey.hex)")
            batch.append(pubKey)
            //print("  Public Key:  \(String(bytes: privateKey.publicKey.dataRepresentation))")
            //print("  Public Key Compressed:  \(String(bytes: privateKeyCompressed.publicKey.dataRepresentation))")
           
            // Send data batch wise to the GPU for SHA256 hashing
            let BATCH_SIZE = 10
            if batch.count == BATCH_SIZE {
                // Calculate SHA256 for the batch of public keys on the GPU
                let outPtr = SHA256.run(batchOfData: batch)
                printSha256Output(BATCH_SIZE, outPtr)
             
                let ripemd160_input_data = Data(bytesNoCopy: outPtr, count: BATCH_SIZE*32, deallocator: .custom({ (ptr, size) in ptr.deallocate() }))
                //let ripemd160_input_data = Data(bytes: outPtr, count: BATCH_SIZE*32) // Is an alternative, but copies the data and therefore is slower
               
                let ripemd160_result = RIPEMD160.run(messagesData: ripemd160_input_data, messageCount: BATCH_SIZE)
                printRipemd160Output(BATCH_SIZE, ripemd160_result)
                
                
                // TODO: This is not very performant. Its better adding it in the metal file of ripemd160 at the end
                var versionedRipemd160 = convertPointerToDataArray(ptr:ripemd160_result, count: 5*BATCH_SIZE, dataItemLength: 5)
                for i in 0..<BATCH_SIZE{
                    versionedRipemd160[i].insert( 0x00, at: 0) // 0x00 Mainnet
                }
                
                
                // Calculate SHA256 for the RIPEMD160 hashes + version byte
                let sha256_out2 = SHA256.run(batchOfData: versionedRipemd160)
                printSha256Output(BATCH_SIZE, sha256_out2)
                
                // Till here it works fine. The next Sha256 is wrong because big/little endian mismatch
                

                let sha256_out2_data = convertPointerToDataArray2(ptr:sha256_out2, count: 8*BATCH_SIZE, chunkSize: 8)
                print(sha256_out2_data[0].hex)
                // Calculate SHA256 on the results a second time
                let sha256_out3 = SHA256.run(batchOfData: sha256_out2_data)
                printSha256Output(BATCH_SIZE, sha256_out3)
               
                
                // TODO:
                // - Instead of BASE58 encoding each address, we should rather BSAE58 decode the addressess from the file and put them decoded in the bloomfilter. That way we save BASE58 during bruteforce entirely
                // - To improve pervormance even more, we could even skip the Checksum part including double SHA256 and put addresses with removed checksum into the bloomfilter. Only on a match we can still check the full address
                
                /*
                for i in 0..<BATCH_SIZE {
                    let checksumBytes = sha256_out3[i*8] // Take the first 4 bytes from the double SHA256 result which is the checksum
                    ripemd160_result[i]
                    var words: [UInt32] = []
                    for j in 0..<8 {
                        let w = outPtr[i*8 + j].bigEndian // convert to big-endian for correct hex order
                        words.append(w)
                        
                    }
                
                sha256_out3
                
                let bitcoinAddress = Base58.encode(binaryAddress)
                print("Bitcoin Address: \(bitcoinAddress)")
                 */
                // TODO: Extend with version byte
                // TODO: perform SHA-256 on the result
                // TODO: Perform SHA-256 again (note the first four bytes of the result are referred to as the “check sum”)
                // TODO: Take the check sum and add it to the end of the result from step three. This is the 25 bit binary bitcoin address
                // TODO: Convert from a byte strong to base58
                // TODO: Check against bloomfilter of addresses with balance
                
                
                batch = []  //clearing batch
                print("Batch complete ############################")
            }
            
 
        }
        
        print("Generated \(batch.count) keys")

 
    }
    
    
  
    
    /// Converts a pointer to UInt32 values into an array of `Data` objects.
    /// Each `Data` chunk will contain `chunkSize` UInt32 values (default: 4).
    fileprivate static func convertPointerToDataArray2(
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
    
    fileprivate static func convertPointerToDataArray(ptr: UnsafeMutablePointer<UInt32>, count: Int, dataItemLength: Int) -> [Data] {
        
        
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
    fileprivate static func ripemdWordsToHex(_ words: [UInt32]) -> String {
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
    fileprivate static func hashWordsToHex(_ words: [UInt32]) -> String {
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
        return beBytes.map { String(format: "%02x", $0) }.joined()
    }
    
    
    // TEST convert words to little endian
    fileprivate static func toLittleEndian(_ words: [UInt32]) -> Data {
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
    
    
    fileprivate static func printSha256Output(_ BATCH_SIZE: Int, _ outPtr: UnsafeMutablePointer<UInt32>) {
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
    
    
    fileprivate static func printRipemd160Output(_ BATCH_SIZE: Int, _ ripemd160_result: UnsafeMutablePointer<UInt32>) {
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







