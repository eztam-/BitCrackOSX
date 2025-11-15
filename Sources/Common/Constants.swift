
import Metal

struct Constants{
    
    public static let APP_COMMAND_NAME = "keysearch"
    
    // Shouldn't make a hige difference in performance, but having the batch size as a multiple of maxThreadsPerThreadgroup will utilize each thread group fully.
    // (otherwise the last one might be just partially used).
    // This might also be a nice way, to chose larger batch sized for faster GPUs (TBC)
    public static let BATCH_SIZE = MTLCreateSystemDefaultDevice()!.maxThreadsPerThreadgroup.width * 512
 
    // TODO: See if 'mathMode.fast' brings any performance boost. Unfortunately this only works when compiling metal files at runtime
    // public static func metalOptions()-> MTLCompileOptions {
    //    let options = MTLCompileOptions()
    //    options.mathMode = .fast
    //    return options
    // }
}

