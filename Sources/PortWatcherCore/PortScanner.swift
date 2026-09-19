import Foundation

public protocol CommandRunning {
    func run(executablePath: String, arguments: [String]) throws -> String
}

public struct ProcessCommandRunner: CommandRunning {
    public init() {}

    public func run(executablePath: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

public protocol PortScanning {
    func scan() throws -> [PortEntry]
}

public final class PortScanner: PortScanning {
    public enum ScanError: Error, Equatable {
        case commandNotFound(String)
    }

    private let lsofPath: String
    private let runner: CommandRunning

    public init(lsofPath: String = "/usr/sbin/lsof", runner: CommandRunning = ProcessCommandRunner()) {
        self.lsofPath = lsofPath
        self.runner = runner
    }

    public func scan() throws -> [PortEntry] {
        guard FileManager.default.isExecutableFile(atPath: lsofPath) else {
            throw ScanError.commandNotFound(lsofPath)
        }
        let output = try runner.run(executablePath: lsofPath, arguments: ["-i", "-P", "-n", "-F", "pcnPT"])
        return LsofOutputParser.parse(output)
    }
}
