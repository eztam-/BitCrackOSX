import Metal
import Foundation
import Testing
import Security
import BigNumber
import CryptKeyFinder

class TestKeyGen: TestBase {
    
    
    init() {
        super.init(kernelFunctionName: "generate_keys")!
    }
    
    @Test func testKeyGen() {
        var numFailedTests = 0
        let startKey = "11111111111111111111111111111111111111111111111111111111FFFFFFAA";
        var reference = BInt(startKey, radix: 16)
        
        let keyGen = KeyGen(device: device, startKeyHex: startKey)
       
        // Calculate a first batch of keys
        var outPtr = keyGen.run(
            batchSize: 5000,
            firstBatch: true)

        for hexStr in privKeysToHexStr(5000, outPtr){
            let expected = reference!.asString(radix: 16).uppercased()
            if hexStr.uppercased() != expected {
                print("❌ FAILED - actual: \(hexStr) does not match expected: hex")
                print("          expected: \(expected)")
                numFailedTests += 1
            }
            reference = reference! + 1
        }
        
        //privKeysToHex(5, outPtr)
       
        // Second batch
        outPtr = keyGen.run(
            batchSize: 1000,
            firstBatch: false)

        for hexStr in privKeysToHexStr(1000, outPtr){
            let expected = reference!.asString(radix: 16).uppercased()
            if hexStr.uppercased() != expected {
                print("❌ FAILED - actual: \(hexStr) does not match expected: hex")
                print("          expected: \(expected)")
                numFailedTests += 1
            }
            reference = reference! + 1
        }
                 
        
        
        assert(numFailedTests==0)
        

    }
    
    
    
    
    
    // Convert hex string to little-endian limbs
    func hexToLimbs(_ hex: String) -> [UInt32] {
        var result = [UInt32](repeating: 0, count: 8)
        let clean = hex.replacingOccurrences(of: "0x", with: "")
        let padded = String(repeating: "0", count: max(0, 64 - clean.count)) + clean
        
        // Parse from right to left (little-endian)
        for i in 0..<8 {
            let endIdx = padded.count - (i * 8)
            let startIdx = endIdx - 8
            let start = padded.index(padded.startIndex, offsetBy: startIdx)
            let end = padded.index(padded.startIndex, offsetBy: endIdx)
            let chunk = String(padded[start..<end])
            result[i] = UInt32(chunk, radix: 16) ?? 0
        }
        
        return result
    }
    
    // Convert little-endian limbs to hex string
    func limbsToHex(_ limbs: [UInt32]) -> String {
        var result = ""
        for i in (0..<8).reversed() {
            result += String(format: "%08X", limbs[i])
        }
        return result
    }
    
    
    func privKeysToHex(_ BATCH_SIZE: Int, _ result: UnsafeMutablePointer<UInt32>) {
        for i in 0..<BATCH_SIZE {
            let base = i * 8
            var words: [UInt32] = []
            for j in 0..<8 {
                words.append(result[base + j])
            }
            let hex = limbsToHex(words)
            //print("Sample[\(i)] -> KEY: \(hex)")
            Helpers.printLimbs(limbs: words)
        }
    }
    
    
    
    func privKeysToHexStr(_ BATCH_SIZE: Int, _ result: UnsafeMutablePointer<UInt32>) -> [String]{
        var hexKeys = [String]()
        for i in 0..<BATCH_SIZE {
            let base = i * 8
            var words: [UInt32] = []
            for j in 0..<8 {
                words.append(result[base + j])
            }
            let hex = limbsToHex(words)
            hexKeys.append(hex)
            //print("Sample[\(i)] -> KEY: \(hex)")
            //Helpers.printLimbs(limbs: words)
        }
        return hexKeys
    }
    
    
}




