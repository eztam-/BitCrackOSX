import Metal
import keysearch
import Foundation
import Testing


// Helper for string repetition
extension String {
    static func * (left: String, right: Int) -> String {
        return String(repeating: left, count: right)
    }
}

/**
 Base super class for tests
 */
class TestBase {
    
    let device: MTLDevice = Helpers.getSharedDevice()
    let commandQueue: MTLCommandQueue
    let pipelineState: MTLComputePipelineState
    
    convenience init?() throws {
        self.init(kernelFunctionName: "test_field_mul") // dummy
        
    }
    
    init(kernelFunctionName : String) {
        Helpers.TEST_MODE = true
        self.pipelineState = try! Helpers.buildPipelineState(kernelFunctionName: kernelFunctionName)
        self.commandQueue = device.makeCommandQueue()!
        
    }
    
    // =============== Test Helper Methods ================ //
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
}
