import Foundation

enum SidecarIO {

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func encode(_ sidecar: SidecarModel) throws -> Data {
        try encoder.encode(sidecar)
    }

    static func decode(from data: Data) throws -> SidecarModel {
        try decoder.decode(SidecarModel.self, from: data)
    }
}
