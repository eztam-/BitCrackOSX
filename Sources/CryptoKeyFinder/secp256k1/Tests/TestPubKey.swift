// ==================== SWIFT TEST CODE ====================
// Save this as: TestFieldMul.swift

import Metal
import Foundation



class TestPubKey {
    
    
    func runTests(){
        
        
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
                "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798",
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

    
    

