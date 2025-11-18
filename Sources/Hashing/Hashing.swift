import Foundation
import Metal


class Hashing {
    
    let commandQueue: MTLCommandQueue
    let device: MTLDevice
    let batchSize: Int
    
    let ripemd160: RIPEMD160
    let sha256: SHA256
    let secp256k1 : Secp256k1_GPU
    let keyGen : KeyGen
    
    let privKeyBatchSize = Helpers.PRIV_KEY_BATCH_SIZE // Number of base private keys per batch (number of total threads in grid)
    let pubKeyBatchSize =  Helpers.PUB_KEY_BATCH_SIZE // Number of public keys generated per batch
    
    init(on device: MTLDevice, batchSize: Int, startHexKey: String) throws {
        
        self.device = device
        self.batchSize = batchSize
        self.commandQueue = device.makeCommandQueue()!
        
        self.keyGen = try KeyGen(device: device, batchSize: privKeyBatchSize, startKeyHex: startHexKey)
        self.secp256k1 = try Secp256k1_GPU(on:  device, inputBatchSize: privKeyBatchSize, outputBatchSize: pubKeyBatchSize, inputBuffer: keyGen.getOutputBuffer())
        self.sha256 = try SHA256(on: device, batchSize: batchSize, inputBuffer: secp256k1.getOutputBuffer())
        self.ripemd160 = try RIPEMD160(on: device, batchSize: batchSize, inputBuffer: sha256.getOutputBuffer())
        
    }
    
    
    
    /**
        keyLength:  33 = compressed;  65 = uncompressed
     */
    func run(keyLength: UInt32) -> MTLBuffer {

        let commandBuffer = commandQueue.makeCommandBuffer()!
        keyGen.appendCommandEncoder(commandBuffer: commandBuffer)
        secp256k1.appendCommandEncoder(commandBuffer: commandBuffer)
        sha256.appendCommandEncoder(commandBuffer: commandBuffer, keyLength: keyLength)
        ripemd160.appendCommandEncoder(commandBuffer: commandBuffer)
        
        // Submit work for both SHA256 and RIPEMD160
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        return ripemd160.getOutputBuffer()
    }

    func getBasePrivKeyBuffer() -> MTLBuffer {
        return keyGen.getOutputBuffer()
    }
}
