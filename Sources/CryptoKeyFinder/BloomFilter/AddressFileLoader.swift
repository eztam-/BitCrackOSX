import Foundation

struct AddressFileLoader {
    
    
    
    
    static func countValidAddressesInFile(path: String) -> Int {
        print("Counting supported addresses in file \(path)")
        
        // First we only need to count the relevant addresses, so that we can initialize the BloomFilter with the right capacity
        var validAddrCount: Int = 0
        guard let file = freopen(path, "r", stdin) else {
            print("Error opening file")
            exit(0) // TODO: throw error instead
        }
        defer {
            fclose(file)
        }
        
        // Get file size TODO: we could use this to faster calculate the number of addresses once we support all the other address types
        do {
          let attribute = try FileManager.default.attributesOfItem(atPath: path)
          if let size = attribute[FileAttributeKey.size] as? NSNumber {
            let sizeInMB = size.doubleValue / 1000000.0
              print("File size is \(sizeInMB) MB")
          }
        } catch {
          print("Error: \(error)")
        }
        
        while let line = readLine() {
            if line.starts(with: "1") { // Legacy address
                validAddrCount+=1;
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
        print("Number of supported addresses: \(validAddrCount)")
        return validAddrCount;
    }
    
    static func load(path: String) -> BloomFilter2 {
        
        let BATCH_SIZE = 1000
        let validAddrCount = countValidAddressesInFile(path:path)

        print("Instatiating bloom filter")
        var bloomFilter = BloomFilter2(capacity: validAddrCount*256, falsePositiveRate: 0.0001)

        
        // Opening the same file again to populate the bloomfilter
        guard let file = freopen(path, "r", stdin) else {
            print("Error opening file")
            exit(0) // TODO throw error istead
        }
        defer {
            fclose(file)
        }
        
        print("Reverse calculating and inserting public key hashes tinto bloom filter")
        var progressCnt:Int = 1;
        var lastPerc :Int = 0
        
        var addrBatch: [String] = [];
        while let line = readLine() {
         
          
            if line.starts(with: "1") { // Legacy address
                     
     
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
                var decodedAddress = Base58.decode(line.trimmingCharacters(in: .whitespaces))
                let end = DispatchTime.now()
                let nanoTime = end.uptimeNanoseconds - start.uptimeNanoseconds // <<<<< Difference in nano seconds (UInt64)

               
                
                decodedAddress = decodedAddress.unsafelyUnwrapped.dropFirst(1).dropLast(4) // Removing the addres byte and checksum
                
                //print("Inserting \(decodedAddress.unsafelyUnwrapped.hex) into bloom filter. Original address: \(line.trimmingCharacters(in: .whitespaces)).hex)")
                let start2 = DispatchTime.now()
                bloomFilter.insert(data: decodedAddress.unsafelyUnwrapped)
                let end2 = DispatchTime.now()
                let nanoTime2 = end2.uptimeNanoseconds - start2.uptimeNanoseconds // <<<<< Difference in nano seconds (UInt64)


                progressCnt+=1
                var progressPercent = Int((100.0/Double(validAddrCount))*Double(progressCnt))
                if lastPerc < progressPercent{
                    print("Progress: \(progressPercent)%  -  BASE58 took \(nanoTime)ns  -   Bloomfilter insert took \(nanoTime2)ns")
                    lastPerc = progressPercent
                }
                
                
                
                //print("Addr \(line)   \(decodedAddress.hex)")
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
        
        print("Inserted \(validAddrCount) supoorted addresses into the bloom filter")
        
       /*
        if bloomFilter.contains("ssss"){
            print("yes")
        }
        print("no")
        */
        
        
        return bloomFilter
    }

    
}
