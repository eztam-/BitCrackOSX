import Metal

public class Properties{
   
    public static func metalOptions()-> MTLCompileOptions {
        let options = MTLCompileOptions()
        options.mathMode = .fast
        return options
    }
    
    
}


