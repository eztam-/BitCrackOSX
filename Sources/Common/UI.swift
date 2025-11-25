import Foundation

class UI {
    
    // Per batch detailled stats
    var keyGen: Double = 0
    var secp256k1: Double = 0
    var hashing: Double = 0
    var bloomFilter: Double = 0
    
    // Per batch stats
    var totalStartTime: UInt64 = 0
    var totalEndTime: UInt64 = 0
    var bfFalePositiveCnt: Int = 0
    var startHexKey: String = ""
    var nextBasePrivKey: [UInt8] = []
  
    let timer = DispatchSource.makeTimerSource()
    var isFirstRun = true
    private let lock = NSLock()
    
    private static let STATS_LINES = 6
    
    private let batchSize: Int
    
    public init(batchSize: Int){
        self.batchSize = batchSize
    }
    
    public func startLiveStats(){
        timer.schedule(deadline: .now(), repeating: 1.0)
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
    
    public func updateStats(totalStartTime: UInt64, totalEndTime: UInt64, bfFalsePositiveCnt: Int, nextBasePrivKey: [UInt8]){
        self.totalStartTime = totalStartTime
        self.totalEndTime = totalEndTime
        self.bfFalePositiveCnt = bfFalsePositiveCnt
        self.nextBasePrivKey = nextBasePrivKey
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
        
        
        
        let durationNs = totalEndTime - totalStartTime
        let durationSeconds = Double(durationNs) / 1_000_000_000.0

        let itemsPerSecond = Double(batchSize) / durationSeconds
        let mHashesPerSec = itemsPerSecond / 1_000_000.0


        let falsePositiveRate = 100.0 / Double(batchSize) * Double(self.bfFalePositiveCnt)
        var statusStr = String(format: "  %.1f MKey/s ", mHashesPerSec)
     
        
        if self.bfFalePositiveCnt > 10 {
            statusStr.append(" ⚠️  Bloom filter FPR is too high and impacts performance! Adjust your settings.")
        }
        
        
        print("\u{1B}[\(UI.STATS_LINES)A", terminator: "")
        // TODO: hide the details about the individual steps and make them available by compiler flag or preporeccor? if pperformance is dramatic. Otherwise make them available by comln param
        print("")
        print("📊 Live Stats")
        print("\(clearLine())    Start key   :   \(startHexKey.uppercased())")
        let currKey = nextBasePrivKey.isEmpty ? "" : Data(nextBasePrivKey.reversed()).hexString
        print("\(clearLine())    Current key :   \(currKey.uppercased())")
        //let nextBasePrivKeyHex = Data(privKey.reversed()).hexString
        print(String(format: "\(clearLine())    Bloom Filter: %8.3f ms | FPR %.4f%% (%d)", self.bloomFilter, falsePositiveRate, self.bfFalePositiveCnt))
        print("\(clearLine())    Throughput  : \(statusStr)")
        fflush(stdout)
        
    }
    
    func clearLine() -> String {
        // Clear the current line and move cursor to beginning
        return "\u{001B}[2K\u{001B}[0G"
    }
}


