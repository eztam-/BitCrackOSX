
import Metal

struct Properties{
    

    public static let APP_COMMAND_NAME = "keysearch"
    
    public static let KEYS_PER_THREAD = 512 * 2
    
    // The number of threads. Must be <= totalPoints
    public static let GRID_SIZE = 1024 * 64
    
    // This is effectively the batch size and reflects the number of public keys to be calculated per batch.
    // Must be a multiple of grid size
    public static let TOTAL_POINTS: Int = GRID_SIZE * KEYS_PER_THREAD // DON'T CHANGE THIS!
    

    
   

    
    nonisolated(unsafe) public static var verbose: Bool = false
    
    nonisolated(unsafe) public static var compressedKeySearch: Bool = true
    nonisolated(unsafe) public static var uncompressedKeySearch: Bool = false
 
    // TODO: See if 'mathMode.fast' brings any performance boost. Unfortunately this only works when compiling metal files at runtime
    // public static func metalOptions()-> MTLCompileOptions {
    //    let options = MTLCompileOptions()
    //    options.mathMode = .fast
    //    return options
    // }
    
    
    

}

