import Foundation
import BigNumber
import UserNotifications
import Metal
import Collections
import Darwin


class UI {
    
    private let BF_FPR_WARNING_THRESHOLD = 0.00002
    private static let STATS_LINES = 11
    private static let MIN_TERMIAL_WIDTH = 90
    
    // Per batch stats
    var totalStartTime: UInt64 = 0
    var totalEndTime: UInt64 = 0
    var endKey: BInt?
    var batchCount: Int = 0
    var lastPrintBatchCount = 0
    private let throughputEma = ExponentialMovingAverage(alpha: 0.1)
    public let bfFalsePositiveRateEma = ExponentialMovingAverage(alpha: 0.2)

    let timer = DispatchSource.makeTimerSource()
    var isFirstRun = true
    private let lock = NSLock()
    private var appStartTime = DispatchTime.now()
    let batchSize: Int
    let runConfig: RunConfig
    
    var throughputHistory = Deque<Double>() //Deque<Double>(repeating: 0.0, count: 32)
    var bloomFprHistory = Deque<Double>()
    var batchRateHistory = Deque<Double>()

  
    
    
    public init(batchSize: Int, runConfig: RunConfig){
        self.batchSize = batchSize
        self.endKey = runConfig.endKey != nil ? runConfig.endKey! + 150000000 * 10 : nil // TODO: This is a very dirty hack to avoid skipping the last few key checks, because there is always a delay until the keys are actually printed
        self.runConfig = runConfig
        UI.checkTerminalWidth()
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
        appStartTime = DispatchTime.now() // Start from here to only measure time when the actual key search starts (excluding init points)
    }
    
    
    public func printFooterPadding(numLines: Int = STATS_LINES) {
        print(String(repeating: "\n", count: numLines))
    }

    
    public func updateStats(totalStartTime: UInt64, totalEndTime: UInt64, batchCount: Int){
        self.totalStartTime = totalStartTime
        self.totalEndTime = totalEndTime
        self.batchCount = batchCount
    }
    

    public func printMessage(_ msg: String) {
        lock.lock()
        defer { lock.unlock() }
        
        // Move to top of footer block
        fputs("\u{1B}[\(UI.STATS_LINES)A", stdout)
        
        // Clear footer lines WITHOUT emitting newlines
        for _ in 0..<UI.STATS_LINES {
            fputs("\u{1B}[2K", stdout)    // clear entire line
            fputs("\u{1B}[1B", stdout)    // move cursor down one line
        }
        
        // Back to where the message should start
        fputs("\u{1B}[\(UI.STATS_LINES)A", stdout)
        
        print(msg)
        printFooterPadding()
        printStatsUnlocked()
    }
    
    public func printStats() {
        lock.lock()
        defer { lock.unlock() }
        printStatsUnlocked()
    }
    
    func printAt(column: Int, _ text: String) -> String {
        let esc = "\u{001B}"
        return "\(esc)[s\(esc)[\(column + 1)G\(text)\(esc)[u"
    }


    
    private func printStatsUnlocked(){
        // Skip the first few batch submissions, since they are not representative
        if batchCount <= Properties.RING_BUFFER_SIZE {
            return
        }
        
        // Calculate throughput
        let durationNs = totalEndTime - totalStartTime
        guard durationNs > 0 else { return }
        let mHashesPerSec = Double(batchSize) * 1_000.0 / Double(durationNs)
        guard mHashesPerSec.isFinite else { return }
        let smooth = throughputEma.add(mHashesPerSec) // TODO: This is OK but not perfect since it calculates the EMA from the last value of each second. More accurate would be to take every value.
        let statusStr = String(format: "%.1f MKey/s ", smooth)
        
        // Batch rate
        let batchesPerS = batchCount - lastPrintBatchCount
        var batchRateWarning = ""
        if batchesPerS > Properties.RING_BUFFER_SIZE {
            batchRateWarning = " ⚠️  Batch rate is too high and impacts performance! Adjust your settings."
        }
        let batchesPerSstr = "\(batchCount)  (\(batchesPerS)/s)"


        // Calculate bloom filter FPR
        let fprEma = bfFalsePositiveRateEma.getValue()!
        let falsePositiveRate = 100.0 / Double(batchSize * batchesPerS) * Double(fprEma)
        var bloomFilterString = String(format: "%.6f%% FPR (%d)", falsePositiveRate, Int(fprEma))
        var bloomFilterWarning = ""
        if falsePositiveRate > BF_FPR_WARNING_THRESHOLD {
            bloomFilterWarning.append(" ⚠️  FPR is too high and impacts performance! Adjust your settings.")
        }

        let (currKeyStr, currKey) = runConfig.calcCurrentKey(batchIndex: batchCount, offset: 0)
        let currKeyStrNice = underlineFirstDifferentCharacter(base: runConfig.startKeyStr, modified: currKeyStr)

        // Charts
        let chart1 = chart(values: &batchRateHistory, addValue: Double(batchesPerS))
        let chart2 = chart(values: &bloomFprHistory, addValue: falsePositiveRate)
        let chart3 = chart(values: &throughputHistory, addValue: Double(smooth))
        
        let endLine = printAt(column: 85,"│")
        
      

        print("\u{1B}[\(UI.STATS_LINES)A", terminator: "")
        print("""
        \(clearLine())📊 Live Stats ╭──────────────────────────────────────────────────────────────────────╮
        \(clearLine())╭─────────────╯    \(endLine)
        \(clearLine())│   Start key   :  \(runConfig.startKeyStr) \(endLine)
        \(clearLine())│   Current Key :  \(currKeyStrNice) \(endLine)
        \(clearLine())│   Elapsed Time:  \(elapsedTimeString()) \(endLine)
        \(clearLine())│   Batch Count :  \(arrow(batchesPerSstr, to: 23))\(chart1) \(endLine) \(batchRateWarning)
        \(clearLine())│   Bloom Filter:  \(arrow(bloomFilterString,to: 23))\(chart2) \(endLine) \(bloomFilterWarning)
        \(clearLine())│   Throughput  :  \(arrow(statusStr, to: 23))\(chart3) \(endLine)
        \(clearLine())│                                         ┌╴╴╴╴╴╴╴╴╴┬╴╴╴╴╴╴╴╴╴┬╴╴╴╴╴╴╴╴╴┬╴╴╴╴╴╴╴╴╴┐  │
        \(clearLine())│                                         0        10s       20s       30s       40s │
        \(clearLine())╰────────────────────────────────────────────────────────────────────────────────────╯
        """)
        fflush(stdout)
        
        // TODO: This is skipping the last few key checks, because there is always a delay when the keys are actually printed
        if endKey != nil && currKey > endKey!{
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
    
    func padOrTrim(_ string: String, to length: Int) -> String {
        if string.count == length {
            return string
        }

        if string.count > length {
            return String(string.prefix(length))
        }

        // string.count < length
        return string + String(repeating: " ", count: length - string.count)
    }
    
    func arrow(_ string: String, to length: Int) -> String {
        let currentLength = string.count

        if currentLength == length {
            return string
        }

        if currentLength > length {
            return String(string.prefix(length))
        }

        // Padding needed
        let paddingLength = length - currentLength

        // If there's only room for one padding character, just use space
        if paddingLength == 1 {
            return string + " "
        }
        else if paddingLength == 2 {
            return string + "  "
        }
        else if paddingLength == 3 {
            return string + " ▹ "
        }

        // Build: ├ ╌╌… ╌ ▹
        let middleCount = paddingLength - 3
        let padding = " " + String(repeating: "╌", count: middleCount) + "▹ "

        return string + padding
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
    
    
   
    func chart(values: inout Deque<Double>, addValue: Double) -> String {
        if !addValue.isInfinite {
            values.prepend(addValue)
        }
        if values.count > 41 {
            values.removeLast()
        }
        return barChart(values)
    }


        //let blocks: [Character] = ["⣀", "⣄", "⣆", "⣇", "⣧", "⣷", "⣿"]
       // let blocks: [Character] = ["▁","▂","▃","▄","▅","▆","▇","█"]
       // let blocks: [Character] = ["⣀","⣀","⣤","⣤","⣶","⣶","⣿","⣿"]

    func barChart<C: Collection>(_ values: C) -> String
    where C.Element == Double {
        guard !values.isEmpty else { return "" }

        let blocks: [Character] = ["▁","▂","▃","▄","▅","▆","▇","█"]
        let steps = blocks.count - 1

        let minVal = values.min()!
        let maxVal = values.max()!
        let range = maxVal - minVal

        let reset = "\u{001B}[0m"

        // Subtle grayscale range
        let grayMin = 238   // dark gray
        let grayMax = 252   // light gray

        // Handle flat signal
        if range == 0 {
            let color = "\u{001B}[38;5;\(grayMin + grayMax) / 2)m"
            let mid = blocks[steps / 2]
            return values.map { _ in "\(color)\(mid)\(reset)" }.joined()
        }

        var output = ""

        for v in values {
            let normalized = (v - minVal) / range
            let clamped = max(0.0, min(1.0, normalized))
            let index = Int(round(clamped * Double(steps)))

            // Grayscale intensity only
            let gray = Int(Double(grayMin) + clamped * Double(grayMax - grayMin))
            let color = "\u{001B}[38;5;\(gray)m"

            output += "\(color)\(blocks[index])\(reset)"
        }
        return output
    }
    

    private static func checkTerminalWidth() {
        var w = winsize()
        let result = ioctl(STDOUT_FILENO, TIOCGWINSZ, &w)
        guard result == 0 else {
            fputs("Error: Not running in a terminal.\n", stderr)
            exit(EXIT_FAILURE)
        }
        let width = Int(w.ws_col)
        if width < MIN_TERMIAL_WIDTH {
            fputs("Terminal width (\(width)) is too small. Minimum is \(MIN_TERMIAL_WIDTH). Resize your terminal window.\n", stderr)
            exit(EXIT_FAILURE)
        }
    }

}


