
import Metal

struct Properties{
    

    public static let APP_COMMAND_NAME = "keysearch"
    
    public static let TOTAL_POINTS: Int = 1 << 20   // example
    
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

