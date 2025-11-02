import Metal
import Foundation
import Testing
import Security
import BigNumber
import CryptKeyFinder

class TestKeyGen: TestBase {
    
    
    init() {
        super.init(kernelFunctionName: "generate_keys_256_offset")!
    }
    
    @Test func testKeyGen() {
        
        let library: MTLLibrary! = try? device.makeDefaultLibrary(bundle: Bundle.module)

        let keyGen = KeyGen(library: library, device: device)
       
        
        var outPtr = keyGen.run(
            startKeyHex: "1111111111111111111111111111111111111111111111111111111111111111",
            batchSize: 5)
        
        privKeysToHex(5, outPtr)
       
        
        
        let start = DispatchTime.now()
        outPtr = keyGen.run(
            startKeyHex: "1111111111111111111111111111111111111111111111111111111111111111",
            batchSize: 100_000_000)
        let took = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
        print("Took: \(took)")
        // Took: 882051916ns
        
        
        privKeysToHex(5, outPtr)
        
        
        

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
    
    
}




