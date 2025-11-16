
import Metal

struct Properties{
    
    public static let APP_COMMAND_NAME = "keysearch"
    nonisolated(unsafe) public static var verbose: Bool = false
    

 
    // TODO: See if 'mathMode.fast' brings any performance boost. Unfortunately this only works when compiling metal files at runtime
    // public static func metalOptions()-> MTLCompileOptions {
    //    let options = MTLCompileOptions()
    //    options.mathMode = .fast
    //    return options
    // }
}

