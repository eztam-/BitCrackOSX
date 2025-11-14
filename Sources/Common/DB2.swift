import Foundation
import GRDB


public class DB {
    
    let dbPath: String
    public let dbQueue: DatabaseQueue
    
    
    public struct AddressRow: Codable, Identifiable, FetchableRecord, PersistableRecord {
        public var id: String
        public var pubKeyHash: String
        
        public static let databaseTableName = "addresses"

        
        public enum Columns {
            static let id = Column(CodingKeys.id)
            static let pubKeyHash = Column(CodingKeys.pubKeyHash)
        }
    }
    
    public init(deleteAndReCreateDB: Bool = false, dbPath: String = "CryptKeySearch.sqlite3") throws{
        self.dbPath = dbPath
        
        var dbFileExists = FileManager.default.fileExists(atPath: dbPath)
        
        if dbFileExists && deleteAndReCreateDB {
            try FileManager.default.removeItem(atPath: dbPath)
            print("✅ Database '\(dbPath)' deleted")
            dbFileExists = false
        }
        
        self.dbQueue = try DatabaseQueue(path: dbPath)

        if !dbFileExists {
            try initializeDB()
            print("✅ Database '\(dbPath)' initialized")
        }
    }
    
    
    public func initializeDB() throws {
        
        try dbQueue.write { db in
            try db.create(table: "addresses") { t in
                t.column("id", .text).notNull()
                t.column("pubKeyHash", .text).notNull()
                t.primaryKey(["id"])
            }
        }
        
        try dbQueue.inDatabase { db in
                    try db.execute(sql: "PRAGMA synchronous = OFF")
                    try db.execute(sql: "PRAGMA journal_mode = MEMORY")
        }
    }
    
    // Creating the index after data was inserted is faster
    public func createIndex() throws {
        try dbQueue.write { db in
            try db.create(index: "idx_addresses_pubKeyHash", on: "addresses", columns: ["pubKeyHash"], ifNotExists: true)
        }
    }
    
    public func insert(address: String, publicKeyHash: String) throws {
        
    }
    
    public func insertBatch(_ rows: [AddressRow]) throws {
        guard !rows.isEmpty else { return }
        
        let values = Array(repeating: "(?, ?)", count: rows.count).joined(separator: ", ")
        let sql = "INSERT INTO addresses (id, pubKeyHash) VALUES \(values)"
        let args = rows.flatMap { [$0.id, $0.pubKeyHash] }
        
        try dbQueue.write { db in
            try db.execute(sql: sql, arguments: StatementArguments(args))
        }
    }
    
    
    
    public func getAddresses(for publicKeyHash: String) throws -> [AddressRow] {
        return try dbQueue.read { db in
            try AddressRow
                .filter(AddressRow.Columns.pubKeyHash == publicKeyHash)
                .fetchAll(db)
        }
    }
    
    public func getAllAddresses() throws -> AnySequence<AddressRow> {
        return try dbQueue.read { db in
            let cursor = try AddressRow.fetchCursor(db)
            return AnySequence {
                AnyIterator {
                    try? cursor.next()
                }
            }
        }
    }
    
    
    public func getAddressCount() throws -> Int {
        return try dbQueue.read { db in
            try AddressRow.fetchCount(db)
        }
    }
    
    
}
