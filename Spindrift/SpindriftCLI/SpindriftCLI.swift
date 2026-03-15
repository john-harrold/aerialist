import ArgumentParser

@main
struct SpindriftCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "spindrift-cli",
        abstract: "Spindrift PDF tools command-line interface",
        version: "1.0.0",
        subcommands: [ConvertCommand.self, TextCommand.self, TableCommand.self]
    )
}
