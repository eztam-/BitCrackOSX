import Metal
import Foundation
import CryptKeyFinder
import Testing
import P256K

class TestPubKey: TestBase {
    
    init() {
        super.init(kernelFunctionName: "test_field_sub")! // dummy. actuylly not needed
    }
    
    @Test func testRandomPubKey() {

        let numTests = 1000
        print("Running \(numTests) random number tests. Only printing failed results.")
        
        var numFailedTests = 0
        
        var privKeys : [Secp256k1_GPU.PrivateKey] = []
        
        for _ in 0..<numTests {
           
            let privKeyRaw = UInt256(hexString: super.generateRandom256BitHex())
            
            privKeys.append(Secp256k1_GPU.PrivateKey(hexString:privKeyRaw.data.hexString))
            // TODO: it i very important to add a test for uncompressed keys as well, since there could be calc errors i the Y coordinate which isnt visible in compressed keys
        }
        
        let secp256k1obj = Secp256k1_GPU()
        let res = secp256k1obj.generatePublicKeys(privateKeys: privKeys)
        
        for i in 0..<res.count {
            
            // Calculate expected value from lib
            let privateKeyCompressed = try! P256K.Signing.PrivateKey(dataRepresentation: privKeys[i].data, format: .compressed)
            let privateKeyUncomp = try! P256K.Signing.PrivateKey(dataRepresentation: privKeys[i].data, format: .uncompressed)
            let expPubKeyComp = privateKeyCompressed.publicKey.dataRepresentation.hexString
            //let expPubKeyUncomp = privateKeyUncomp.publicKey.dataRepresentation.hexString
            
            
            let pass = expPubKeyComp == res[i].toCompressed().hexString
            let result = pass ?  "✅ PASS" : "❌ FAIL"
            if !pass {
                numFailedTests+=1
                print("\(result)  Private Key: \(privKeys[i].data.hexString)")
                print("         Actual:      \(res[i].toCompressed().hexString)")
                print("         Expected:    \(expPubKeyComp)\n")
            }
           
            
        }
        
        print("🧪 \(numFailedTests) of \(numTests) tests have failed")
        assert(numFailedTests==0)
        
        
    }
    
    @Test func testPubKey(){
        
        
        let testCases: [(String, String, Bool)] = [ // Private Key, Expected Pub Key, Compressed
            (
                "0000000000000000000000000000000000000000000000000000000000000001",
                "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798",
                true
            ),
            (
                "0000000000000000000000000000000000000000000000000000000000000002",
                "02c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5",
                true
            ),
            (
                "0000000000000000000000000000000000000000000000000000000000000003",
                "02f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9",
                true
            ),
            (
                "0000000000000000000000000000000000000000000000000000000000000003",
                "04f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9388f7b0f632de8140fe337e62a37f3566500a99934c2231b6cb9fd7584b8e672",
                false
            ),
            (
                "000000000000000000000000000000000A100000000000000000000000000003",
                "0206a7d89b595868e231e3474a37051185a8c4d344f02edd122258fb355cfd6000",
                true
            ),
            (
                "c845836f99b08601f113bce036f9388f7b0f632de8140fe337e62a37f3566500",
                "03f0cf7eb73ea035675bb7b91ce9b13af78bc7afe04e9be723983ed5a4ed150a9b",
                true
            )
            
            
        ]
    

        var privKeys : [Secp256k1_GPU.PrivateKey] = []
        for t in testCases {
            privKeys.append(Secp256k1_GPU.PrivateKey(hexString:t.0))
        }
        let secp256k1obj = Secp256k1_GPU()
        let res = secp256k1obj.generatePublicKeys(privateKeys: privKeys)

        
        
        for i in 0..<res.count {
            var pubKey = testCases[i].2 ? res[i].toCompressed().hex : res[i].toUncompressed().hex
            let pass = pubKey == testCases[i].1 ?  "✅ PASS" : "❌ FAIL"
            
            print("\(pass)  Private Key: \(testCases[i].0)")
            print("         Actual:      \(pubKey)")
            print("         Expected:    \(testCases[i].1)\n")
            
        }
        
    }
    
}

    
    

