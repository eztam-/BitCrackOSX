import BigNumber

struct RunConfig {
    
    let startKeyStr: String
    let endKeyStr: String?
    let outputFile: String
    let dbFile: String
    let compressed: Bool
    let verbose: Bool
    let db: DB
    let endKey: BInt?
    let startKey: BInt
   
    enum RunConfigError: Error {
        case invalidStartKeyError
    }
    
    init(
        startKeyStr: String,
        outputFile: String,
        dbFile: String,
        compressed: Bool,
        verbose: Bool
    ) throws {
        self.outputFile = outputFile
        self.dbFile = dbFile
        self.compressed = compressed
        self.verbose = verbose
        self.db = try DB(dbPath: dbFile)
        
        // Parsing the start and end keys
        var endKeyStrTmp:String? = nil
        if startKeyStr == "RANDOM" {
            self.startKeyStr = Helpers.randomHex256(in: ("1", "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364140")) // Max range for BTC keys
        }
        else if startKeyStr.starts(with: "RANDOM:") {
            let parts = startKeyStr.split(separator: ":")
            self.startKeyStr = Helpers.randomHex256(in: (String(parts[1]), String(parts[2])))
        }
        else if startKeyStr.matches(of: /^[0-9A-Fa-f]+:[0-9A-Fa-f]+$/).isEmpty == false {
            let parts = startKeyStr.split(separator: ":")
            self.startKeyStr = Helpers.addTrailingZeros(key: parts[0].uppercased())
            endKeyStrTmp = Helpers.addTrailingZeros(key: parts[1].uppercased())
        }
        else if (startKeyStr.allSatisfy(\.isHexDigit)){
            self.startKeyStr = Helpers.addTrailingZeros(key: startKeyStr.uppercased())
        }
        else {
            print("Invalid start key provided. Please provide a valid 32 byte hex string.")
            throw RunConfigError.invalidStartKeyError
        }

        self.endKeyStr = endKeyStrTmp
        self.startKey = BInt(self.startKeyStr, radix: 16)!
        self.endKey = endKeyStr == nil ? nil : BInt(endKeyStr!, radix: 16)
    }
    
    
    func calcCurrentKey(batchIndex: Int, offset: Int) -> (String, BInt) {
        let privKey = startKey + BInt(batchIndex) * BInt(Properties.TOTAL_POINTS) + BInt(offset)
        let privKeyHex = privKey.asString(radix: 16).uppercased()
        return (Helpers.addTrailingZeros(key: privKeyHex), privKey)
    }
}


