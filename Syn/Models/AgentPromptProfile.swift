import Foundation

enum AgentPromptProfile: String, CaseIterable, Codable, Identifiable, Sendable {
    case generalCoding
    case implementationPlan
    case qaBugReport

    var id: String { rawValue }

    var title: String {
        switch self {
        case .generalCoding:
            "General Coding Agent"
        case .implementationPlan:
            "Implementation Plan"
        case .qaBugReport:
            "QA Bug Report"
        }
    }

    var detail: String {
        switch self {
        case .generalCoding:
            "Balanced feedback handoff for coding agents."
        case .implementationPlan:
            "Turns feedback into scoped tasks and sequencing."
        case .qaBugReport:
            "Emphasizes reproduction, evidence, expected behavior, and severity."
        }
    }

    var fileName: String {
        switch self {
        case .generalCoding:
            "general-coding.md"
        case .implementationPlan:
            "implementation-plan.md"
        case .qaBugReport:
            "qa-bug-report.md"
        }
    }

    var openingInstruction: String {
        switch self {
        case .generalCoding:
            "Use it as concrete implementation guidance, but verify claims against the transcript, selected frames, and recording before changing code."
        case .implementationPlan:
            "Convert the evidence into a scoped implementation plan before changing code. Separate direct fixes from follow-up investigation."
        case .qaBugReport:
            "Use it as a bug report packet. Prioritize reproducible behavior, observed versus expected results, severity, timestamps, and visual evidence."
        }
    }

    var workflowSteps: [String] {
        switch self {
        case .generalCoding:
            [
                "Read the embedded summary below, then inspect `summary.md` for the full file.",
                "Use the selected frames in `frames/full/` and `frames/compressed/` to verify visual states.",
                "Use `transcript.md` and `recording.mp4` as authority when the summary is uncertain.",
                "Convert confirmed feedback into concrete code changes, tests, and follow-up questions.",
                "Keep uncertain visual or spoken claims separate from verified implementation facts."
            ]
        case .implementationPlan:
            [
                "Extract the concrete requests, defects, and constraints from the summary, transcript, and selected frames.",
                "Group related work into ordered implementation tasks with acceptance checks.",
                "Identify dependencies, risky areas, and missing evidence before editing code.",
                "Use `recording.mp4` and frame references when a task depends on visual behavior.",
                "End with a short open-questions list only for issues that cannot be resolved from the packet."
            ]
        case .qaBugReport:
            [
                "Identify each observed issue and cite the timestamp, transcript excerpt, and frame references that prove it.",
                "Write observed behavior, expected behavior, reproduction clues, affected area, and severity for each issue.",
                "Do not infer root cause unless the packet contains direct evidence.",
                "Use `recording.mp4` as the source of truth when summary and transcript disagree.",
                "Separate confirmed bugs from usability observations and unanswered questions."
            ]
        }
    }

    var additionalSections: String {
        switch self {
        case .generalCoding:
            """
            ## Agent Focus

            - Produce code changes only after verifying the feedback against packet evidence.
            - Prefer small, testable fixes with clear user-facing behavior.
            - Preserve uncertainty where the recording does not prove intent.
            """
        case .implementationPlan:
            """
            ## Planning Focus

            - Produce a prioritized task list with dependencies and acceptance criteria.
            - Call out quick fixes separately from design or architecture work.
            - Include verification steps for each task.
            """
        case .qaBugReport:
            """
            ## QA Focus

            - For each issue, capture observed behavior, expected behavior, reproduction evidence, severity, and confidence.
            - Prefer timestamps and frame filenames over paraphrase.
            - Keep product suggestions separate from confirmed defects.
            """
        }
    }
}
