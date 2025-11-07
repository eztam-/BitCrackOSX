import Foundation
import SQLite

public class DB {
    
    let dbPath = "CryptKeySearch.sqlite3"
    let db: Connection
    
    public struct row {
        var address: String
        var publicKeyHash: String
    }
    
    public init(delete: Bool = false) {
        do {
            if delete {
                if FileManager.default.fileExists(atPath: dbPath) {
                    print("Database exists ✅")
                    try FileManager.default.removeItem(atPath: dbPath)
                    print("File deleted ✅")
                } else {
                    print("Database does NOT exist ❌")
                }
                
                self.db = try! Connection("CryptKeySearch.sqlite3")
                try db.run(
                """
                    CREATE TABLE "addresses" (
                        "address" TEXT PRIMARY KEY NOT NULL,
                        "public_key_hash" TEXT
                    );
                """)
                
                try db.run("CREATE INDEX Index_addresses_pubKeyHash ON addresses(public_key_hash);")
                
            } else {
                self.db = try! Connection("CryptKeySearch.sqlite3")
            }
                
            } catch {
                print("Error creating the database", error)
                _DarwinFoundation3.exit(1)
            }
       
    }
    



    public func insert(address: String, publicKeyHash: String) {
        do {
            try db.run("INSERT INTO addresses (address, public_key_hash) VALUES( '\(address)', '\(publicKeyHash)');")
        } catch {
            print ("Error inserting into DB 😱",error)
            _DarwinFoundation3.exit(1)
        }
    }
    
    public func get(publicKeyHash: String) -> [row] {
        do {
            var result: [row] = []
            for r in try db.run("SELECT * FROM addresses WHERE public_key_hash == '\(publicKeyHash)';"){
                result.append(row(address: r[0] as! String, publicKeyHash: r[1] as! String))
            }
            return result
        } catch {
            print ("Error inserting into DB 😱",error)
            _DarwinFoundation3.exit(1)
        }
    }
    
    
    
    
}
