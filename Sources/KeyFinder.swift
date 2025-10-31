import Foundation
import P256K
import Metal


let device = MTLCreateSystemDefaultDevice()!
let BATCH_SIZE = 5000


@main
struct KeyFinder {
    
    
    static func main() {
        KeyFinder().run()
    }
    
    
    func run(){
        
        let clock = ContinuousClock()
        let SHA256 = SHA256gpu(on: device)
        let RIPEMD160 = RIPEMD160(on: device)
        let secp256k1obj = Secp256k1_GPU(on:  device, bufferSize: BATCH_SIZE)
        
        print("Starting on GPU: \(device.name)\n")
        
        let bloomFilter = AddressFileLoader.load(path: "/Users/x/Downloads/bitcoin_very_short.tsv")
        
        
        
        // TODO: check for maximum range wich is: 0xFFFF FFFF FFFF FFFF FFFF FFFF FFFF FFFE BAAE DCE6 AF48 A03B BFD2 5E8C D036 4140
        // Iterate through a range of private keys
        let start = UInt256(hexString: "0000000000000000000000000000000000000000000000000001000000000000")
        let end = UInt256(hexString: "00000000000000000000000000000000000000000000000000010000A0000005")
        
        
        // Generate keys in batches
        print("\n=== Batch Generation ===")
        var pubKeyBatch: [Data] = []
        //var privKeyBatch: [UInt256] = []
        var privKeysBatch2 : [Secp256k1_GPU.PrivateKey] = [] // TODO consolidatio into one
        let batchIterator = BitcoinPrivateKeyIterator(start: start, end: end)
        
        // TODO: FIXME: If the key range is smaller than the batch size it doesnt work
        for privateKey: UInt256 in batchIterator {
            //privKeyBatch.append(privateKey)
            privKeysBatch2.append(Secp256k1_GPU.PrivateKey(hexString:privateKey.hexString))
            // TODO add trailling zeros?
            
            
            
            
            
            /*
             
             // We are running the secp256k1 calculations on the CPU which is very slow.
             // TODO: Do secp256k1 calculations on GPU
             let privateKeyCompressed = try! P256K.Signing.PrivateKey(dataRepresentation: privateKey.data, format: .compressed)
             let privateKey = try! P256K.Signing.PrivateKey(dataRepresentation: privateKey.data, format: .uncompressed)
             
             // Public key
             // TODO: add option to add uncompressed keys
             let pubKey = privateKeyCompressed.publicKey.dataRepresentation
             //print("Private Key Compressed: = \(privateKeyCompressed.dataRepresentation.hex) Pub Key:  \(pubKey.hex)")
             pubKeyBatch.append(pubKey)
             //print("  Public Key:  \(String(bytes: privateKey.publicKey.dataRepresentation))")
             //print("  Public Key Compressed:  \(String(bytes: privateKeyCompressed.publicKey.dataRepresentation))")
             */
            // Send data batch wise to the GPU for SHA256 hashing
            
            if privKeysBatch2.count == BATCH_SIZE {
                let startTime = CFAbsoluteTimeGetCurrent()
                
                
                
                
                var start = DispatchTime.now()
                let pubKeys = secp256k1obj.generatePublicKeys(privateKeys: privKeysBatch2)
                for pk in pubKeys {
                    pubKeyBatch.append(pk.toCompressed())
                }
                var end = DispatchTime.now()
                print("secp256k1 took  : \(end.uptimeNanoseconds - start.uptimeNanoseconds)ns")
                
                
                
                // Calculate SHA256 for the batch of public keys on the GPU
                start = DispatchTime.now()
                let outPtr = SHA256.run(batchOfData: pubKeyBatch)
                //printSha256Output(BATCH_SIZE, outPtr)
                end = DispatchTime.now()
                print("SHA256 took     : \(end.uptimeNanoseconds - start.uptimeNanoseconds)ns")
                
                
                start = DispatchTime.now()
                let ripemd160_input_data = Data(bytesNoCopy: outPtr, count: BATCH_SIZE*32, deallocator: .custom({ (ptr, size) in ptr.deallocate() }))
                //let ripemd160_input_data = Data(bytes: outPtr, count: BATCH_SIZE*32) // Is an alternative, but copies the data and therefore is slower
                
                let ripemd160_result = RIPEMD160.run(messagesData: ripemd160_input_data, messageCount: BATCH_SIZE)
                //printRipemd160Output(BATCH_SIZE, ripemd160_result)
                end = DispatchTime.now()
                print("ripemd160 took  : \(end.uptimeNanoseconds - start.uptimeNanoseconds)ns")
                
                
                start = DispatchTime.now()
                for i in 0..<BATCH_SIZE {
                    let addrExists = bloomFilter.contains(pointer: ripemd160_result, length: 5, offset: i*5)
                    if addrExists {
                        print("#########################################################")
                        print("Found matching address: \(createData(from: ripemd160_result, offset: i*5, length: 5).hex) for private key: \(privKeysBatch2[i].data.hexString)")
                        print("!!! NOTE !!! At the moment this address is just the RIPEMD160 result, you need to add the address byte and do a base58 decode and a checksum validation to get the actual address.")
                        print("#########################################################")
                    }
                }
                end = DispatchTime.now()
                print("bloomfilter took: \(end.uptimeNanoseconds - start.uptimeNanoseconds)ns")
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
                
                
                
                
                
                pubKeyBatch = []  //clearing batch
                // privKeyBatch = []  //clearing batch
                privKeysBatch2 = []  //clearing batch
            }
            
            
        }
        
        //print("Generated \(batch.count) keys")
        
    }
    
    func createData(from pointer: UnsafePointer<UInt32>, offset: Int, length: Int) -> Data {
        let startPointer = pointer.advanced(by: offset)
        let buffer = UnsafeBufferPointer(start: startPointer, count: length)
        
        return Data(buffer: buffer)
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









