import Testing
import Foundation
@testable import PortWatcherCore

struct ProcessOriginTests {
    @Test func readsWorkingDirectoryOfCurrentProcess() {
        let pid = Int32(ProcessInfo.processInfo.processIdentifier)
        let cwd = ProcessOriginReader.workingDirectory(pid: pid)
        #expect(cwd == FileManager.default.currentDirectoryPath)
    }

    @Test func readsArgumentsOfCurrentProcess() {
        let pid = Int32(ProcessInfo.processInfo.processIdentifier)
        let arguments = ProcessOriginReader.arguments(pid: pid)
        #expect(arguments?.isEmpty == false)
        #expect(arguments?.first == CommandLine.arguments.first)
    }

    @Test func returnsNilForNonexistentPID() {
        #expect(ProcessOriginReader.workingDirectory(pid: 999_999) == nil)
        #expect(ProcessOriginReader.arguments(pid: 999_999) == nil)
    }

    @Test func summarizeShortensPathsAndTruncates() {
        let vite = ["node", "/Users/x/proj/node_modules/.bin/vite", "--port", "5175"]
        #expect(ProcessOriginReader.summarize(arguments: vite) == "node vite --port 5175")
        let long = ["node"] + Array(repeating: "--flag-with-a-long-name", count: 10)
        let summary = ProcessOriginReader.summarize(arguments: long, maxLength: 30)!
        #expect(summary.count == 30)
        #expect(summary.hasSuffix("…"))
        #expect(ProcessOriginReader.summarize(arguments: []) == nil)
    }
}
