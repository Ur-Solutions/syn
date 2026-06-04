import Foundation

enum PacketHistoryRecovery {
    static func recover(_ packets: [PacketSummary], persist: Bool = true) -> [PacketSummary] {
        var changed = false
        let recovered = packets.map { packet -> PacketSummary in
            guard packet.status == .processing || shouldReclassifyFailedPacket(packet) else {
                return packet
            }

            changed = true
            return recover(packet)
        }

        if changed, persist {
            PacketHistoryStore.save(recovered)
        }

        return recovered
    }

    private static func recover(_ packet: PacketSummary) -> PacketSummary {
        var recovered = packet
        let context = PacketContext.existing(packet: packet)

        if let manifest = loadManifest(context: context) {
            recovered.duration = manifest.duration
            recovered.status = PacketStatus(rawValue: manifest.processing.status) ?? .partial
            return recovered
        }

        let rawExists = FileManager.default.fileExists(atPath: context.rawRecordingURL.path)
        let rawSegmentsExist = hasRawSegments(context: context)
        let sessionExists = FileManager.default.fileExists(atPath: context.rawCaptureSessionURL.path)

        if rawExists || rawSegmentsExist {
            recovered.status = .partial
            writeInterruptedPacketNote(
                context: context,
                status: .partial,
                message: sessionExists
                    ? "Syn was interrupted after raw capture metadata was saved but before packet processing completed. Retry processing from the History view."
                    : "Syn was interrupted after raw video segments were saved but before retry metadata was saved. Retry processing from the History view; Syn will use fallback capture metadata if needed."
            )
            return recovered
        }

        recovered.status = .failed
        writeInterruptedPacketNote(
            context: context,
            status: .failed,
            message: rawExists
                ? "Syn was interrupted before retry metadata was saved. Raw recording exists, but retry may need manual recovery."
                : "Syn was interrupted before a raw recording was saved. Start a new recording."
        )
        return recovered
    }

    private static func loadManifest(context: PacketContext) -> PacketManifest? {
        guard let data = try? Data(contentsOf: context.manifestURL) else {
            return nil
        }

        return try? JSONDecoder.synDecoder.decode(PacketManifest.self, from: data)
    }

    private static func shouldReclassifyFailedPacket(_ packet: PacketSummary) -> Bool {
        guard packet.status == .failed else {
            return false
        }

        let context = PacketContext.existing(packet: packet)
        guard loadManifest(context: context) == nil else {
            return false
        }

        return FileManager.default.fileExists(atPath: context.rawRecordingURL.path)
            || hasRawSegments(context: context)
    }

    private static func hasRawSegments(context: PacketContext) -> Bool {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: context.rawSegmentsURL,
            includingPropertiesForKeys: nil
        ) else {
            return false
        }

        return contents.contains { $0.pathExtension.lowercased() == "mp4" }
    }

    private static func writeInterruptedPacketNote(
        context: PacketContext,
        status: PacketStatus,
        message: String
    ) {
        try? context.ensureDerivedDirectories()

        if shouldWriteInterruptedNote(at: context.summaryURL) {
            let summary = """
            # Interrupted Recording

            Status: \(status.title)

            \(message)
            """
            try? summary.write(to: context.summaryURL, atomically: true, encoding: .utf8)
        }

        if shouldWriteInterruptedNote(at: context.agentPromptURL) {
            let prompt = """
            # Syn Feedback Packet

            Packet folder:
            `\(context.folderURL.path)`

            This packet was interrupted before processing completed.

            \(message)
            """
            try? prompt.write(to: context.agentPromptURL, atomically: true, encoding: .utf8)
        }
    }

    private static func shouldWriteInterruptedNote(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return true
        }

        guard let existing = try? String(contentsOf: url, encoding: .utf8) else {
            return false
        }

        return existing.contains("Interrupted Recording")
            || existing.contains("This packet was interrupted before processing completed.")
    }
}
