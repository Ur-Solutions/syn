import Foundation

enum ZipService {
    static func createZip(for context: PacketContext) throws {
        try createZip(
            folderURL: context.folderURL,
            outputURL: context.zipURL,
            includingRaw: false
        )
    }

    static func createRawZip(for context: PacketContext) throws {
        try createZip(
            folderURL: context.folderURL,
            outputURL: context.rawZipURL,
            includingRaw: true
        )
    }

    static func createRawZip(for packet: PacketSummary) throws -> URL {
        let outputURL = packet.rawZipURL
        try createZip(
            folderURL: packet.folderURL,
            outputURL: outputURL,
            includingRaw: true
        )
        return outputURL
    }

    static func createCompactZip(for packet: PacketSummary) throws -> URL {
        let outputURL = packet.compactZipURL
        try createCompactZip(
            folderURL: packet.folderURL,
            outputURL: outputURL
        )
        return outputURL
    }

    static func createCompactZip(folderURL: URL, outputURL: URL) throws {
        try? FileManager.default.removeItem(at: outputURL)

        let root = folderURL.lastPathComponent
        let arguments = [
            "-qry",
            outputURL.path,
            root,
            "-x",
            "\(root)/raw/*",
            "\(root)/recording.mp4",
            "\(root)/recording-edited.mp4",
            "\(root)/frames/full/*"
        ]

        let result = try run(
            executable: "/usr/bin/zip",
            arguments: arguments,
            workingDirectory: folderURL.deletingLastPathComponent()
        )

        if result.status != 0 {
            throw NSError(
                domain: "Syn.Zip",
                code: Int(result.status),
                userInfo: [NSLocalizedDescriptionKey: result.output]
            )
        }
    }

    private static func createZip(
        folderURL: URL,
        outputURL: URL,
        includingRaw: Bool
    ) throws {
        try? FileManager.default.removeItem(at: outputURL)

        var arguments = [
            "-qry",
            outputURL.path,
            folderURL.lastPathComponent
        ]

        if !includingRaw {
            arguments.append(contentsOf: [
                "-x",
                "\(folderURL.lastPathComponent)/raw/*"
            ])
        }

        let result = try run(
            executable: "/usr/bin/zip",
            arguments: arguments,
            workingDirectory: folderURL.deletingLastPathComponent()
        )

        if result.status != 0 {
            throw NSError(
                domain: "Syn.Zip",
                code: Int(result.status),
                userInfo: [NSLocalizedDescriptionKey: result.output]
            )
        }
    }
}

extension JSONEncoder {
    static var synEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var synDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
