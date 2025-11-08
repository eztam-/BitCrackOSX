import Foundation
import SQLite

class AddressFileLoader {
    
    private let db: DB
    
    public init(db: DB){
        self.db = db
    }
    
    
    public func loadAddressesFromFile(path: String) throws {

        var approxNumAddresses: Int32 = 0;
        let attribute = try FileManager.default.attributesOfItem(atPath: path)
        if let size = attribute[FileAttributeKey.size] as? NSNumber {
            let sizeInBytes = size.doubleValue
            approxNumAddresses = Int32(sizeInBytes/39.0) // 39 is the average length of BTC addresses with balance in 2025. We don't need to be precise for the progress status.
            print("📄 File size is \(sizeInBytes/1000000.0) MB")
            
        }


        // Opening the same file again to populate the bloomfilter
        guard let file = freopen(path, "r", stdin) else {
            print("Error opening file")
            exit(0) // TODO throw error istead
        }
        defer {
            fclose(file)
        }
        
        print("🧮 Reverse calculating and inserting public key hashes into database")
        var progressCnt:Int = 1;
        var lastPerc :Int = 0
        
        var addrBatch: [Data] = [];
        while let line = readLine() {
            let address = line.trimmingCharacters(in: .whitespaces)
            progressCnt+=1
            
            if address.starts(with: "1") { // Legacy address
                     
     
                // ASYNC Version
                /*
                var nanoTime: UInt64 = 0
                
                // Async batch version
                addrBatch.append(line.trimmingCharacters(in: .whitespaces))
                if addrBatch.count > BATCH_SIZE {
                    let start = DispatchTime.now()
                    let decodedAddresses = Base58.decodeBatchAsync(addrBatch)
                    for i in decodedAddresses {
                        bloomFilter.insert(data: i)
                    }
                    let end = DispatchTime.now()
                    nanoTime = end.uptimeNanoseconds - start.uptimeNanoseconds // <<<<< Difference in nano seconds (UInt64)

                   
                            
                    addrBatch = []
                
                
                    
                    
                    progressCnt+=BATCH_SIZE
                    var procressPercent = Int((100.0/Double(validAddrCount))*Double(progressCnt))
                    if lastPerc < procressPercent{
                        print("Progress: \(procressPercent)%")
                        //print("Bloom \(nanoTime2)")
                        print("BASE58 \(nanoTime/UInt64(BATCH_SIZE))")
                        lastPerc = procressPercent
                    }
                }
            */
                
                //---------------------
                
             
                let start = DispatchTime.now()
                var decodedAddress = Base58.decode(address)
                let end = DispatchTime.now()
                let nanoTime = end.uptimeNanoseconds - start.uptimeNanoseconds // <<<<< Difference in nano seconds (UInt64)

               
                
                decodedAddress = decodedAddress.unsafelyUnwrapped.dropFirst(1).dropLast(4) // Removing the addres byte and checksum
                
                //print("Inserting \(decodedAddress.unsafelyUnwrapped.hex) into bloom filter. Original address: \(line.trimmingCharacters(in: .whitespaces)).hex)")
                let start2 = DispatchTime.now()
                //bloomFilter.insert(data: decodedAddress.unsafelyUnwrapped)
                try db.insert(address: address, publicKeyHash: decodedAddress!.hexString)
                let end2 = DispatchTime.now()
                let nanoTime2 = end2.uptimeNanoseconds - start2.uptimeNanoseconds // <<<<< Difference in nano seconds (UInt64)


              
      
                var progressPercent = Int(min((100.0/Double(approxNumAddresses))*Double(progressCnt),99))
                
                if lastPerc < progressPercent{
                    print("\rProgress: \(progressPercent)%", terminator: "")
                    //print("\r⏳ Progress: \(progressPercent)%  -  BASE58 took \(nanoTime)ns  -   DB insert took \(nanoTime2)ns", terminator: "")
                    fflush(stdout)
                    lastPerc = progressPercent
                }
             
                
                
                //print("Addr \(line)   \(decodedAddress.hex)")
            }
            else if address.starts(with: "3"){ // P2SH address
                // NOT SUPPORTED YET
            }
            else if address.starts(with: "bc1q"){ // Segwit Bech32 address
                // NOT SUPPORTED YET
            }
            else if address.starts(with: "bc1p"){ // Taproot address
                // NOT SUPPORTED YET
            }
        }
        
        print("\r⏳Progress: 100%")
        fflush(stdout)
        print("✅ Imported \(try db.getAddressCount()) supported addresses into the database.")
        
        
    }

    
}
