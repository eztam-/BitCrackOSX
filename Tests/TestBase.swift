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
        
        self.pipelineState = try! Helpers.buildPipelineState(kernelFunctionName: kernelFunctionName)
        self.commandQueue = device.makeCommandQueue()!
        
    }
    
    // =============== Test Helper Methods ================ //
    
    
    
    
    	
}
