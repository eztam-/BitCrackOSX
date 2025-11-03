import Foundation
import P256K
import Metal


let device = MTLCreateSystemDefaultDevice()!
let BATCH_SIZE = 5000 // TODO: FIXME: If the key range is smaller than the batch size it doesnt work


@main
struct KeyFinder {
    
    
    static func main() {
        KeyFinder().run()
    }
    

    /// An efficient iterator over a 256-bit integer range represented as 32-byte Data.
    /// Designed for cryptographic key enumeration or GPU batching.
    public struct KeyRange256: Sequence, IteratorProtocol {
        private var current: [UInt8]
        private let end: [UInt8]
        private var finished = false

        /// Initialize with start and end values in hexadecimal form (with or without 0x prefix).
        public init?(startHex: String, endHex: String) {
            guard let startBytes = Self.hexToBytes(startHex),
                  let endBytes   = Self.hexToBytes(endHex),
                  startBytes.count == 32, endBytes.count == 32 else {
                return nil
            }
            self.current = startBytes
            self.end = endBytes
            if Self.isGreater(startBytes, than: endBytes) {
                finished = true
            }
        }

        /// Return the next 32-byte Data value in the range.
        public mutating func next() -> Data? {
            guard !finished else { return nil }

            let result = Data(current) // Wraps without copying unless mutated later

            if !increment256(&current) || Self.isGreater(current, than: end) {
                finished = true
            }
            return result
        }

        // MARK: - Private helpers

        /// Increment the 256-bit number in place. Returns false if overflow occurred.
        @inline(__always)
        private func increment256(_ bytes: inout [UInt8]) -> Bool {
            for i in (0..<32).reversed() {
                let (sum, overflow) = bytes[i].addingReportingOverflow(1)
                bytes[i] = sum
                if !overflow { return true }
            }
            return false // overflow beyond 256 bits
        }

        /// Lexicographic comparison (big-endian).
        @inline(__always)
        private static func isGreater(_ lhs: [UInt8], than rhs: [UInt8]) -> Bool {
            for i in 0..<lhs.count {
                if lhs[i] != rhs[i] {
                    return lhs[i] > rhs[i]
                }
            }
            return false
        }

        /// Convert a hex string to a fixed 32-byte big-endian array.
        private static func hexToBytes(_ hex: String) -> [UInt8]? {
            var s = hex
            if s.hasPrefix("0x") { s.removeFirst(2) }
            guard s.count <= 64 else { return nil }
            s = String(repeating: "0", count: 64 - s.count) + s

            var result = [UInt8]()
            result.reserveCapacity(32)
            var index = s.startIndex
            while index < s.endIndex {
                let next = s.index(index, offsetBy: 2)
                guard let byte = UInt8(s[index..<next], radix: 16) else { return nil }
                result.append(byte)
                index = next
            }
            return result
        }
    }

    
    func run(){
        /*
        let library: MTLLibrary! = try? device.makeDefaultLibrary(bundle: Bundle.module)
        let queue  = (device.makeCommandQueue())!
    

        let keyGen = KeyGen(library: library, device: device)
        let outPtr = keyGen.run(
            startKeyHex: "0000000000000000000000000000000000000000000000000001000000000000")
        privKeysToHex(BATCH_SIZE, outPtr)

        
        exit(0)
         
         */
        
        
        // TODO: check for maximum range wich is: 0xFFFF FFFF FFFF FFFF FFFF FFFF FFFF FFFE BAAE DCE6 AF48 A03B BFD2 5E8C D036 4140
        let keyGen = KeyGen(device: device, startKeyHex: "0000000000000000000000000000000000000000000000000001000000000000")
        let secp256k1obj = Secp256k1_GPU(on:  device, bufferSize: BATCH_SIZE)
        let SHA256 = SHA256gpu(on: device)
        let RIPEMD160 = RIPEMD160(on: device)
        let bloomFilter = AddressFileLoader.load(path: "/Users/x/Downloads/bitcoin_very_short.tsv")
        let t = TimeMeasurement()
        
        
        
        print("Starting on GPU: \(device.name)\n")
        var pubKeyBatch: [Data] = []
        

        
        while true {  // TODO: Shall we introduce an end key, if reached then the application stops?
            
            let startTime = CFAbsoluteTimeGetCurrent()
            
            
            // Generate batch of private keys
            var start = DispatchTime.now()
            var outPtrKeyGen = keyGen.run(batchSize: BATCH_SIZE)
            let secp256k1_input_data = Data(bytesNoCopy: outPtrKeyGen, count: BATCH_SIZE*32, deallocator: .custom({ (ptr, size) in ptr.deallocate() }))
            t.keyGen = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds

            
            
            // Using secp256k1 EC to calculate public keys for the given private keys
            start = DispatchTime.now()
            let pubKeys = secp256k1obj.generatePublicKeys(privateKeys: secp256k1_input_data)
            for pk in pubKeys {
                pubKeyBatch.append(pk.toCompressed())
            }
            t.secp256k1 = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
            
            
            
            // Calculate SHA256 for the batch of public keys
            start = DispatchTime.now()
            let outPtr = SHA256.run(batchOfData: pubKeyBatch)
            //printSha256Output(BATCH_SIZE, outPtr)
            t.sha256 = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
            
            
            
            // Calculate RIPEDM160
            start = DispatchTime.now()
            let ripemd160_input_data = Data(bytesNoCopy: outPtr, count: BATCH_SIZE*32, deallocator: .custom({ (ptr, size) in ptr.deallocate() }))
            let ripemd160_result = RIPEMD160.run(messagesData: ripemd160_input_data, messageCount: BATCH_SIZE)
            //printRipemd160Output(BATCH_SIZE, ripemd160_result)
            t.ripemd160 = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
            
            
            
            // Check RIPEMD160 hashes against the bloom filter
            // Note, we have reverse-calculated BASE58 before inserting addresses into the bloom filter, so we can check directly the RIPEMD160 hashes which is faster.
            start = DispatchTime.now()
            for i in 0..<BATCH_SIZE {
                let addrExists = bloomFilter.contains(pointer: ripemd160_result, length: 5, offset: i*5)
                if addrExists {
                    let privateKeyLimbs = Array(UnsafeBufferPointer(start: outPtrKeyGen.advanced(by: i*8), count: 8))
                    let hexKey = privateKeyLimbs.map { String(format: "%08x", $0) }.reversed().joined()
                    print("#########################################################")
                    //print("Found matching address: \(createData(from: ripemd160_result, offset: i*5, length: 5).hex) for private key: \(hexKey)")
                    print("Found private key for address from list. Private key: \(hexKey)")
                    print("Use any tool like btc_address_dump to get the address for the private key")
                    //print("!!! NOTE !!! At the moment this address is just the RIPEMD160 result, you need to add the address byte and do a base58 decode and a checksum validation to get the actual address.")
                    print("#########################################################")
                }
            }
            t.bloomFilter = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
            //print("bloomfilter took: \(end.uptimeNanoseconds - start.uptimeNanoseconds)ns")
            // The following would do all the further steps to calculate the address but we don't need it, since the addresses in the bloomfilter
            // are already BASE58 decoded and also the version byte and checksum were removed.
            /*
             // TODO: This is not very performant. Its better adding it in the metal file of ripemd160 at the end
             var versionedRipemd160 = convertPointerToDataArray(ptr:ripemd160_result, count: 5*BATCH_SIZE, dataItemLength: 5)
             for i in 0..<BATCH_SIZE{
             versionedRipemd160[i].insert( 0x00, at: 0) // 0x00 Mainnet
             }
             
             
             // Calculate SHA256 for the RIPEMD160 hashes + version byte
             let sha256_out2 = SHA256.run(batchOfData: versionedRipemd160)
             //printSha256Output(BATCH_SIZE, sha256_out2)
             
             let sha256_out2_data = convertPointerToDataArray2(ptr:sha256_out2, count: 8*BATCH_SIZE, chunkSize: 8)
             //print(sha256_out2_data[0].hex)
             // Calculate a sechond SHA256 on the previous SHA256 hash
             let sha256_out3 = SHA256.run(batchOfData: sha256_out2_data)
             //printSha256Output(BATCH_SIZE, sha256_out3)
             
             
             //for i in stride(from: 0, to: BATCH_SIZE*8, by: 8) {
             for i in 0..<BATCH_SIZE {
             let checksum = sha256_out3[i*8]
             //print(String(format: "Checksum: %08X", checksum.bigEndian))
             
             var bitcoinAddress = Data(versionedRipemd160[i])
             
             bitcoinAddress.append(withUnsafeBytes(of: checksum) { Data($0) })
             let bitcoinAddressStr = Base58.encode(bitcoinAddress)
             //print("Bitcoin Address: \(bitcoinAddressStr)")
             }
             
             */
            let endTime = CFAbsoluteTimeGetCurrent()
            let elapsed = endTime - startTime
            let hashesPerSec = Double(BATCH_SIZE) / elapsed
            t.keysPerSec = String(format: "--------[ %.0f keys/s ]--------", hashesPerSec)
            
            
            pubKeyBatch = []  //clearing batch
        }
        
    }
    

    
    
    
    /// Converts a pointer to UInt32 values into an array of `Data` objects.
    /// Each `Data` chunk will contain `chunkSize` UInt32 values (default: 4).
    func convertPointerToDataArray2(
        ptr: UnsafeMutablePointer<UInt32>,
        count: Int,
        chunkSize: Int
    ) -> [Data] {
        precondition(chunkSize > 0, "chunkSize must be greater than zero")
        precondition(count % chunkSize == 0, "count must be a multiple of chunkSize")
        
        var result: [Data] = []
        result.reserveCapacity(count / chunkSize)
        
        for i in stride(from: 0, to: count, by: chunkSize) {
            let chunkPtr = ptr.advanced(by: i)
            let data = Data(bytes: chunkPtr, count: chunkSize * MemoryLayout<UInt32>.size)
            result.append(data)
        }
        
        return result
    }
    
    func convertPointerToDataArray(ptr: UnsafeMutablePointer<UInt32>, count: Int, dataItemLength: Int) -> [Data] {
        
        
        var result: [Data] = []
        result.reserveCapacity(count / dataItemLength)
        
        for i in stride(from: 0, to: count, by: dataItemLength) {
            // Create a raw pointer for the dateItemLength UInt32 words
            let chunkPtr = ptr.advanced(by: i)
            
            // Create Data directly from memory (no copy)
            let data = Data(bytes: chunkPtr, count: dataItemLength * MemoryLayout<UInt32>.size)
            
            result.append(data)
        }
        
        return result
    }
    
    
    
    
    // Convert 5 UInt32 words (as written by kernel) into canonical 20-byte hex string.
    // The kernel produces words in host-endian uints (native endianness). RIPEMD-160 digest bytes are defined
    // as the little-endian concatenation of the 5 32-bit words. So we take each UInt32 and write its bytes LE -> hex.
    func ripemdWordsToHex(_ words: [UInt32]) -> String {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(20)
        for w in words {
            let le = w.littleEndian
            bytes.append(UInt8((le >> 0) & 0xff))
            bytes.append(UInt8((le >> 8) & 0xff))
            bytes.append(UInt8((le >> 16) & 0xff))
            bytes.append(UInt8((le >> 24) & 0xff))
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
    
    
    // Convert output words (uint32) to hex string (big-endian per SHA-256 spec)
    func hashWordsToHex(_ words: [UInt32]) -> String {
        // SHA-256 words are stored as big-endian words in the algorithm; the kernel computed in uint (host little-endian).
        // We need to print each word as big-endian bytes in hex.
        let beBytes: [UInt8] = words.flatMap { w -> [UInt8] in
            let be = w // .bigendian
            return [
                UInt8((be >> 24) & 0xff),
                UInt8((be >> 16) & 0xff),
                UInt8((be >> 8) & 0xff),
                UInt8(be & 0xff)
            ]
        }
        return beBytes.map { String(format: "%02x", $0) }.joined()
    }
    
    
    // TEST convert words to little endian
    func toLittleEndian(_ words: [UInt32]) -> Data {
        // SHA-256 words are stored as big-endian words in the algorithm; the kernel computed in uint (host little-endian).
        // We need to print each word as big-endian bytes in hex.
        let beBytes: [UInt8] = words.flatMap { w -> [UInt8] in
            let be = w.bigEndian
            return [
                UInt8((be >> 24) & 0xff),
                UInt8((be >> 16) & 0xff),
                UInt8((be >> 8) & 0xff),
                UInt8(be & 0xff)
            ]
        }
        return Data(beBytes)
        //return beBytes.map { String(format: "%02x", $0) }.joined()
    }
    
    
    func printSha256Output(_ BATCH_SIZE: Int, _ outPtr: UnsafeMutablePointer<UInt32>) {
        // Print output
        for i in 0..<BATCH_SIZE {
            var words: [UInt32] = []
            for j in 0..<8 {
                let w = outPtr[i*8 + j].bigEndian // convert to big-endian for correct hex order
                words.append(w)
                
            }
            let hex = hashWordsToHex(words)
            print("Message[\(i)] -> SHA256: \(hex)")
            
        }
    }
    
    
    func printRipemd160Output(_ BATCH_SIZE: Int, _ ripemd160_result: UnsafeMutablePointer<UInt32>) {
        for i in 0..<BATCH_SIZE {
            let base = i * 5
            var words: [UInt32] = []
            for j in 0..<5 {
                words.append(ripemd160_result[base + j])
            }
            let hex = ripemdWordsToHex(words)
            print("Sample[\(i)] -> RIPEMD: \(hex)")
        }
    }
    
    
    func privKeysToHex(_ BATCH_SIZE: Int, _ result: UnsafeMutablePointer<UInt32>) {
        for i in 0..<BATCH_SIZE {
            let base = i * 8
            var words: [UInt32] = []
            for j in 0..<8 {
                words.append(result[base + j])
            }
            let hex = ripemdWordsToHex(words)
            print("Sample[\(i)] -> KEY: \(hex)")
        }
    }
}









