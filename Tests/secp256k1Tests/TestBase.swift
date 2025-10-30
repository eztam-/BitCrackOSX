import Metal
import Foundation
import Testing

/**
 Base super class for tests
 */
class TestBase {
    
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let pipelineState: MTLComputePipelineState
    
    
    init?(kernelFunctionName : String) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            print("❌ Failed to initialize Metal device")
            return nil
        }
        
        self.device = device
        self.commandQueue = commandQueue

        let library: MTLLibrary! = try? device.makeDefaultLibrary(bundle: Bundle.module)

        guard let function = library.makeFunction(name: kernelFunctionName) else {
            fatalError("Failed to load function \(kernelFunctionName) from library")
        }
        do {
            self.pipelineState = try device.makeComputePipelineState(function: function)
        } catch {
            fatalError("Failed to create pipeline state: \(error)")
        }
        
    }
    
    // =============== Test Helper Methods ================ //
    
    func generateRandom256BitHex() -> String {
        var bytes = [UInt8](repeating: 0, count: 32) // 32 bytes = 256 bits
        let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard result == errSecSuccess else {
            fatalError("Failed to generate secure random bytes")
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
    	
}
