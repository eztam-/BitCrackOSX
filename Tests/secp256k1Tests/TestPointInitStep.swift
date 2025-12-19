import Metal
import Foundation
import keysearch
import Testing
import P256K
import BigNumber

final class Secp256k1Tests: TestBase {
    
    init() {
        super.init(kernelFunctionName: "step_points")
    }
    
    func cpuCalculateExpectedPublicKey(privKey: BInt, compressed: Bool) -> String {
        if compressed {
            let privateKey = try! P256K.Signing.PrivateKey(
                dataRepresentation: privKeyToData(privKey: privKey),
                format: .compressed
            )
            return privateKey.publicKey.dataRepresentation.hexString.lowercased()
        } else {
            let privateKey = try! P256K.Signing.PrivateKey(
                dataRepresentation: privKeyToData(privKey: privKey),
                format: .uncompressed
            )
            return privateKey.publicKey.dataRepresentation.hexString.lowercased()
        }
    }
    
    func cpuCalcPublicKeyPoint(privKeyBint: BInt) -> (String, String) {
        let privateKey = try! P256K.Signing.PrivateKey(
            dataRepresentation: privKeyToData(privKey: privKeyBint),
            format: .uncompressed
        )
        let uncompPubKeyStr = privateKey.publicKey.dataRepresentation
        let xBytes = uncompPubKeyStr[1..<33]
        let yBytes = uncompPubKeyStr[33..<65]
        let xHex = xBytes.map { String(format: "%02x", $0) }.joined()
        let yHex = yBytes.map { String(format: "%02x", $0) }.joined()
        return (xHex, yHex)
    }
    
    
    fileprivate func comparePoints(_ pointSet: KeySearchMetal.PointSet, _ TOTAL_POINTS: Int, _ startKeyBint: BInt) -> Int {
        let xPtr = pointSet.xBuffer.contents().bindMemory(to: KeySearchMetal.UInt256.self, capacity: TOTAL_POINTS)
        let yPtr = pointSet.yBuffer.contents().bindMemory(to: KeySearchMetal.UInt256.self, capacity: TOTAL_POINTS)
        
        
        var failCnt = 0
        for i in 0..<TOTAL_POINTS {
            let xGpu = uint256ToHex(xPtr[i])
            let yGpu = uint256ToHex(yPtr[i])
            
            let (xCpu,yCpu) = cpuCalcPublicKeyPoint(privKeyBint: startKeyBint.advanced(by: i))
            
            if xGpu != xCpu || yGpu != yCpu {
                print("❌ Mismatch at index \(i)")
                print("   GPU Point X=\(xGpu) Y=\(yGpu)")
                print("   CPU Point X=\(xCpu) Y=\(yCpu)\n")
                failCnt += 1
            }
        }
        return failCnt
    }
    
    @Test func testPointInit() throws {
        
        let KEYS_PER_THREAD = 16
        let GRID_SIZE = 64
        let TOTAL_POINTS: Int = GRID_SIZE * KEYS_PER_THREAD // DON'T CHANGE THIS!
        let keySearchMetal = try KeySearchMetal(on:  device, compressed: true, totalPoints: TOTAL_POINTS, gridSize: GRID_SIZE)
        let bloomFilter = try BloomFilter(entries: ["b87a8987babdf766f47ad399609d88dc2fd5e5a5"], batchSize: 1)

        let startKeyHexStr = Helpers.generateRandom256BitHex()
        let startKeyBint = BInt(startKeyHexStr, radix: 16)!
        let startKeyLE = Helpers.hex256ToUInt32Limbs(startKeyHexStr)
    
        // TEST POINT INIT KERNEL
        try keySearchMetal.runInitKernel(startKeyLE: startKeyLE, commandBuffer: commandQueue.makeCommandBuffer()!)
        let initFailCnt = comparePoints(keySearchMetal.getPointSet(), TOTAL_POINTS, startKeyBint)
        assert(initFailCnt == 0)
        print("✅ Point Initialization Passed")
        
        
        // TEST POINT STEP KERNEL
        for i in 1..<4 { // Testing three steps
            let hitsBuffer = device.makeBuffer(length: BLOOM_MAX_HITS * MemoryLayout<HitResult>.size, options: .storageModeShared)!
            let resultCount: UInt32 = 0
            let hitCountBuffer = device.makeBuffer(bytes: [resultCount], length: MemoryLayout<UInt32>.size, options: .storageModeShared)!
            
            let cmdBuff = super.commandQueue.makeCommandBuffer()!
            let encoder = cmdBuff.makeComputeCommandEncoder()!
            
            try keySearchMetal.appendStepKernel(
                commandEncoder: encoder,
                bloomFilter: bloomFilter,
                hitsBuffer: hitsBuffer,
                hitCountBuffer: hitCountBuffer)
            encoder.endEncoding()
            cmdBuff.commit()
            cmdBuff.waitUntilCompleted()
            
            
            let stepFailCnt = comparePoints(keySearchMetal.getPointSet(), TOTAL_POINTS, startKeyBint.advanced(by: TOTAL_POINTS*i))
            assert(stepFailCnt == 0)
            print("✅ Point Step \(i) Passed")
        }
       
    }
    
    
    func privKeyToData(privKey: BInt) -> Data {
        // Convert to hex (without 0x)
        var hex = privKey.asString(radix: 16)
        
        // Pad to 64 hex characters (32 bytes)
        if hex.count < 64 {
            hex = String(repeating: "0", count: 64 - hex.count) + hex
        }
        
        // Ensure length is exactly 64 (32 bytes)
        if hex.count > 64 {
            fatalError("Private key larger than 256 bits: \(hex)")
        }
        
        // Convert padded hex to Data
        var data = Data(capacity: 32)
        var index = hex.startIndex
        
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            let byteStr = hex[index..<nextIndex]
            let byte = UInt8(byteStr, radix: 16)!
            data.append(byte)
            index = nextIndex
        }
        
        return data   // big-endian 32-byte data
    }
    
    
    func uint256ToHex(_ v:  KeySearchMetal.UInt256) -> String {
        let arr = [v.limbs.0, v.limbs.1, v.limbs.2, v.limbs.3,
                   v.limbs.4, v.limbs.5, v.limbs.6, v.limbs.7]
        return arr.reversed().map { String(format: "%08x", $0) }.joined()
    }
}
