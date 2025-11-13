
struct Constants{
    
    public static let APP_COMMAND_NAME = "keysearch"
    public static let BATCH_SIZE = 4096*8*8*4 // ~1M
 
    // TODO: See if 'mathMode.fast' brings any performance boost. Unfortunately this only works when compiling metal files at runtime
    // public static func metalOptions()-> MTLCompileOptions {
    //    let options = MTLCompileOptions()
    //    options.mathMode = .fast
    //    return options
    // }
}

