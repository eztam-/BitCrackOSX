import Foundation
import P256K


@main
struct BitCrackOSX {
    static func main() {
        print("Hello, world!")

        
        
 
        // Run UInt256 tests and demonstration
        // UInt256Tests.runTests()
        // demonstrateUsage()
        
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
        
        
        
        
        
        
        print("Done")


    }
}






