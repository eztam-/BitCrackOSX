import Foundation
import Metal
import ArgumentParser
import BigNumber

@main
struct Main: ParsableCommand {
    
    
    
    static let banner = """
_________                        __     ____  __.               _________                           .__     
\\_   ___ \\_______ ___.__._______/  |_  |    |/ _|____ ___.__.  /   _____/ ____ _____ _______   ____ |  |__  
/    \\  \\/\\_  __ <   |  |\\____ \\   __\\ |      <_/ __ <   |  |  \\_____  \\_/ __ \\\\__  \\\\_  __ \\_/ ___\\|  |  \\ 
\\     \\____|  | \\/\\___  ||  |_> >  |   |    |  \\  ___/\\___  |  /        \\  ___/ / __ \\|  | \\/\\  \\___|   Y  \\
 \\______  /|__|   / ____||   __/|__|   |____|__ \\___  > ____| /_______  /\\___  >____  /__|    \\___  >___|  /
        \\/        \\/     |__|                  \\/   \\/\\/              \\/     \\/     \\/            \\/     \\/ 
"""
    
    
    
    struct FileLoadCommand: ParsableCommand {
        
        static let configuration = CommandConfiguration(
            commandName: "load",
            abstract: "Loads an address file into the applications database. This is only required once before the first start or if you want to add a different set of addresses.",
        )
        
        @Argument(help: "A file containing bitcoin addresses (one address per row) to be included in the key search.")
        var filePath: String
        
        
        @Option( name: [.customShort("d"), .customLong("database-file")],
                 help: "Path to the database file with .sqlite3 extension.")
        var dbFile: String = "CryptKeySearch.sqlite3"
        
        func run() {
            do {
                print(banner)
                let db = try DB(deleteAndReCreateDB: true, dbPath: dbFile)
                let loader = AddressFileLoader(db:db)
                try loader.loadAddressesFromFile(path: filePath)
            } catch {
                print("Caught error: \(error)")
                print("Type: \(type(of: error))")
                print("Error: \(error.localizedDescription)")
            }
        }
    }
    
    
    struct RunCommand: ParsableCommand {
        
        static let configuration = CommandConfiguration(
            commandName: "run",
            abstract: "Print the product of the values."
        )
        
        @Option(
            name: [.customShort("s"), .customLong("start-key")],
            help: ArgumentHelp("Either a private key from which the search will start like: 0000000000000000000000000000000000000000000000000000000000000001. Or 'RANDOM' to start with a random private key. Or a random number withing a range of private keys like: RANDOM:1:1000",
                               valueName: "<start-key>|RANDOM|RANDOM:<start>:<end>",
                              ))
        var startKey: String
        
        
        @Option(
            name: [.customShort("e"), .customLong("end-key")],
            help: ArgumentHelp("A private key for the end of the search like: 0000000000000000000000000000000000000000000000000000000000100001. If this key is reached, then the application will end.",
                               valueName: "<end-key>",
                              ))
        var endKey: String = ""
        
        
        @Option( name: .shortAndLong,
                 help: "Path to the output file. The file will contain the found private keys and their corresponding addresses. If not provided, then the output will be written into 'result.txt'.")
        var outputFile: String = "result.txt"
        
        
        @Option( name: [.customShort("d"), .customLong("database-file")],
                 help: "Path to the database file with .sqlite3 extension.")
        var dbFile: String = "CryptKeySearch.sqlite3"
        
        
        
        @Flag(name: [.customShort("c")], help: "Search for compressed key types (Legacy and SegWit P2WPKH). This is the default. If combined with uncompressed key search then there will be a small impact to performance.")
        var compressedKeySearch: Bool = false
        
        @Flag(name: [.customShort("u")], help: "Search for uncompressed key types (legacy). If combined with compressed key search then there will be a small impact to performance")
        var uncompressedKeySearch: Bool = false
        
        
        @Flag(name: [.customShort("v"), .customLong("verbose")])
        var verbose: Bool = false
        
        mutating func run() {
            Properties.verbose = verbose
            do {
                if uncompressedKeySearch && compressedKeySearch {
                    print("Combined search for compressed and uncompressed keys is not yet supported. Please use one of the two options separately.")
                    return
                } else if uncompressedKeySearch {
                    print("Support for uncompressed keys has been droped")
                    return
                } else if !uncompressedKeySearch && !compressedKeySearch{
                    Properties.compressedKeySearch = true
                } else {
                    Properties.compressedKeySearch = compressedKeySearch
                    Properties.uncompressedKeySearch = uncompressedKeySearch
                }
                
                print(banner)
                try UI.printGPUInfo()
                let db = try DB(dbPath: dbFile)
                let bloomFilter = try BloomFilter(db: db, batchSize: Properties.TOTAL_POINTS) // TODO: bad access of BATCH_SIZE in KeySearch
                
                var endKeyBint: BInt? = nil
                if !endKey.isEmpty {
                    endKeyBint = BInt(endKey, radix: 16)
                }
                
                if startKey == "RANDOM" {
                    startKey = Helpers.randomHex256(in: ("1", "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364140")) // Max range for BTC keys
                }
                else if startKey.starts(with: "RANDOM:") {
                    let parts = startKey.split(separator: ":")
                    startKey = Helpers.randomHex256(in: (String(parts[1]), String(parts[2])))
                }
                
                if startKey.count == 64 && startKey.allSatisfy(\.isHexDigit) {
                    try KeySearch(bloomFilter: bloomFilter, database: db, outputFile: outputFile, startKeyHex: startKey, endKey: endKeyBint).run()
                }
                print("Invalid start key provided. Please provide a valid 32 byte hex string.")
                
            } catch {
                print("Caught error: \(error)")
                print("Type: \(type(of: error))")
                print("Error: \(error.localizedDescription)")
            }
        }
    }
    
    
    static let configuration = CommandConfiguration(
        commandName: Properties.APP_COMMAND_NAME,
        abstract: "Before starting the key search, please import your address file by using the '\(FileLoadCommand.configuration.commandName!)' command. This is only required once before the first start. After that you can use the '\(RunCommand.configuration.commandName!)' command to search for the private keys.",
        subcommands: [FileLoadCommand.self, RunCommand.self],
        //defaultSubcommand: RunCommand.self
    )
    
    
}
