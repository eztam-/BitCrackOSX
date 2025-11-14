import Foundation

class UI {
    
    // Per batch detailled stats
    var keyGen: Double = 0
    var secp256k1: Double = 0
    var sha256: Double = 0
    var ripemd160: Double = 0
    var bloomFilter: Double = 0
    
    // Per batch stats
    var totalStartTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    var totalEndTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    var bfFalePositiveCnt: Int = 0
    
    let timer = DispatchSource.makeTimerSource()
    var isFirstRun = true
    private let lock = NSLock()
    nonisolated(unsafe) static let instance = UI()
    private static let STATS_LINES = 8
    
    private init(){
        
        timer.schedule(deadline: .now()+DispatchTimeInterval.seconds(3), repeating: 1.0)
        timer.setEventHandler {
            if self.isFirstRun {
                self.printFooterPadding()
                self.isFirstRun = false
            }
            self.printStats()
        }
        timer.resume()
    }
    
    public func printFooterPadding(numLines: Int = STATS_LINES) {
        for i in 0..<UI.STATS_LINES {
           // print("\u{1B}[K") // Clear each line
            print("")
        }
    }
    
    public func updateStats(totalStartTime: CFAbsoluteTime, totalEndTime: CFAbsoluteTime, bfFalsePositiveCnt: Int){
        self.totalStartTime = totalStartTime
        self.totalEndTime = totalEndTime
        self.bfFalePositiveCnt = bfFalsePositiveCnt
    }
    
    
    @inline(__always)
    private func raw(_ s: String) {
        fputs(s, stdout)
    }
    
    public func printMessage(_ msg: String) {
        lock.lock()
        defer { lock.unlock() }

        // Move to top of footer block
        raw("\u{1B}[\(UI.STATS_LINES)A")

        // Clear footer lines WITHOUT emitting newlines
        for _ in 0..<UI.STATS_LINES {
            raw("\u{1B}[2K")     // clear entire line
            raw("\u{1B}[1B")     // move cursor down one line
        }

        // Back to where the message should start
        raw("\u{1B}[\(UI.STATS_LINES)A")

        // Print the message (may be multi-line; will scroll naturally)
        print(msg)
        printFooterPadding()
        fflush(stdout)


    }


    func printStats(){
        lock.lock()
         defer { lock.unlock() }
        
        let totalTimeElapsed = self.totalEndTime - self.totalStartTime
        let mHashesPerSec = Double(Constants.BATCH_SIZE) / totalTimeElapsed / 1000000
        let falsePositiveRate = 100.0 / Double(Constants.BATCH_SIZE) * Double(self.bfFalePositiveCnt)
        var statusStr = String(format: "  %.3f MKey/s ", mHashesPerSec)
     
        
        if self.bfFalePositiveCnt > 10 {
            statusStr.append(" ⚠️ Bloom filter FPR is too high and impacts performance! Adjust your settings.")
        }
        
        
        print("\u{1B}[\(UI.STATS_LINES)A", terminator: "")
        // TODO: hide the details about the individual steps and make them available by compiler flag or preporeccor? if pperformance is dramatic. Otherwise make them available by comln param
        print("📊 Live Stats")
        print(String(format: "\(clearLine())    Key gen     : %8.3f ms", self.keyGen))
        print(String(format: "\(clearLine())    secp256k1   : %8.3f ms", self.secp256k1))
        print(String(format: "\(clearLine())    SHA256      : %8.3f ms", self.sha256))
        print(String(format: "\(clearLine())    RIPEMD160   : %8.3f ms", self.ripemd160))
        print(String(format: "\(clearLine())    Bloom Filter: %8.3f ms | FPR %.4f%% (%d)", self.bloomFilter, falsePositiveRate, self.bfFalePositiveCnt))
        print("\(clearLine())    ─────────────────────────────")
        print("\(clearLine())    Throughput  :  \(statusStr)")
        fflush(stdout)
        
    }
    
    func clearLine() -> String {
        // Clear the current line and move cursor to beginning
        return "\u{001B}[2K\u{001B}[0G"
    }
}


