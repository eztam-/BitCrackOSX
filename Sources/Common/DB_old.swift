import Foundation
import SQLite

public class DB_old {
    
    let dbPath: String
    let db: Connection
    
    let addressesTbl = Table("addresses")
    let addressCol      = Expression<String>("address")
    let publicKeyHashCol = Expression<String>("public_key_hash")
    
    public struct AddressRow {
        var address: String
        var publicKeyHash: String
    }
    
    public init(deleteAndReCreateDB: Bool = false, dbPath: String = "CryptKeySearch.sqlite3") throws{
        self.dbPath = dbPath
        
        var dbFileExists = FileManager.default.fileExists(atPath: dbPath)
        
        if dbFileExists && deleteAndReCreateDB {
            try FileManager.default.removeItem(atPath: dbPath)
            print("✅ Database '\(dbPath)' deleted")
            dbFileExists = false
        }
        
        self.db = try Connection(dbPath)
        if !dbFileExists {
            try initializeDB()
            print("✅ Database '\(dbPath)' initialized")
        }
    }
    
    
    public func initializeDB() throws {
        
        // TODO only do this during insert and reverse / remove again after insert is done
        try db.run("PRAGMA journal_mode = WAL;")
        try db.run("PRAGMA synchronous = OFF;")
        try db.run("PRAGMA temp_store = MEMORY;")
        try db.run("PRAGMA cache_size = 100000;")
        try db.run("PRAGMA locking_mode = EXCLUSIVE;")
        
        try db.transaction{
            
        // Create table
        try db.run(
            addressesTbl.create(ifNotExists: true) { t in
                t.column(addressCol, primaryKey: true)     // TEXT PRIMARY KEY NOT NULL
                t.column(publicKeyHashCol)                 // TEXT
            }
        )
        }
    }
    
    public func createIndex() throws {
        // Create index on public_key_hash
        try db.run(
            addressesTbl.createIndex(publicKeyHashCol,unique: false, ifNotExists: true)
        )
    }
    
    public func insert(address: String, publicKeyHash: String) throws {
        let insertStmt = addressesTbl.insert(
            addressCol <- address,
            publicKeyHashCol <- publicKeyHash
        )
        try db.run(insertStmt)
    }
    
    public func insertBatch(_ rows: [AddressRow]) throws {
        guard !rows.isEmpty else { return }

        // Build placeholders (?, ?) for each row
        let valuePlaceholders = Array(repeating: "(?, ?)", count: rows.count).joined(separator: ", ")
        
        // Flatten the values into a single array and cast to [Binding?]
        let bindings: [Binding?] = rows.flatMap { [$0.address as Binding?, $0.publicKeyHash as Binding?] }
        let sql = "INSERT INTO addresses (address, public_key_hash) VALUES \(valuePlaceholders);"
        try db.run(sql, bindings)
    }
    
    public  func getAddresses(for publicKeyHash: String) throws -> [AddressRow] {
        let query = addressesTbl.filter(publicKeyHashCol == publicKeyHash)
        var results: [AddressRow] = []
        for row in try db.prepare(query) {
            results.append(
                AddressRow(
                    address: row[addressCol],
                    publicKeyHash: row[publicKeyHashCol]
                )
            )
        }
        return results
    }
    
    
    
    public func getAllAddresses() throws -> AnySequence<AddressRow> {
        let seq = try db.prepare(addressesTbl)
        return AnySequence(seq.lazy.map { row in
            AddressRow(
                address: row[self.addressCol],
                publicKeyHash: row[self.publicKeyHashCol]
            )
        })
    }
    
    
    public func getAddressCount() throws -> Int {
        return try db.scalar(addressesTbl.count)
    }
    
    
}
