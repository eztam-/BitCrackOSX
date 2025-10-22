import Foundation
import P256K
import Metal
import Foundation

let device = MTLCreateSystemDefaultDevice()!
let ITERATIONS = 10000




@main
struct BitCrackOSX {
    static func main() {
        print("Hello, world!")

        
        print("Starting \(ITERATIONS) iterations benchmarks on GPU: \(device.name)\n")

        //------------------------
        // RIPEMD160 benchmark
        //------------------------
        // RIPEMD160.run(on: device)

        
        //------------------------
        // SHA256 Benchmark
        //------------------------
        let result = clock.measure{
            SHA256gpu.run(on: device, iterations: ITERATIONS)
        }
        print("\nAll benchmarks finished after: \(result)s")
 
        
        
        //------------------------
        // secp256k1 benchmark
        //------------------------
        
        // Run UInt256 tests and demonstration
        // UInt256Tests.runTests()
        // demonstrateUsage()
        
        exit(0);
        
        // Iterate through a range of private keys
        let start = UInt256(hexString: "0000000000000000000000000000000000000000000000000000000000000001")
        let end = UInt256(hexString: "0000000000000000000000000000000000000000000000000000000000200000")
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
        
        // END ecp256k1 benchmark
        
        
        
        
        print("Done")


    }
}






