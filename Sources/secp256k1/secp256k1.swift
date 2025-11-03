import Metal
import Foundation

public class Secp256k1_GPU {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLComputePipelineState
    private let bufferSize: Int // Number of private keys per batch
    
    private let privateKeyBuffer: MTLBuffer
    private let publicKeyBuffer: MTLBuffer
    
    public init(on device: MTLDevice, bufferSize : Int) {
        self.bufferSize = bufferSize
        guard let commandQueue = device.makeCommandQueue() else {
            print("Failed to initialize Metal device")
            //return nil
            
            exit(0)
            // TODO
        }
        
        self.device = device
        self.commandQueue = commandQueue
        
        
        //
        let library: MTLLibrary! = try? device.makeDefaultLibrary(bundle: Bundle.module)
        guard let function = library.makeFunction(name: "private_to_public_keys") else {
            fatalError("Failed to load function private_to_public_keys from library")
        }
        do {
            self.pipelineState = try device.makeComputePipelineState(function: function)
        } catch {
            fatalError("Failed to create pipeline state: \(error)")
        }
        
        
        
        // Create Metal buffers
        guard let privateKeyBuffer = device.makeBuffer(
            length: MemoryLayout<UInt32>.stride * bufferSize * 8,
            options: .storageModeShared
        ),
        let publicKeyBuffer = device.makeBuffer(
            length: MemoryLayout<UInt32>.stride * bufferSize * 16, // 16 UInt32s per public key
            options: .storageModeShared
        ) else {
            print("Failed to create Metal buffers")
            //return nil
            exit(0)
            //TODO
        }
        self.privateKeyBuffer = privateKeyBuffer
        self.publicKeyBuffer = publicKeyBuffer

    }
    

    
    public struct PublicKey {
        public let x: Data
        public let y: Data
        
        public init(x: Data, y: Data) {
            self.x = x
            self.y = y
        }
        
        public func toUncompressed() -> Data {
            var result = Data([0x04])  // Uncompressed prefix
            result.append(x)
            result.append(y)
            return result
        }
        
        public func toCompressed() -> Data {
            let lastByte = y.last ?? 0
            let prefix: UInt8 = (lastByte & 1) == 0 ? 0x02 : 0x03
            var result = Data([prefix])
            result.append(x)
            return result
        }
        
        static func fromUInt32Array(_ array: [UInt32], index: Int) -> PublicKey {
            var xData = Data(count: 32)
            var yData = Data(count: 32)
            
            for i in 0..<8 {
                var xValue = array[index * 16 + i].bigEndian
                var yValue = array[index * 16 + 8 + i].bigEndian
                
                xData.withUnsafeMutableBytes { $0.storeBytes(of: xValue, toByteOffset: (7 - i) * 4, as: UInt32.self) }
                yData.withUnsafeMutableBytes { $0.storeBytes(of: yValue, toByteOffset: (7 - i) * 4, as: UInt32.self) }
            }
            
            return PublicKey(x: xData, y: yData)
        }
    }
    

    public func generatePublicKeys(privateKeys: Data) -> [PublicKey] {
            let keyCount = privateKeys.count / 32
            guard keyCount > 0 else { return [] }
       
        
        // Copy private key data to buffer
        //privateKeyBuffer.contents().copyMemory(from: privateKeys, byteCount: privateKeyBuffer.length)
        let privateKeyBuffer = device.makeBuffer(bytes: (privateKeys as NSData).bytes, length: privateKeys.count, options: [])!
        
        // Create command buffer and encoder
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let commandEncoder = commandBuffer.makeComputeCommandEncoder() else {
            print("Failed to create command encoder")
            //return nil
            exit(0)
            //TODO
        }
        
        // Configure the compute pipeline
        commandEncoder.setComputePipelineState(pipelineState)
        commandEncoder.setBuffer(privateKeyBuffer, offset: 0, index: 0)
        commandEncoder.setBuffer(publicKeyBuffer, offset: 0, index: 1)
       
        
        
        
        
        // Calculate thread execution width
        let threadsPerThreadgroup = MTLSize(
            width: min(pipelineState.threadExecutionWidth, keyCount),
            height: 1,
            depth: 1
        )
        let threadgroupsPerGrid = MTLSize(
            width: (keyCount + threadsPerThreadgroup.width - 1) / threadsPerThreadgroup.width,
            height: 1,
            depth: 1
        )
        
        // Dispatch compute threads
        commandEncoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        commandEncoder.endEncoding()

        
        // Execute and wait for completion
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        

        // Check for errors
        if let error = commandBuffer.error {
            print("Metal execution error: \(error)")
            //return nil
            exit(0)
            //TODO
        }
        
        // Convert results back to PublicKey objects
        let publicKeyArray = publicKeyBuffer.contents().bindMemory(
            to: UInt32.self,
            capacity: keyCount * 16
        )
        
        var results = [PublicKey]()
        for i in 0..<keyCount {
            let publicKey = PublicKey.fromUInt32Array(
                Array(UnsafeBufferPointer(start: publicKeyArray, count: keyCount * 16)),
                index: i
            )
            results.append(publicKey)
        }
        
        return results
    }
}


