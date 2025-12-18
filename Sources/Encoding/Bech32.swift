import Foundation

struct Bech32 {
    private static let charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
    private static let charsetRev: [Character: Int] = {
        var dict = [Character: Int]()
        for (i, c) in charset.enumerated() { dict[c] = i }
        return dict
    }()
    
    private static let generator: [UInt32] = [
        0x3b6a57b2,
        0x26508e6d,
        0x1ea119fa,
        0x3d4233dd,
        0x2a1462b3
    ]
    
    private static func polymod(_ values: [UInt8]) -> UInt32 {
        var chk: UInt32 = 1
        for v in values {
            let top = chk >> 25
            chk = (chk & 0x1ffffff) << 5 ^ UInt32(v)
            for i in 0..<5 {
                if ((top >> i) & 1) != 0 {
                    chk ^= generator[i]
                }
            }
        }
        return chk
    }
    
    private static func hrpExpand(_ hrp: String) -> [UInt8] {
        var result = [UInt8]()
        for c in hrp.utf8 { result.append(c >> 5) }
        result.append(0)
        for c in hrp.utf8 { result.append(c & 31) }
        return result
    }
    
    static func decode(_ bech32: String) -> (hrp: String, data: [UInt8])? {
        let lower = bech32.lowercased()
        guard lower == bech32 || bech32.uppercased() == bech32 else { return nil }
        
        guard let pos = bech32.lastIndex(of: "1"), pos != bech32.startIndex else {
            return nil
        }
        
        let hrp = String(bech32[..<pos])
        let dataPart = bech32[bech32.index(after: pos)...]
        
        var data = [UInt8]()
        for c in dataPart {
            guard let idx = charsetRev[c] else { return nil }
            data.append(UInt8(idx))
        }
        
        guard data.count >= 6 else { return nil }
        
        let values = hrpExpand(hrp) + data
        guard polymod(values) == 1 else { return nil }
        
        return (hrp, Array(data.dropLast(6)))
    }
}
