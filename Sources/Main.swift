import Foundation
import Metal
import ArgumentParser
import BigNumber

@main
struct Main: ParsableCommand {

    
static let banner = """

╭━━━╮        ╭╮ ╭╮╭━╮       ╭━━━╮          ╭╮
┃╭━╮┃       ╭╯╰╮┃┃┃╭╯       ┃╭━╮┃          ┃┃
┃┃ ╰╋━┳╮ ╭┳━┻╮╭╯┃╰╯╯╭━━┳╮ ╭╮┃╰━━┳━━┳━━┳━┳━━┫╰━╮
┃┃ ╭┫╭┫┃ ┃┃╭╮┃┃ ┃╭╮┃┃┃━┫┃ ┃┃╰━━╮┃┃━┫╭╮┃╭┫╭━┫╭╮┃
┃╰━╯┃┃┃╰━╯┃╰╯┃╰╮┃┃┃╰┫┃━┫╰━╯┃┃╰━╯┃┃━┫╭╮┃┃┃╰━┫┃┃┃
╰━━━┻╯╰━╮╭┫╭━┻━╯╰╯╰━┻━━┻━╮╭╯╰━━━┻━━┻╯╰┻╯╰━━┻╯╰╯
      ╭━╯┃┃┃           ╭━╯┃
      ╰━━╯╰╯           ╰━━╯
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
            help: ArgumentHelp("Either a private key in hexadecimal format from which the search will start like: 02C0FFEEBABE.\n Or 'RANDOM' to start with a random private key.\n Or a random number withing a range of private keys like: RANDOM:1:1FFFF.\n Or a start and end key like: 02C0FFEEBABE:FFFFFFFFFFFF.",
                               valueName: "<start-key>|<start-key>:<end-key>|RANDOM|RANDOM:<start>:<end>",
                              ))
        var startKey: String
        
        
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
            
            do {
                if uncompressedKeySearch && compressedKeySearch {
                    print("Combined search for compressed and uncompressed keys is not yet supported. Please use one of the two options separately.")
                    return
                } else if uncompressedKeySearch {
                    print("Support for uncompressed keys has been dropped")
                    return
                }
                
                print(banner)
                
                let runConfig = try RunConfig(
                    startKeyStr: startKey,
                    outputFile: outputFile,
                    dbFile: dbFile,
                    compressed: compressedKeySearch,
                    verbose: verbose
                )
                try UI.printGPUInfo()
                let bloomFilter = try BloomFilter(db: runConfig.db, batchSize: Properties.TOTAL_POINTS) // TODO: bad access of BATCH_SIZE in KeySearch
                try KeySearch(bloomFilter: bloomFilter, runConfig: runConfig).run()                
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
