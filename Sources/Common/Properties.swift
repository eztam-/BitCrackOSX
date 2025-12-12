
import Metal

struct Properties{
    

    public static let APP_COMMAND_NAME = "keysearch"
    
    public static let KEYS_PER_THREAD = 1024
    
    // The number of threads. Must be <= totalPoints
    public static let GRID_SIZE = 1024 * 32
    
    // This is effectively the batch size and reflects the number of public keys to be calculated per batch.
    // Must be a multiple of grid size
    public static let TOTAL_POINTS: Int = GRID_SIZE * KEYS_PER_THREAD // DON'T CHANGE THIS!
    
    nonisolated(unsafe) public static var verbose: Bool = false
    nonisolated(unsafe) public static var compressedKeySearch: Bool = true
    nonisolated(unsafe) public static var uncompressedKeySearch: Bool = false

}

