import Foundation
import SQLite

public class DB {
    
    let dbPath = "CryptKeySearch.sqlite3"
    let db: Connection
    
    let addressesTbl = Table("addresses")
    let addressCol      = Expression<String>("address")
    let publicKeyHashCol = Expression<String>("public_key_hash")
    
    public struct AddressRow {
        let address: String
        let publicKeyHash: String
    }
    
    public init(deleteAndReCreateDB: Bool = false) throws{
        
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
        // Create table
        try db.run(
            addressesTbl.create(ifNotExists: true) { t in
                t.column(addressCol, primaryKey: true)     // TEXT PRIMARY KEY NOT NULL
                t.column(publicKeyHashCol)                 // TEXT
            }
        )
        
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
    
    public  func getAddresses(for publicKeyHash: String, db: Connection) throws -> [AddressRow] {
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
    
    
    
    public   func getAllAddresses() throws -> AnySequence<AddressRow> {
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
