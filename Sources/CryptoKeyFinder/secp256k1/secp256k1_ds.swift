import Metal
import Foundation

public class SECP256k1GPUds {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLComputePipelineState
    
    public init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            print("Failed to initialize Metal device")
            return nil
        }
        
        self.device = device
        self.commandQueue = commandQueue
        
        // Load the Metal shader
        guard let defaultLibrary = device.makeDefaultLibrary(),
              let kernelFunction = defaultLibrary.makeFunction(name: "private_to_public_keys") else {
            print("Failed to load Metal shader")
            return nil
        }
        
        do {
            self.pipelineState = try device.makeComputePipelineState(function: kernelFunction)
        } catch {
            print("Failed to create pipeline state: \(error)")
            return nil
        }
    }
    
    public struct PrivateKey {
        public let data: Data
        
        public init(_ data: Data) {
            self.data = data
        }
        
        public init(hexString: String) {
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
            self.data = data
        }
        
        func toUInt32Array() -> [UInt32] {
            var result = [UInt32](repeating: 0, count: 8)
            var paddedData = data
            
            // Ensure we have exactly 32 bytes
            if paddedData.count < 32 {
                paddedData = Data(count: 32 - paddedData.count) + paddedData
            } else if paddedData.count > 32 {
                paddedData = paddedData.prefix(32)
            }
            
            paddedData.withUnsafeBytes { bytes in
                for i in 0..<8 {
                    let byteOffset = (7 - i) * 4
                    if byteOffset + 4 <= bytes.count {
                        let value = bytes.load(fromByteOffset: byteOffset, as: UInt32.self)
                        result[i] = value.bigEndian
                    }
                }
            }
            
            return result
        }
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
    
    public func generatePublicKeys(privateKeys: [PrivateKey]) -> [PublicKey]? {
        let count = privateKeys.count
        guard count > 0 else { return [] }
        
        // Convert private keys to UInt32 arrays for Metal
        var privateKeyData = [UInt32]()
        for privateKey in privateKeys {
            privateKeyData.append(contentsOf: privateKey.toUInt32Array())
        }
        
        // Create Metal buffers
        guard let privateKeyBuffer = device.makeBuffer(
            length: MemoryLayout<UInt32>.stride * privateKeyData.count,
            options: .storageModeShared
        ),
        let publicKeyBuffer = device.makeBuffer(
            length: MemoryLayout<UInt32>.stride * count * 16, // 16 UInt32s per public key
            options: .storageModeShared
        ) else {
            print("Failed to create Metal buffers")
            return nil
        }
        
        // Copy private key data to buffer
        privateKeyBuffer.contents().copyMemory(from: privateKeyData, byteCount: privateKeyBuffer.length)
        
        // Create command buffer and encoder
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let commandEncoder = commandBuffer.makeComputeCommandEncoder() else {
            print("Failed to create command encoder")
            return nil
        }
        
        // Configure the compute pipeline
        commandEncoder.setComputePipelineState(pipelineState)
        commandEncoder.setBuffer(privateKeyBuffer, offset: 0, index: 0)
        commandEncoder.setBuffer(publicKeyBuffer, offset: 0, index: 1)
        
        // Calculate thread execution width
        let threadsPerThreadgroup = MTLSize(
            width: min(pipelineState.threadExecutionWidth, count),
            height: 1,
            depth: 1
        )
        let threadgroupsPerGrid = MTLSize(
            width: (count + threadsPerThreadgroup.width - 1) / threadsPerThreadgroup.width,
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
            return nil
        }
        
        // Convert results back to PublicKey objects
        let publicKeyArray = publicKeyBuffer.contents().bindMemory(
            to: UInt32.self,
            capacity: count * 16
        )
        
        var results = [PublicKey]()
        for i in 0..<count {
            let publicKey = PublicKey.fromUInt32Array(
                Array(UnsafeBufferPointer(start: publicKeyArray, count: count * 16)),
                index: i
            )
            results.append(publicKey)
        }
        
        return results
    }
}

// Extension for hex string conversion
extension Data {
    public var hexString: String {
        return map { String(format: "%02x", $0) }.joined()
    }
}
