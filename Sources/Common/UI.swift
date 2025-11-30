import Foundation
import BigNumber


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
    var startKey: BInt = BInt.zero
    var batchCount: Int = 0
    
    let timer = DispatchSource.makeTimerSource()
    var isFirstRun = true
    private let lock = NSLock()
    
    private static let STATS_LINES = 7
    
    private let batchSize: Int
    
    public init(batchSize: Int, startKeyHex: String){
        self.batchSize = batchSize
        self.startHexKey = startKeyHex
        self.startKey = BInt(startKeyHex, radix: 16)!
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
    
    public func updateStats(totalStartTime: UInt64, totalEndTime: UInt64, bfFalsePositiveCnt: Int, batchCount: Int){
        self.totalStartTime = totalStartTime
        self.totalEndTime = totalEndTime
        self.bfFalePositiveCnt = bfFalsePositiveCnt
        self.batchCount = batchCount
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
     
        
        if falsePositiveRate > 0.0001 {
            statusStr.append(" ⚠️  Bloom filter FPR is too high and impacts performance! Adjust your settings.")
        }
        
        
        print("\u{1B}[\(UI.STATS_LINES)A", terminator: "")
        // TODO: hide the details about the individual steps and make them available by compiler flag or preporeccor? if pperformance is dramatic. Otherwise make them available by comln param
        print("")
        print("📊 Live Stats")
        print("\(clearLine())    Start key   :   \(startHexKey.uppercased())")
       
        
        
        let currentKey = startKey + batchSize * batchCount
        var currKey: String = ""
        if currentKey > 0 {
            currKey = currentKey.asString(radix: 16)
            // Add trailing zeros if missing
            if currKey.count < 64 {
                currKey = String(repeating: "0", count: 64 - currKey.count) + currKey
            }
            currKey = underlineFirstDifferentCharacter(base: startHexKey.uppercased(), modified: currKey.uppercased())
        }
       
        print("\(clearLine())    Current key :   \(currKey)")
        print("\(clearLine())    Batch Count :   \(batchCount)")
        //let nextBasePrivKeyHex = Data(privKey.reversed()).hexString
        print(String(format: "\(clearLine())    Bloom Filter:   %.4f%% FPR (%d)", falsePositiveRate, self.bfFalePositiveCnt))
        print("\(clearLine())    Throughput  : \(statusStr)")
        fflush(stdout)
        
    }
    
    func clearLine() -> String {
        // Clear the current line and move cursor to beginning
        return "\u{001B}[2K\u{001B}[0G"
    }
    
    
    func underlineFirstDifferentCharacter(base: String, modified: String) -> String {
        let baseChars = Array(base)
           let modChars  = Array(modified)
           let count = min(baseChars.count, modChars.count)
           
           // ANSI formatting
           let boldUnderline = "\u{001B}[1m\u{001B}[4m"  // bold + underline
           let reset         = "\u{001B}[0m"             // reset formatting
           
           for i in 0..<count {
               if baseChars[i] != modChars[i] {
                   let startIndex = modified.startIndex
                   let diffIndex = modified.index(startIndex, offsetBy: i)
                   let nextIndex = modified.index(after: diffIndex)
                   
                   let prefix = modified[startIndex..<diffIndex]
                   let highlighted = "\(boldUnderline)\(modified[diffIndex])\(reset)"
                   let suffix = modified[nextIndex..<modified.endIndex]
                   
                   return prefix + highlighted + suffix
               }
           }
           
           return modified
    }
}


