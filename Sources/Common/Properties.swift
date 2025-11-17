
import Metal

struct Properties{
    
    // How many keys each thread calculates per batch.
    // Tune: 256, 512, 1024, ... depending on registers/occupancy.
    // Each thread will process KEYS_PER_THREAD keys at a time
    // The key generator will only generate the start key used by each thread and therefore increments by KEYS_PER_THREAD
    public static let KEYS_PER_THREAD: Int = 128
    
    public static let APP_COMMAND_NAME = "keysearch"
    nonisolated(unsafe) public static var verbose: Bool = false
    

 
    // TODO: See if 'mathMode.fast' brings any performance boost. Unfortunately this only works when compiling metal files at runtime
    // public static func metalOptions()-> MTLCompileOptions {
    //    let options = MTLCompileOptions()
    //    options.mathMode = .fast
    //    return options
    // }
}

