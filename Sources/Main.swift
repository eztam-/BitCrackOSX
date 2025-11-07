import Foundation
import Metal
import ArgumentParser

@main
struct Main: ParsableCommand {
    
    
    struct FileImportCommand: ParsableCommand {
        
        static let configuration = CommandConfiguration(
            commandName: "import",
            abstract: "Loads an address file into the applications database. This is only required once before the first start or if you want to add a different set of addresses.",
            aliases: ["i"])
        
        @Argument(help: "A file containing bitcoin addresses (one address per row) to be included in the key search.")
        var filePath: String
        
        mutating func run() {
            print("FileLoad \(filePath)")
        }
    }
    
    
    struct KeySearchCommand: ParsableCommand {
        
        static let configuration = CommandConfiguration(
            commandName: "keysearch",
            abstract: "Print the product of the values."
        )
        
        @Option(name: .shortAndLong,
                help: "Any Bitcoin private key to start with. Always provide a full length key of 32 bytes in hexadecimal representation like: 0000000000000000000000000000000000000000000000000000000000000001. If not provided, a random key will be used.")
        var startKey: String = ""
     
        @Option( name: .shortAndLong,
                 help: "Path to the output file. The file will contain the private keys and their corresponding addresses. If not provided, the output will be printed to the console.")
        var outputFile: String = ""

        mutating func run() {
            if startKey.isEmpty{
                startKey = Helpers.generateRandom256BitHex()
                KeyFinder().run(startKey: startKey)
            }
            else if startKey.count == 64 && startKey.allSatisfy(\.isHexDigit) {
                KeyFinder().run(startKey: startKey)
            }
            print("Invalid start key provided. Please provide a valid 32 byte hex string.")
        }
    }
    
    

    
    
    
    
    static let configuration = CommandConfiguration(
        commandName: "CryptKeySearch",
        abstract: "Before starting the key search, please import your address file by using the 'file-load'command. This is only required once before the first start. After that you can use the 'run' command to search for the private keys.",
        subcommands: [FileImportCommand.self, KeySearchCommand.self],
        defaultSubcommand: KeySearchCommand.self
    )
    
    

}
