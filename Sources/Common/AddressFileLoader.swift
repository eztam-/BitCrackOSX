import Foundation
import SQLite

class AddressFileLoader {
    
    private let db: DB
    
    public init(db: DB){
        self.db = db
    }
    
    
    func loadAddressesFromFile(path: String) throws {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        print("✅ Loading address file \(path)")
        var approxNumAddresses: Int32 = 0;
        let attribute = try FileManager.default.attributesOfItem(atPath: path)
        if let size = attribute[FileAttributeKey.size] as? NSNumber {
            let sizeInBytes = size.doubleValue
            approxNumAddresses = Int32(sizeInBytes/39.0) // 39 is the average length of BTC addresses with balance in 2025. We don't need to be precise for the progress status.
            print("   📄 File size is \(sizeInBytes/1000000.0) MB")
            
        }
        
        
        guard let file = freopen(path, "r", stdin) else {
            print("Error opening file")
            exit(0) // TODO throw error istead
        }
        defer {
            fclose(file)
        }
        
        
        print("🧮 Reverse calculating and inserting public key hashes into database")
        
        let batchSize = 5000
        var batch = [DB.AddressRow]()
        var progressCnt = 1
        var lastPerc = 0
        
        while var line = readLine() {
            progressCnt+=1
            line = line.trimmingCharacters(in: .whitespaces)
            
            let hash160 = addressTohash160(line)
            if hash160 != nil {
                batch.append(DB.AddressRow(address: line, publicKeyHash: hash160!.hexString))
            }
            
            // if batch is full, process it and reset
            if batch.count >= batchSize {
                try db.insertBatch(batch)
                batch.removeAll(keepingCapacity: true) // reuse array memory
                
                // Print status
                let progressPercent = Int(min((100.0/Double(approxNumAddresses))*Double(progressCnt),99))
                if lastPerc < progressPercent {
                    print("\r   ⏳ Progress: \(progressPercent)%", terminator: "")
                    fflush(stdout)
                    lastPerc = progressPercent
                }
            }
        }
        
        // process any remaining lines
        if !batch.isEmpty {
            try db.insertBatch(batch)
            print("\r   ⏳ Progress: 100%")
            fflush(stdout)
            print("✅ Imported \(try db.getAddressCount()) supported addresses into the database.")
        }
        let endTime = CFAbsoluteTimeGetCurrent()
        
        try db.createIndex() // We create the index after insertion for better performance of b-tree index -> log(n)
        let endTime2 = CFAbsoluteTimeGetCurrent()
        
        let dataLoadTimeM = String(format: "%.2f", (endTime-startTime)/60.0)
        let indexingTimeM = String(format: "%.2f", (endTime2-startTime)/60.0)
        
        print("Data load took: \(dataLoadTimeM)min, indexing took: \(indexingTimeM)min)")
        
    }
    
    
    
    
    
    // Returns the HASH160 (pub key hash) for supported address types. Otherwise nil
    private func addressTohash160(_ address: String) -> Data?  {
        
        // Legacy addresses
        if address.starts(with: "1") {
            var decodedAddress = Base58.decode(address)!
            return decodedAddress.dropFirst(1).dropLast(4) // Removing the addres byte and checksum
        }
        
        // Segwit Bech32 address
        else if address.starts(with: "bc1q"){
            return hash160FromSegWitAddress(address)
        }
        
        /*
         else if address.starts(with: "3"){ // P2SH address
         // NOT SUPPORTED YET
         }
         else if address.starts(with: "bc1p"){ // Taproot address
         // NOT SUPPORTED YET
         }
         */
        
        return nil
    }
    
    
    
    
    func convert5to8bits(_ input: [UInt8], pad: Bool = false) -> [UInt8]? {
        var acc: Int = 0
        var bits: Int = 0
        var output = [UInt8]()
        let maxv = (1 << 8) - 1
        
        for value in input {
            if value > 31 { return nil }
            acc = (acc << 5) | Int(value)
            bits += 5
            
            while bits >= 8 {
                bits -= 8
                output.append(UInt8((acc >> bits) & maxv))
            }
        }
        
        if !pad {
            if bits >= 5 { return nil }
            if ((acc << (8 - bits)) & maxv) != 0 { return nil }
        }
        
        return output
    }
    
    
    // Extract HASH160 from SegWit addr
    func hash160FromSegWitAddress(_ address: String) -> Data? {
        guard let (hrp, data) = Bech32.decode(address) else {
            print("Invalid Bech32")
            return nil
        }
        
        guard let version = data.first else { return nil }
        let program5 = Array(data.dropFirst())
        
        guard let program8 = convert5to8bits(program5, pad: false) else {
            print("Invalid 5→8 bit conversion")
            return nil
        }
        
        // Only P2WPKH (version 0, 20-byte program)
        // We don't support P2WSH and Taproot (both also starting with bc1q)
        // This is because only P2WPKH supports the same hash function RIPEMD160(SHA(privKey))
        guard version == 0, program8.count == 20 else {
            //print("Not a P2WPKH SegWit address")
            return nil
        }
        
        return Data(program8)
    }
    
    
}
