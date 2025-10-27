import Foundation
import Metal

struct Secp256k1{
    
    
    static func test() throws {


        func hexToData(_ hex: String) -> Data {
            var h = hex
            if h.count % 2 != 0 { h = "0" + h }
            var d = Data()
            var i = h.startIndex
            while i < h.endIndex {
                let j = h.index(i, offsetBy: 2)
                let byte = UInt8(h[i..<j], radix: 16)!
                d.append(byte)
                i = j
            }
            return d
        }
        func hex(_ d: Data) -> String { d.map{ String(format: "%02x",$0)}.joined() }

        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("No Metal device available")
        }

        let metalSourceURL = URL(fileURLWithPath: "./secp256k1.metal") // adjust path as needed
        let source = try String(contentsOf: metalSourceURL, encoding: .utf8)
        let library = try device.makeLibrary(source: source, options: nil)
        guard let fn = library.makeFunction(name: "secp256k1_generate_pubkeys") else {
            fatalError("Kernel not found")
        }
        let pipeline = try device.makeComputePipelineState(function: fn)
        let queue = device.makeCommandQueue()!

        // Test private keys: k=1 and k=2 (big-endian 32 bytes)
        let privHex = [
            "0000000000000000000000000000000000000000000000000000000000000001",
            "0000000000000000000000000000000000000000000000000000000000000002"
        ]
        let count = privHex.count
        var inData = Data()
        for h in privHex {
            inData.append(hexToData(h))
        }

        // choose compressed or not
        let compressed = true
        let outStride = compressed ? 33 : 65
        let outSize = outStride * count

        let inBuf = device.makeBuffer(bytes: (inData as NSData).bytes, length: inData.count, options: [])!
        let outBuf = device.makeBuffer(length: outSize, options: [])!

        var cnt = UInt32(count)
        let cntBuf = device.makeBuffer(bytes: &cnt, length: MemoryLayout<UInt32>.size, options: [])!
        var stride32 = UInt32(outStride)
        let strideBuf = device.makeBuffer(bytes: &stride32, length: MemoryLayout<UInt32>.size, options: [])!
        var comp: UInt32 = compressed ? 1 : 0
        let compBuf = device.makeBuffer(bytes: &comp, length: MemoryLayout<UInt32>.size, options: [])!

        let commandBuffer = queue.makeCommandBuffer()!
        let encoder = commandBuffer.makeComputeCommandEncoder()!
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(inBuf, offset: 0, index: 0)
        encoder.setBuffer(outBuf, offset: 0, index: 1)
        encoder.setBuffer(cntBuf, offset: 0, index: 2)
        encoder.setBuffer(strideBuf, offset: 0, index: 3)
        encoder.setBuffer(compBuf, offset: 0, index: 4)

        let gridSize = MTLSize(width: count, height: 1, depth: 1)
        let w = pipeline.threadExecutionWidth
        let tgSize = MTLSize(width: min(w, count), height: 1, depth: 1)
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: tgSize)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let outPtr = outBuf.contents().bindMemory(to: UInt8.self, capacity: outSize)
        for i in 0..<count {
            let slice = Data(bytes: outPtr + i * outStride, count: outStride)
            print("priv:", privHex[i])
            print("pub :", hex(slice))
        }

        
    }
    
 
    
}
