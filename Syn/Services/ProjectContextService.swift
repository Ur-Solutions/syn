import Foundation

struct ProjectContextResult {
    var markdown: String
    var projectName: String
    var rootPath: String
    var detectedFiles: [String]
    var notes: [String]
}

enum ProjectContextService {
    private static let maximumReadmeCharacters = 2_000
    private static let maximumTopLevelEntries = 80
    private static let maximumGitStatusLines = 80
    private static let maximumGitLogLines = 8

    private static let excludedTopLevelNames: Set<String> = [
        ".DS_Store",
        ".git",
        ".hg",
        ".svn",
        ".env",
        ".env.local",
        ".env.production",
        ".venv",
        ".idea",
        ".vscode",
        "DerivedData",
        "build",
        "dist",
        "node_modules",
        "Pods",
        "Secrets",
        "tmp",
        "vendor"
    ]

    private static let sensitiveNameFragments = [
        ".env",
        "secret",
        "token",
        "credential",
        "private-key",
        "apikey",
        "api-key"
    ]

    private static let projectMarkerNames = [
        "Package.swift",
        "Syn.xcodeproj",
        "project.pbxproj",
        "package.json",
        "pnpm-lock.yaml",
        "yarn.lock",
        "bun.lockb",
        "Cargo.toml",
        "go.mod",
        "pyproject.toml",
        "requirements.txt",
        "Gemfile",
        "composer.json",
        "mix.exs",
        "README.md",
        "README.markdown",
        "README"
    ]

    static func createContext(for rootURL: URL) -> ProjectContextResult {
        let standardizedRoot = rootURL.standardizedFileURL
        let projectName = standardizedRoot.lastPathComponent
        var notes = [
            "Project context is a local metadata snapshot. Syn did not embed source files or secret-like files."
        ]

        let detectedFiles = detectProjectMarkers(in: standardizedRoot)
        let readmeExcerpt = readmeExcerpt(in: standardizedRoot)
        let topLevelEntries = listTopLevelEntries(in: standardizedRoot)
        let gitInfo = collectGitInfo(in: standardizedRoot)
        if gitInfo == nil {
            notes.append("No git metadata was available for this project folder.")
        }

        let markerMarkdown = detectedFiles.isEmpty
            ? "- No common project marker files detected at the project root."
            : detectedFiles.map { "- `\($0)`" }.joined(separator: "\n")
        let topLevelMarkdown = topLevelEntries.isEmpty
            ? "- No top-level entries were listed."
            : topLevelEntries.map { "- \($0)" }.joined(separator: "\n")
        let gitMarkdown = gitInfo?.markdown ?? "- Git metadata unavailable."
        let readmeMarkdown = readmeExcerpt ?? "_No README excerpt found._"
        let noteMarkdown = notes.map { "- \($0)" }.joined(separator: "\n")

        let markdown = """
        # Project Context

        Project: `\(projectName)`

        Root: `\(standardizedRoot.path)`

        ## Safety Notes

        \(noteMarkdown)

        ## Detected Project Files

        \(markerMarkdown)

        ## Git Snapshot

        \(gitMarkdown)

        ## Top-Level Structure

        \(topLevelMarkdown)

        ## README Excerpt

        \(readmeMarkdown)
        """

        return ProjectContextResult(
            markdown: markdown,
            projectName: projectName,
            rootPath: standardizedRoot.path,
            detectedFiles: detectedFiles,
            notes: notes
        )
    }

    static func writeContext(for rootURL: URL, to outputURL: URL) throws -> ProjectContextResult {
        let result = createContext(for: rootURL)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try result.markdown.write(to: outputURL, atomically: true, encoding: .utf8)
        return result
    }

    private static func detectProjectMarkers(in rootURL: URL) -> [String] {
        projectMarkerNames.filter { marker in
            FileManager.default.fileExists(atPath: rootURL.appendingPathComponent(marker).path)
        }
    }

    private static func readmeExcerpt(in rootURL: URL) -> String? {
        let names = ["README.md", "README.markdown", "README"]
        for name in names {
            let url = rootURL.appendingPathComponent(name)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                continue
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            if trimmed.count <= maximumReadmeCharacters {
                return trimmed
            }
            let end = trimmed.index(trimmed.startIndex, offsetBy: maximumReadmeCharacters)
            return "\(trimmed[..<end])\n\n[README excerpt truncated by Syn.]"
        }
        return nil
    }

    private static func listTopLevelEntries(in rootURL: URL) -> [String] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        )) ?? []

        return urls
            .filter { !shouldExcludeTopLevelEntry($0) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .prefix(maximumTopLevelEntries)
            .map { url in
                let isDirectory = ((try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false)
                return "`\(url.lastPathComponent)\(isDirectory ? "/" : "")`"
            }
    }

    private static func shouldExcludeTopLevelEntry(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        let lowercased = name.lowercased()
        if excludedTopLevelNames.contains(name) {
            return true
        }
        if sensitiveNameFragments.contains(where: { lowercased.contains($0) }) {
            return true
        }
        return false
    }

    private static func collectGitInfo(in rootURL: URL) -> GitInfo? {
        guard gitCommand(["rev-parse", "--is-inside-work-tree"], rootURL: rootURL)?.trimmingCharacters(in: .whitespacesAndNewlines) == "true" else {
            return nil
        }

        let branch = gitCommand(["branch", "--show-current"], rootURL: rootURL)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let commit = gitCommand(["rev-parse", "--short", "HEAD"], rootURL: rootURL)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let statusLines = limitedLines(
            gitCommand(["status", "--short"], rootURL: rootURL),
            limit: maximumGitStatusLines
        )
        let recentCommits = limitedLines(
            gitCommand(["log", "--oneline", "-\(maximumGitLogLines)"], rootURL: rootURL),
            limit: maximumGitLogLines
        )

        return GitInfo(
            branch: branch?.isEmpty == false ? branch : nil,
            commit: commit?.isEmpty == false ? commit : nil,
            statusLines: statusLines,
            recentCommits: recentCommits
        )
    }

    private static func gitCommand(_ arguments: [String], rootURL: URL) -> String? {
        guard let result = try? run(
            executable: "/usr/bin/git",
            arguments: arguments,
            workingDirectory: rootURL
        ), result.status == 0 else {
            return nil
        }
        return result.output
    }

    private static func limitedLines(_ value: String?, limit: Int) -> [String] {
        guard let value else {
            return []
        }
        return value
            .split(separator: "\n", omittingEmptySubsequences: true)
            .prefix(limit)
            .map(String.init)
    }
}

private struct GitInfo {
    var branch: String?
    var commit: String?
    var statusLines: [String]
    var recentCommits: [String]

    var markdown: String {
        var sections: [String] = []
        sections.append("- Branch: \(branch.map { "`\($0)`" } ?? "unknown")")
        sections.append("- Commit: \(commit.map { "`\($0)`" } ?? "unknown")")

        if statusLines.isEmpty {
            sections.append("- Working tree: clean or status unavailable.")
        } else {
            let status = statusLines.map { "  - `\($0)`" }.joined(separator: "\n")
            sections.append("- Working tree changes:\n\(status)")
        }

        if recentCommits.isEmpty {
            sections.append("- Recent commits: unavailable.")
        } else {
            let commits = recentCommits.map { "  - `\($0)`" }.joined(separator: "\n")
            sections.append("- Recent commits:\n\(commits)")
        }

        return sections.joined(separator: "\n")
    }
}
