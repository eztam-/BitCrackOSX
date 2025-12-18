import Foundation
import BigNumber
import UserNotifications
import Metal

class UI {
    
    // Per batch detailled stats
    var keyGen: Double = 0
    var secp256k1: Double = 0
    var hashing: Double = 0
    var bloomFilter: Double = 0
    
    // Per batch stats
    var totalStartTime: UInt64 = 0
    var totalEndTime: UInt64 = 0
    var bfFalsePositiveCnt: [Int] = []
    var startHexKey: String = ""
    var startKey: BInt = BInt.zero
    var batchCount: Int = 0
    
    var lastPrintBatchCount = 0
    
    let timer = DispatchSource.makeTimerSource()
    var isFirstRun = true
    private let lock = NSLock()
    
    private static let STATS_LINES = 8
    
    private let batchSize: Int
    
    private let appStartTime = DispatchTime.now()
    
    public init(batchSize: Int, startKeyHex: String){
        self.batchSize = batchSize
        self.startHexKey = startKeyHex
        self.startKey = BInt(startKeyHex, radix: 16)!
    }
    
    func elapsedTimeString() -> String {
        let elapsed = DispatchTime.now().uptimeNanoseconds - appStartTime.uptimeNanoseconds
        
        let totalSeconds = elapsed / 1_000_000_000
        
        let days = totalSeconds / 86_400
        let hours = (totalSeconds % 86_400) / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        
        return String(format: "%02d:%02d:%02d:%02d", days, hours, minutes, seconds)
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
        for _ in 0..<UI.STATS_LINES {
            // print("\u{1B}[K") // Clear each line
            print("")
        }
    }
    
    public func updateStats(totalStartTime: UInt64, totalEndTime: UInt64, batchCount: Int){
        self.totalStartTime = totalStartTime
        self.totalEndTime = totalEndTime
        self.batchCount = batchCount
    }
    
    
    @inline(__always)
    private func raw(_ s: String) {
        fputs(s, stdout)
    }
    
    public func printMessage(_ msg: String) {
        //lock.lock()
        //defer { lock.unlock() }
        
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
        printStats()
        fflush(stdout)
        
    }
    
    
    func printStats(){
        lock.lock()
        defer { lock.unlock() }
        
        
        let durationNs = totalEndTime - totalStartTime
        let durationSeconds = Double(durationNs) / 1_000_000_000.0
        
        
        let itemsPerSecond = Double(batchSize) / durationSeconds
        let mHashesPerSec = itemsPerSecond / 1_000_000.0
        let statusStr = String(format: "  %.1f MKey/s ", mHashesPerSec)
        
        
        let batchesPerS = batchCount - lastPrintBatchCount
        let totalFpLastSecond = bfFalsePositiveCnt.reduce(0, +)
        let falsePositiveRate = 100.0 / Double(batchSize * batchesPerS) * Double(totalFpLastSecond)
        var bloomFilterString = String(format: "%.6f%% FPR (%d)", falsePositiveRate, totalFpLastSecond)
        if falsePositiveRate > 0.00001 {
            bloomFilterString.append(" ⚠️  Bloom filter FPR is too high and impacts performance! Adjust your settings.")
        }
        
        print("\u{1B}[\(UI.STATS_LINES)A", terminator: "")
        print("")
        print("📊 Live Stats")
        print("\(clearLine())    Start key   :  \(startHexKey.uppercased())")
        
        let currentKey = startKey + batchSize * batchCount
        var currKey: String = ""
        if currentKey > 0 {
            currKey = currentKey.asString(radix: 16)
            currKey = Helpers.addTrailingZeros(key: currKey)
            currKey = underlineFirstDifferentCharacter(base: startHexKey.uppercased(), modified: currKey.uppercased())
        }
        
        print("\(clearLine())    Current Key :  \(currKey)")
        print("\(clearLine())    Elapsed Time:  \(elapsedTimeString())")
        print("\(clearLine())    Batch Count :  \(batchCount) (\(batchesPerS)/s)")
        print("\(clearLine())    Bloom Filter:  \(bloomFilterString)")
        print("\(clearLine())    Throughput  :\(statusStr)")
        fflush(stdout)
        
        bfFalsePositiveCnt.removeAll()
        lastPrintBatchCount = batchCount
        
    }
    
    func clearLine() -> String {
        // Clear the current line and move cursor to beginning
        return "\u{001B}[2K\u{001B}[0G"
    }
    
    public static func printGPUInfo() throws {
        let device = Helpers.getSharedDevice()
        let name = device.name
        let maxThreadsPerThreadgroup = device.maxThreadsPerThreadgroup
        let isLowPower = device.isLowPower
        let hasUnifiedMemory = device.hasUnifiedMemory
        let memoryMB = device.recommendedMaxWorkingSetSize / (1024 * 1024)
        
        print("""
        
        ⚡ GPU Information
            Name        : \(name)
            Low Power   : \(isLowPower ? "Yes" : "No")
            Unified Mem : \(hasUnifiedMemory ? "Yes" : "No")
            Max Threads : \(maxThreadsPerThreadgroup.width) per TG
            Memory      : \(memoryMB) MB
        
        """)
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
    
    
    func sendNotification(message: String, title: String) {
        let script = "display notification \"\(message)\" with title \"\(title)\" sound name \"Ping\""
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        task.launch()
    }
    
}


