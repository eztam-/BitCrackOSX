import Foundation
import SQLite

class AddressFileLoader {
    
    private let db: DB
    
    public init(db: DB){
        self.db = db
    }
    
    
    func loadAddressesFromFile(path: String) throws {
        
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
            
            
            if line.starts(with: "1") { // Legacy addres
                batch.append(DB.AddressRow(address: line, publicKeyHash: ""))
                
                // if batch is full, process it and reset
                if batch.count >= batchSize {
                    try processBatch(batch)
                    batch.removeAll(keepingCapacity: true) // reuse array memory
                    
                    // Print status
                    var progressPercent = Int(min((100.0/Double(approxNumAddresses))*Double(progressCnt),99))
                    if lastPerc < progressPercent {
                        print("\r   ⏳ Progress: \(progressPercent)%", terminator: "")
                        fflush(stdout)
                        lastPerc = progressPercent
                    }
                    
                }
            }
            else if line.starts(with: "3"){ // P2SH address
                // NOT SUPPORTED YET
            }
            else if line.starts(with: "bc1q"){ // Segwit Bech32 address
                // NOT SUPPORTED YET
            }
            else if line.starts(with: "bc1p"){ // Taproot address
                // NOT SUPPORTED YET
            }
        }

        // process any remaining lines
        if !batch.isEmpty {
            try processBatch(batch)
            print("\r   ⏳ Progress: 100%")
            fflush(stdout)
            print("✅ Imported \(try db.getAddressCount()) supported addresses into the database.")
        }


    }
    
    
    private func processBatch(_ addrBatch: [DB.AddressRow]) throws {
        var addrBatch = addrBatch // make mutable
        for i in addrBatch.indices {
            var decodedAddress = Base58.decode(addrBatch[i].address)
            decodedAddress = decodedAddress.unsafelyUnwrapped.dropFirst(1).dropLast(4) // Removing the addres byte and checksum
            addrBatch[i].publicKeyHash = decodedAddress!.hexString
        }
        try db.insertBatch(addrBatch)
    }
    

    
}
