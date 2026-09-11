import Foundation

enum CLI {
    /// Handles CLI-style invocation. Returns an exit code if a command was
    /// recognized, or nil to fall through to launching the GUI.
    static func run(arguments: [String]) -> Int32? {
        guard let command = arguments.first else { return nil }

        switch command {
        case "start", "--start", "-s":
            return nil
        case "add", "--add", "-a":
            runAdd()
            return 0
        case "version", "--version", "-v":
            runVersion()
            return 0
        case "help", "--help", "-h":
            runHelp()
            return 0
        default:
            FileHandle.standardError.write(Data("render: unknown command '\(command)'\n".utf8))
            runHelp()
            return 1
        }
    }

    private static func runAdd() {
        print("add: not yet implemented")
    }

    private static func runVersion() {
        print("render \(Version.current)")
    }

    private static func runHelp() {
        print("""
        Usage: render [command]

        Commands:
          start            Start the app                (--start, -s)
          add              Add [not yet implemented]  (--add, -a)
          version          Print the version           (--version, -v)
          help             Show this help message       (--help, -h)

        Running render with no command also starts the app.
        """)
    }
}
