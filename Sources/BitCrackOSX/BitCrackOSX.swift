import Foundation
import P256K
import Metal
import Foundation

let device = MTLCreateSystemDefaultDevice()!
let ITERATIONS = 10000




@main
struct BitCrackOSX {
    static func main() {

        let SHA256 = SHA256gpu(on: device)
        
        
        print("Starting \(ITERATIONS) iterations benchmarks on GPU: \(device.name)\n")
        //let clock = ContinuousClock()
        //------------------------
        // RIPEMD160 benchmark
        //------------------------
        // RIPEMD160.run(on: device)

        
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
        
        //exit(0);
        
        // Iterate through a range of private keys
        let start = UInt256(hexString: "0000000000000000000000000000000000000000000000000000000000000001")
        let end = UInt256(hexString: "000000000000000000000000000000000000000000000000000000000000000A")
       /*
        let keyIterator = BitcoinPrivateKeyIterator(start: start, end: end)
        
        for (index, privateKey) in keyIterator.enumerated() {
            print("Key \(index + 1): \(privateKey.hexString)")
            
            // We are running the secp256k1 calculations on the CPU which is very slow.
            // TODO: Do secp256k1 calculations on GPU
            let privateKeyCompressed = try! P256K.Signing.PrivateKey(dataRepresentation: privateKey.data, format: .compressed)
            let privateKey = try! P256K.Signing.PrivateKey(dataRepresentation: privateKey.data, format: .uncompressed)
            
            // Public key
            print("  Public Key:  \(String(bytes: privateKey.publicKey.dataRepresentation))")
            print("  Public Key Compressed:  \(String(bytes: privateKeyCompressed.publicKey.dataRepresentation))")
        
        }
        */
        
        
        
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
            let pubKey = UInt256(data: privateKey.publicKey.dataRepresentation)
            print("Private Key Compressed: = \(privateKeyCompressed.dataRepresentation.hex) Pub Key:  \(pubKey.hexString)")
            batch.append(pubKey)
            //print("  Public Key:  \(String(bytes: privateKey.publicKey.dataRepresentation))")
            //print("  Public Key Compressed:  \(String(bytes: privateKeyCompressed.publicKey.dataRepresentation))")
           
            // Send data batch wise to the GPU for SHA256 hashing
            if batch.count%10==0 {
                // Calculate SHA256 for the batch of public keys on the GPU
                SHA256.run(batchOfData: batch)
                
            }
            
 
        }
        
        print("Generated \(batch.count) keys")
        for key in batch {
          //  print("Pub Key:  \(key.hexString)")
        }
        // END ecp256k1 benchmark
        
        print("Done")


    }
}







