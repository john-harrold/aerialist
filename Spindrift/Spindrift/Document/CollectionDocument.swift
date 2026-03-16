import UniformTypeIdentifiers

extension UTType {
    static let spindriftCollection: UTType = UTType("com.spindrift.collection")
        ?? UTType(exportedAs: "com.spindrift.collection", conformingTo: .data)
}
