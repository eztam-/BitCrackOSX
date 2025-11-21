import Metal
import Foundation
import keysearch
import Testing
import P256K

class TestPubKey: TestBase {
    
    init() {
        super.init(kernelFunctionName: "test_field_sub") // dummy. actuylly not needed
    }
   /*
    func bytePtrToData(bytePtr : UnsafeRawPointer, keySizeBytes : Int, numKeys: Int) -> [Data]{
        let pubKeyArray = bytePtr.bindMemory(to: UInt8.self,capacity: numKeys * keySizeBytes)
        var pubKeysData : [Data] = []
        for i in 0..<numKeys {
            var d = Data()
            for b in 0..<keySizeBytes {
                let index = i * keySizeBytes + b
                d.append(pubKeyArray[index])
            }
            pubKeysData.append(d)
        }
        return pubKeysData
    }
    
    @Test func testRandomPubKeys() throws {
        let numTests = 4096
        print("Running \(numTests) random number tests. Only printing failed results.")
        
        var numFailedTests = 0
       
        var privKeysArr : [String] = []
        var privKeysData : Data = Data()
        for _ in 0..<numTests {
            
            let randomStr = Helpers.generateRandom256BitHex()
            let  limbs = Helpers.hex256ToUInt32Limbs(randomStr)
            privKeysData.append(dataFromUInt32Limbs(limbs))
            privKeysArr.append(randomStr)
        }
        
        let privKeysBuffer = device.makeBuffer(
            bytes: privKeysData.bytes,
            length: MemoryLayout<UInt32>.stride * numTests * 8,
            options: .storageModeShared
        )!;
        
        
        let secp256k1obj = try Secp256k1(on:super.device, batchSize: numTests)
        let (pubKeysComp, pubKeysUncomp) = secp256k1obj.generatePublicKeys(privateKeyBuffer: privKeysBuffer)
        
        let resultPubKeysComp = bytePtrToData(bytePtr: pubKeysComp.contents(), keySizeBytes: 33, numKeys: numTests)
        let resultPubKeysUncomp = bytePtrToData(bytePtr: pubKeysUncomp.contents(), keySizeBytes: 65, numKeys: numTests)
        
        
        for i in 0..<numTests{
            
            // Calculate expected value from lib
            let privateKeyCompressed = try! P256K.Signing.PrivateKey(dataRepresentation: hexStringToData(hexString: privKeysArr[i]), format: .compressed)
            let privateKeyUncomp = try! P256K.Signing.PrivateKey(dataRepresentation: hexStringToData(hexString: privKeysArr[i]), format: .uncompressed)
            let expPubKeyComp = privateKeyCompressed.publicKey.dataRepresentation.hexString
            let expPubKeyUncomp = privateKeyUncomp.publicKey.dataRepresentation.hexString
            
            
            // Testing compressed keys
            let pubKeyComp =  resultPubKeysComp[i].hexString
            if pubKeyComp != expPubKeyComp {
                print("❌ FAIL Comp Private Key: \(privKeysArr[i])")
                print("                  Actual: \(pubKeyComp)")
                print("                Expected: \(expPubKeyComp)\n")
                numFailedTests += 1
            }
            
            // Testing uncompressed keys
            let pubKeyUncomp =  resultPubKeysUncomp[i].hexString
            if pubKeyUncomp != expPubKeyUncomp {
                print("❌ FAIL Uncomp Private Key: \(privKeysArr[i])")
                print("                    Actual: \(pubKeyUncomp)")
                print("                  Expected: \(expPubKeyUncomp)\n")
                numFailedTests += 1
            }
            
        }
        
        let result = numFailedTests == 0 ?  "✅ PASS" : "❌ FAIL"
        print("\(result) \(numFailedTests) of \(numTests) tests have failed")
        assert(numFailedTests==0)
    }
    
    @Test func testPubKey() throws {
        
        
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
        
        
        var privKeysArr : [Data] = []
        var privKeysData : Data = Data()
        for t in testCases {
            
            //Helpers.printLimbs(limbs: Helpers.hex256ToUInt32Limbs(t.0))
            
            let  limbs = Helpers.hex256ToUInt32Limbs(t.0)
            
            privKeysData.append(dataFromUInt32Limbs(limbs))
            privKeysArr.append(dataFromUInt32Limbs(limbs))
        }
        let privKeysBuffer = device.makeBuffer(bytes: privKeysData.bytes,
                                           length: privKeysData.count * MemoryLayout<UInt32>.stride * 8,
                                           options: [])!
        
        
        let secp256k1obj = try Secp256k1(on:super.device, batchSize: testCases.count)
        let (pubKeysComp, pubKeysUncomp) = secp256k1obj.generatePublicKeys(privateKeyBuffer: privKeysBuffer)
        
        let resultPubKeysComp = bytePtrToData(bytePtr: pubKeysComp.contents(), keySizeBytes: 33, numKeys: testCases.count)
        let resultPubKeysUncomp = bytePtrToData(bytePtr: pubKeysUncomp.contents(), keySizeBytes: 65, numKeys: testCases.count)
        
        
        for i in 0..<testCases.count {
            let pubKey = testCases[i].2 ? resultPubKeysComp[i].hexString : resultPubKeysUncomp[i].hexString
            let pass = pubKey == testCases[i].1 ?  "✅ PASS" : "❌ FAIL"
            print("\(pass)  Private Key: \(testCases[i].0)")
            print("         Actual:      \(pubKey)")
            print("         Expected:    \(testCases[i].1)\n")
            
            assert(pubKey == testCases[i].1)
        }
        
    }
    
    func hexStringToData(hexString: String) -> Data{
        var data = Data()
        var hexString = hexString
        if hexString.hasPrefix("0x") {
            hexString = String(hexString.dropFirst(2))
        }
        
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let nextIndex = hexString.index(index, offsetBy: 2)
            if nextIndex <= hexString.endIndex {
                let byteString = hexString[index..<nextIndex]
                if let byte = UInt8(byteString, radix: 16) {
                    data.append(byte)
                }
            }
            index = nextIndex
        }
        return data
    }
    
    
    /// Converts 8 UInt32 limbs into a Data object (little-endian).
    func dataFromUInt32Limbs(_ limbs: [UInt32]) -> Data {
        precondition(limbs.count == 8, "Expected exactly 8 limbs (UInt32).")
        
        var data = Data(capacity: 8 * MemoryLayout<UInt32>.size)
        for limb in limbs {
            var littleEndian = limb.littleEndian
            withUnsafeBytes(of: &littleEndian) { bytes in
                data.append(contentsOf: bytes)
            }
        }
        return data
    }
 */
}




