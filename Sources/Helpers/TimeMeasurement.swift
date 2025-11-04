import Foundation

class TimeMeasurement {
    
    var keyGen: Double = 0
    var secp256k1: Double = 0
    var secp256k1_2: Double = 0
    var sha256: Double = 0
    var ripemd160: Double = 0
    var bloomFilter: Double = 0
    var keysPerSec: String = ""
    
    let timer = DispatchSource.makeTimerSource()
    
    nonisolated(unsafe) static let instance = TimeMeasurement()
    
    private init(){
        
        timer.schedule(deadline: .now()+DispatchTimeInterval.seconds(3), repeating: 1.0)
        timer.setEventHandler {
            print("Key gen     :\(String(format: "%8.3f", self.keyGen)) ms")
            print("secp256k1   :\(String(format: "%8.3f", self.secp256k1)) ms")
            print("secp256k1 2 :\(String(format: "%8.3f", self.secp256k1_2)) ms")
            print("SHA256      :\(String(format: "%8.3f", self.sha256)) ms")
            print("RIPEMD160   :\(String(format: "%8.3f", self.ripemd160)) ms")
            print("Bloomfilter :\(String(format: "%8.3f", self.bloomFilter)) ms")
            print(self.keysPerSec)
        }
        timer.resume()
    }
    
    
    
    
}
