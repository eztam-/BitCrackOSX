import Foundation
import Metal
import ArgumentParser

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
        
        mutating func run() {
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
            help: ArgumentHelp("Either a private key from which the search will start like: 0000000000000000000000000000000000000000000000000000000000000001. Or 'RANDOM' to start with a random private key.",
                               valueName: "start-key|RANDOM",
                              ))
        var startKey: String
        
        
        @Option( name: .shortAndLong,
                 help: "Path to the output file. The file will contain the found private keys and their corresponding addresses. If not provided, then the output will be written into 'result.txt'.")
        var outputFile: String = "result.txt"

        
        @Option( name: [.customShort("d"), .customLong("database-file")],
                 help: "Path to the database file with .sqlite3 extension.")
        var dbFile: String = "CryptKeySearch.sqlite3"

        
        mutating func run() {
            do {
                print(banner)
                if startKey == "RANDOM" {
                    //print("\n✨ Using random start key")
                    startKey = Helpers.generateRandom256BitHex()
                }
                let db = try DB(dbPath: dbFile)
                let bloomFilter = try BloomFilter(db: db)
                if startKey == "RANDOM" {
                    try KeySearch(bloomFilter: bloomFilter, database: db, outputFile: outputFile).run(startKey: startKey)
                }
                else if startKey.count == 64 && startKey.allSatisfy(\.isHexDigit) {
                    try KeySearch(bloomFilter: bloomFilter, database: db, outputFile: outputFile).run(startKey: startKey)
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
        commandName: Constants.APP_COMMAND_NAME,
        abstract: "Before starting the key search, please import your address file by using the '\(FileLoadCommand.configuration.commandName!)' command. This is only required once before the first start. After that you can use the '\(RunCommand.configuration.commandName!)' command to search for the private keys.",
        subcommands: [FileLoadCommand.self, RunCommand.self],
        //defaultSubcommand: RunCommand.self
    )
    
    
}
