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
        let arguments = Array(CommandLine.arguments.dropFirst())
        if let exitCode = CLI.run(arguments: arguments) {
            exit(exitCode)
        }
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
