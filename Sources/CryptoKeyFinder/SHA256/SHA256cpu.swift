import Foundation
import CryptoKit


/**
 This was an experiment to test Apple Silicon  CPU hardware acceleradted SHA256. It doesn't perform closely as well as the GPU version and is therefore useless. But keeping it for now.
 SHA256 on GPU took: 0.0161 s
 SHA256 on CPU took: 3.711000291 seconds

 */
struct SHA256cpu {
    static func run(iterations: Int) {
        
        let range = ClosedRange(uncheckedBounds: (lower: 0, upper: iterations))

        for item in range {
            let data = Data("Some text \(item)".utf8)
            let digest = SHA256.hash(data: data)
            let hashString = digest.compactMap { String(format: "%02x", $0) }.joined()
            //print(hashString)
        }

    }
}
