import Foundation
import P256K
import Metal
import Foundation

let device = MTLCreateSystemDefaultDevice()!
let ITERATIONS = 10000




@main
struct BitCrackOSX {
    fileprivate static func printSha256Output(_ BATCH_SIZE: Int, _ outPtr: UnsafeMutablePointer<UInt32>, _ hashWordsToHex: ([UInt32]) -> String, _ batch: inout [UInt256]) {
        // Print output
        for i in 0..<BATCH_SIZE {
            var words: [UInt32] = []
            for j in 0..<8 {
                let w = outPtr[i*8 + j].bigEndian // convert to big-endian for correct hex order
                words.append(w)
                
            }
            let hex = hashWordsToHex(words)
            print("Message[\(i)] Public Key: '\(batch[i])' -> SHA256: \(hex)")
            
        }
    }
    
    static func main() {

        let SHA256 = SHA256gpu(on: device)
        let RIPEMD160 = RIPEMD160(on: device)
        
        print("Starting \(ITERATIONS) iterations benchmarks on GPU: \(device.name)\n")
        //let clock = ContinuousClock()
        //------------------------
        // RIPEMD160 benchmark
        //------------------------
        
        //RIPEMD160.run()
        //exit(0);
        
        //------------------------
        // SHA256 Benchmark
        //------------------------
        /*let result = clock.measure{
            SHA256gpu.run(on: device, iterations: ITERATIONS)
        }
        print("\nAll benchmarks finished after: \(result)s")
 */
        
        
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
        var batch: [UInt256] = []
        let batchIterator = BitcoinPrivateKeyIterator(start: start, end: end)

        for privateKey: UInt256 in batchIterator {
            // We are running the secp256k1 calculations on the CPU which is very slow.
            // TODO: Do secp256k1 calculations on GPU
            let privateKeyCompressed = try! P256K.Signing.PrivateKey(dataRepresentation: privateKey.data, format: .compressed)
            let privateKey = try! P256K.Signing.PrivateKey(dataRepresentation: privateKey.data, format: .uncompressed)
            
            // Public key
            // TODO: add option to add uncompressed keys
            let pubKey = UInt256(data: privateKeyCompressed.publicKey.dataRepresentation)
            print("Private Key Compressed: = \(privateKeyCompressed.dataRepresentation.hex) Pub Key:  \(pubKey.hexString)")
            batch.append(pubKey)
            //print("  Public Key:  \(String(bytes: privateKey.publicKey.dataRepresentation))")
            //print("  Public Key Compressed:  \(String(bytes: privateKeyCompressed.publicKey.dataRepresentation))")
           
            // Send data batch wise to the GPU for SHA256 hashing
            let BATCH_SIZE = 10
            if batch.count == BATCH_SIZE {
                // Calculate SHA256 for the batch of public keys on the GPU
                let outPtr = SHA256.run(batchOfData: batch)
                printSha256Output(BATCH_SIZE, outPtr, hashWordsToHex, &batch)
             
                let ripemd160_input_data = Data(bytesNoCopy: outPtr, count: BATCH_SIZE*32, deallocator: .custom({ (ptr, size) in ptr.deallocate() }))
                //let ripemd160_input_data = Data(bytes: outPtr, count: BATCH_SIZE*32) // Is an alternative, but copies the data and therefore is slower
               
                RIPEMD160.run(inputData: ripemd160_input_data)
            
                
                

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
      
        
        print("Done")


        
        // Convert output words (uint32) to hex string (big-endian per SHA-256 spec)
         func hashWordsToHex(_ words: [UInt32]) -> String {
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
        
    }
    
    

}







