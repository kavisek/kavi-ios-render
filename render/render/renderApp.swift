//
//  renderApp.swift
//  render
//
//  Created by Kavi Sekhon on 2026-09-04.
//

import SwiftUI

@main
struct RenderMain {
    static func main() {
        #if os(macOS)
        // Only the Mac app doubles as the `render` command-line tool.
        let arguments = Array(CommandLine.arguments.dropFirst())
        if let exitCode = CLI.run(arguments: arguments) {
            exit(exitCode)
        }
        #endif
        renderApp.main()
    }
}

struct renderApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
