import Foundation
import BigNumber
import UserNotifications
import Metal

class UI {
    
    private let BF_FPR_WARNING_THRESHOLD = 0.00002
    private static let STATS_LINES = 7
    
    // Per batch stats
    var totalStartTime: UInt64 = 0
    var totalEndTime: UInt64 = 0
    var startHexKey: String = ""
    var startKey: BInt = BInt.zero
    var endKey: BInt?
    var batchCount: Int = 0
    var lastPrintBatchCount = 0
    private let throughputEma = ExponentialMovingAverage(alpha: 0.1)
    public let bfFalsePositiveRateEma = ExponentialMovingAverage(alpha: 0.2)

    let timer = DispatchSource.makeTimerSource()
    var isFirstRun = true
    private let lock = NSLock()
    private let appStartTime = DispatchTime.now()
    let batchSize: Int
    
    
    public init(batchSize: Int, startKeyHex: String, endKey: BInt?){
        self.batchSize = batchSize
        self.startHexKey = startKeyHex
        self.startKey = BInt(startKeyHex, radix: 16)!
        self.endKey = endKey != nil ? endKey! + 150000000 * 10 : nil // TODO: This is a very dirty hack to avoid skipping the last few key checks, because there is always a delay when the keys are actually printed
    }
    
    
    func elapsedTimeString() -> String {
        let elapsed = DispatchTime.now().uptimeNanoseconds - appStartTime.uptimeNanoseconds
        
        let totalSeconds = elapsed / 1_000_000_000
        
        let days = totalSeconds / 86_400
        let hours = (totalSeconds % 86_400) / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        
        return String(format: "%d:%02d:%02d:%02d", days, hours, minutes, seconds)
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
        print(String(repeating: "\n", count: numLines))
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
        
        // Skip the first few batch submissions, since they are not representative
        if batchCount <= Properties.RING_BUFFER_SIZE {
            return
        }
        
        // Calculate throughput
        let durationNs = totalEndTime - totalStartTime
        guard durationNs > 0 else { return }
        let mHashesPerSec = Double(batchSize) * 1_000.0 / Double(durationNs)
        guard mHashesPerSec.isFinite else { return }
        let smooth = throughputEma.add(mHashesPerSec)
        let statusStr = String(format: "%.1f MKey/s ", smooth)
        
        let batchesPerS = batchCount - lastPrintBatchCount

        // Calculate bloom filter FPR
        let fprEma = bfFalsePositiveRateEma.getValue()!
        let falsePositiveRate = 100.0 / Double(batchSize * batchesPerS) * Double(fprEma)
        var bloomFilterString = String(format: "%.6f%% FPR (%d)", falsePositiveRate, Int(fprEma))
        if falsePositiveRate > BF_FPR_WARNING_THRESHOLD {
            bloomFilterString.append(" ⚠️  FPR is too high and impacts performance! Adjust your settings.")
        }

        // Calculate current key
        let currentKey = startKey + batchSize * batchCount
        var currKey: String = ""
        if currentKey > 0 {
            currKey = currentKey.asString(radix: 16)
            currKey = Helpers.addTrailingZeros(key: currKey)
            currKey = underlineFirstDifferentCharacter(base: startHexKey.uppercased(), modified: currKey.uppercased())
        }
        
        print("\u{1B}[\(UI.STATS_LINES)A", terminator: "")
        
        print("""
        📊 Live Stats
        \(clearLine())    Start key   :  \(startHexKey.uppercased())
        \(clearLine())    Current Key :  \(currKey)
        \(clearLine())    Elapsed Time:  \(elapsedTimeString())
        \(clearLine())    Batch Count :  \(batchCount) (\(batchesPerS)/s)
        \(clearLine())    Bloom Filter:  \(bloomFilterString)
        \(clearLine())    Throughput  :  \(statusStr)
        """)
        fflush(stdout)
        
        // TODO: This is skipping the last few key checks, because there is always a delay when the keys are actually printed
        if endKey != nil && currentKey > endKey!{
            print("\n\nEnd key reached. Exiting.")
            exit(0);
        }
        
        lastPrintBatchCount = batchCount
        
    }
    
    /// Clear the current line and move cursor to beginning
    func clearLine() -> String {
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
        // ANSI formatting
        let highlight = "\u{001B}[1m\u{001B}[4m"
        let reset     = "\u{001B}[0m"

        var modIndex = modified.startIndex

        for (baseChar, modChar) in zip(base, modified) {
            if baseChar != modChar {
                let nextIndex = modified.index(after: modIndex)

                let prefix = modified[..<modIndex]
                let highlighted = "\(highlight)\(modChar)\(reset)"
                let suffix = modified[nextIndex...]

                return prefix + highlighted + suffix
            }
            modIndex = modified.index(after: modIndex)
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


