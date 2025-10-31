import Foundation

class TimeMeasurement {
    
    var keyGen: UInt64 = 0
    var secp256k1: UInt64 = 0
    var sha256: UInt64 = 0
    var ripemd160: UInt64 = 0
    var bloomFilter: UInt64 = 0
    var keysPerSec: String = ""
    
    let timer = DispatchSource.makeTimerSource()
    
    init(){
        
        timer.schedule(deadline: .now()+DispatchTimeInterval.seconds(3), repeating: 1.0)
        timer.setEventHandler {
            print("------------------------------------")
            print("Key gen took     : \(self.keyGen)ns")
            print("secp256k1 took   : \(self.secp256k1)ns")
            print("SHA256 took      : \(self.sha256)ns")
            print("ripemd160 took   : \(self.ripemd160)ns")
            print("Bloomfilter took : \(self.bloomFilter)ns")
            print(self.keysPerSec)
            
        }
        timer.resume()
    }
    
    
    
}
