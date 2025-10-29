// ==================== SWIFT TEST CODE ====================
// Save this as: TestFieldMul.swift

import Metal
import Foundation



class TestPubKey {
    
    
    func runTests(){
        
        do {
            let secp256k1obj = SECP256k1GPUds()
            let privKeys = [
                SECP256k1GPUds.PrivateKey(hexString: "0000000000000000000000000000000000000000000000000000000000000001"),
                SECP256k1GPUds.PrivateKey(hexString: "0000000000000000000000000000000000000000000000000000000000000002"),
                SECP256k1GPUds.PrivateKey(hexString: "0000000000000000000000000000000000000000000000000000000000000003"),
                SECP256k1GPUds.PrivateKey(hexString: "000000000000000000000000000000000A100000000000000000000000000003")
            ]
            let res = secp256k1obj.generatePublicKeys(privateKeys: privKeys)

            

            
            var correct = res[0].toCompressed().hex != "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798" ? "❌ FAIL" : "✅ PASS"
            print("\(correct) Expected: 0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798 \n          Actual: \(res[0].toCompressed().hex)" )
            // uncompressed
            correct = res[0].toUncompressed().hex != "0479be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8"  ? "❌ FAIL" : "✅ PASS"
            print("\(correct) Expected: 0479be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8 \n          Actual: \(res[0].toUncompressed().hex)" )

            correct = res[1].toCompressed().hex != "02c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5"  ? "❌ FAIL" : "✅ PASS"
            print("\(correct) Expected: 02c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5 \n          Actual: \(res[1].toCompressed().hex)" )
            
            correct = res[2].toCompressed().hex != "02f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"  ? "❌ FAIL" : "✅ PASS"
            print("\(correct) Expected: 02f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9 \n          Actual: \(res[2].toCompressed().hex)" )
            
            correct = res[3].toCompressed().hex != "0206a7d89b595868e231e3474a37051185a8c4d344f02edd122258fb355cfd6000"  ? "❌ FAIL" : "✅ PASS"
            print("\(correct) Expected: 0206a7d89b595868e231e3474a37051185a8c4d344f02edd122258fb355cfd6000 \n          Actual: \(res[3].toCompressed().hex)" )
            
            // uncompressed
            correct = res[3].toUncompressed().hex != "0406a7d89b595868e231e3474a37051185a8c4d344f02edd122258fb355cfd6000f50b6b9828f3d11e65825bf2f26fc735817eda1e7b601849292848980b3281de"  ? "❌ FAIL" : "✅ PASS"
            print("\(correct) Expected: 0406a7d89b595868e231e3474a37051185a8c4d344f02edd122258fb355cfd6000f50b6b9828f3d11e65825bf2f26fc735817eda1e7b601849292848980b3281de \n          Actual: \(res[3].toUncompressed().hex)" )
            
            
            // Hex conversion is correct:
            //print(UInt256(words: SECP256k1GPUds.PrivateKey(hexString: "0000000000000000000000000000000000000000000000000000000000000002").toUInt32Array()).hexString)
            
 
            
        } catch {
            print("Secp256k1.test() failed: \(error)")
            exit(1)
        }
        
    }
    
}

    
    

