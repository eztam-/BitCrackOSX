import Foundation
import Metal


class Hashing {
    
    let commandQueue: MTLCommandQueue
    let device: MTLDevice
    let batchSize: Int
    
    let ripemd160: RIPEMD160
    let sha256: SHA256
    
    init(on device: MTLDevice, batchSize: Int, inputBuffer: MTLBuffer) throws {
        
        self.device = device
        self.batchSize = batchSize
        self.commandQueue = device.makeCommandQueue()!
        
        
        self.sha256 = try SHA256(on: device, batchSize: batchSize, inputBuffer: inputBuffer)
        self.ripemd160 = try RIPEMD160(on: device, batchSize: batchSize, inputBuffer: sha256.getOutputBuffer())
        
    }
    
    
    
    /**
        keyLength:  33 = compressed;  65 = uncompressed
     */
    func run(keyLength: UInt32) -> MTLBuffer {

        let commandBuffer = commandQueue.makeCommandBuffer()!
        sha256.appendCommandEncoder(commandBuffer: commandBuffer, keyLength: keyLength)
        ripemd160.appendCommandEncoder(commandBuffer: commandBuffer)
        
        // Submit work for both SHA256 and RIPEMD160
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        return ripemd160.getOutputBuffer()
    }

}
