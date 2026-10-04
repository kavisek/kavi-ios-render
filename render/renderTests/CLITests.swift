//
//  CLITests.swift
//  renderTests
//

import Testing
@testable import render

@MainActor
struct CLITests {

    @Test func noArgumentsLaunchesGUI() {
        #expect(CLI.run(arguments: []) == nil)
    }

    @Test(arguments: ["start", "--start", "-s"])
    func startLaunchesGUI(_ argument: String) {
        #expect(CLI.run(arguments: [argument]) == nil)
    }

    @Test(arguments: [
        ["-NSTreatUnknownArgumentsAsOpen", "NO", "-ApplePersistenceIgnoreState", "YES"],
        ["-NSDocumentRevisionsDebugMode", "YES"],
        ["-psn_0_12345"],
    ])
    func systemLaunchFlagsLaunchGUI(_ arguments: [String]) {
        #expect(CLI.run(arguments: arguments) == nil)
    }

    @Test(arguments: ["version", "--version", "-v", "help", "--help", "-h", "add"])
    func commandsExitSuccessfully(_ argument: String) {
        #expect(CLI.run(arguments: [argument]) == 0)
    }

    @Test func unknownCommandFails() {
        #expect(CLI.run(arguments: ["bogus"]) == 1)
    }
}
