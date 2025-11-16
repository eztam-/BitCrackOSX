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
    
    convenience init?() {
        self.init(kernelFunctionName: "test_field_mul") // dummy
    }
    
    init?(kernelFunctionName : String) {
        
        self.commandQueue = device.makeCommandQueue()!

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
    
    
    
    
    	
}
