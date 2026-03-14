import ArgumentParser

@main
struct AerialistCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "aerialist-cli",
        abstract: "Aerialist PDF tools command-line interface",
        version: "1.0.0",
        subcommands: [ConvertCommand.self, TextCommand.self, TableCommand.self]
    )
}
