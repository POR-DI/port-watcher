import Testing
@testable import PortWatcherCore

struct PortScannerTests {
    final class FakeCommandRunner: CommandRunning {
        var capturedPath: String?
        var capturedArguments: [String]?
        var outputToReturn: String = ""
        func run(executablePath: String, arguments: [String]) throws -> String {
            capturedPath = executablePath
            capturedArguments = arguments
            return outputToReturn
        }
    }

    @Test func scanParsesRunnerOutputThroughLsofOutputParser() throws {
        let fake = FakeCommandRunner()
        fake.outputToReturn = "p481\ncnode\nLpordiewtrakul\nf16\nPTCP\nn*:5174\nTST=LISTEN\n"
        let scanner = PortScanner(lsofPath: "/usr/sbin/lsof", runner: fake)
        let entries = try scanner.scan()
        #expect(entries.count == 1)
        #expect(entries[0].pid == 481)
    }

    @Test func scanPassesExpectedArgumentsToRunner() throws {
        let fake = FakeCommandRunner()
        let scanner = PortScanner(lsofPath: "/usr/sbin/lsof", runner: fake)
        _ = try scanner.scan()
        #expect(fake.capturedPath == "/usr/sbin/lsof")
        #expect(fake.capturedArguments == ["-i", "-P", "-n", "-F", "pcnPT"])
    }

    @Test func scanThrowsWhenLsofBinaryMissing() {
        let scanner = PortScanner(lsofPath: "/nonexistent/lsof", runner: FakeCommandRunner())
        #expect(throws: PortScanner.ScanError.commandNotFound("/nonexistent/lsof")) {
            try scanner.scan()
        }
    }

    @Test func processCommandRunnerDoesNotDeadlockWhenChildFloodsStderr() throws {
        // Writes 256KB to stderr (well past the ~64KB pipe buffer) before printing to stdout.
        let runner = ProcessCommandRunner()
        let output = try runner.run(
            executablePath: "/bin/sh",
            arguments: ["-c", "head -c 262144 /dev/zero 1>&2; echo ok"]
        )
        #expect(output == "ok\n")
    }
}
