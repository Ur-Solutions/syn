import AppKit
import Foundation
import Network

// MARK: - Web Element Bridge (PRD MVP 2 + 3: browser DOM / framework providers)
//
// Local WebSocket server on 127.0.0.1:47845. Pages running `@syn/web-elements`
// (see web/packages/web-elements) connect out to Syn; Syn never connects into the
// page. During element picking, when the hovered window belongs to a browser, the
// picker broadcasts a `lookup` to every connected page and the page whose viewport
// contains the point answers with a DOM/framework snapshot. The accessibility
// snapshot remains the fallback and is preserved in `rawProviders` after a merge.
//
// Protocol (JSON text frames; see docs/WEB_ELEMENT_SDK_PLAN.md):
//   SDK -> Syn  {type:"hello", sdkVersion, framework, adapter?, url, devicePixelRatio}
//   Syn -> SDK  {type:"helloAck", app:"Syn", version}
//   Syn -> SDK  {type:"lookup", id, screenX, screenY}   // global TOP-LEFT-origin points,
//                                                       // the space window.screenX lives in
//   SDK -> Syn  {type:"element", id, snapshot|null}     // snapshot bounds.screen is top-left
//                                                       // global points; Syn converts to Cocoa

/// `web` block of a flagged element: DOM-level identity from the page SDK.
struct WebElementBlock: Codable, Sendable {
    var tagName: String?
    var selector: String?
    /// Selector of the raw `elementFromPoint` leaf before interactive-ancestor promotion.
    var leafSelector: String?
    var testId: String?
    var text: String?
    var url: String?
    var route: String?
    var title: String?
    var attributes: [String: String]?
}

/// `framework` block of a flagged element: component identity from a dev-mode resolver.
struct FrameworkElementBlock: Codable, Sendable {
    var name: String?
    var componentName: String?
    var ownerStack: [String]?
    /// `file:line:column` when the dev build exposes it (React `_debugSource`/`_debugStack`,
    /// Svelte `__svelte_meta`).
    var source: String?
    var propsMode: String?
    var propsRedacted: Bool?
    var props: [String: JSONValue]?
}

/// Lower-priority provider data preserved when a higher-priority snapshot wins a merge.
struct RawProviderSnapshot: Codable, Sendable {
    var provider: String
    var role: String?
    var label: String?
    var value: String?
    var identifier: String?
}

/// Minimal JSON value for sanitized framework props (SDK sends safe primitives only).
enum JSONValue: Codable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    indirect case array([JSONValue])
    indirect case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

/// Snapshot payload as sent by the page SDK in an `element` message.
struct WebElementSnapshotPayload: Codable, Sendable {
    struct Identity: Codable, Sendable {
        var role: String?
        var label: String?
        var text: String?
        var testId: String?
    }

    struct Bounds: Codable, Sendable {
        /// Normalized: global top-left-origin screen points.
        var screen: CodableRect?
        /// Raw: viewport CSS pixels, for mapping verification.
        var viewport: CodableRect?
        var devicePixelRatio: Double?
        var zoom: Double?
    }

    var provider: String
    var identity: Identity?
    var web: WebElementBlock?
    var framework: FrameworkElementBlock?
    var bounds: Bounds
}

final class WebElementBridge: @unchecked Sendable {
    static let shared = WebElementBridge()
    static let port: UInt16 = 47845
    /// How long a lookup waits for the page before the picker falls back to AX-only.
    private static let lookupTimeout: TimeInterval = 0.25

    private struct HelloInfo {
        var sdkVersion: String?
        var framework: String?
        var adapter: String?
        var url: String?
        var devicePixelRatio: Double?
    }

    private final class Client {
        let connection: NWConnection
        var hello: HelloInfo?
        init(connection: NWConnection) { self.connection = connection }
    }

    private struct PendingLookup {
        var continuation: CheckedContinuation<WebElementSnapshotPayload?, Never>
        var remaining: Int
    }

    private struct IncomingMessage: Decodable {
        var type: String
        var sdkVersion: String?
        var framework: String?
        var adapter: String?
        var url: String?
        var devicePixelRatio: Double?
        var id: String?
        var snapshot: WebElementSnapshotPayload?
    }

    /// All mutable state is confined to `queue`.
    private let queue = DispatchQueue(label: "syn.web-element-bridge")
    private var listener: NWListener?
    private var clients: [ObjectIdentifier: Client] = [:]
    private var pendingLookups: [String: PendingLookup] = [:]
    private var started = false

    private init() {}

    /// True when at least one page has completed the hello handshake.
    var hasClients: Bool {
        queue.sync { clients.values.contains { $0.hello != nil } }
    }

    /// One line per connected page, for diagnostics surfaces.
    var connectedClientDescriptions: [String] {
        queue.sync {
            clients.values.compactMap { client in
                guard let hello = client.hello else { return nil }
                let framework = hello.framework ?? "unknown"
                let url = hello.url ?? "unknown-url"
                return "\(framework) @ \(url) (sdk \(hello.sdkVersion ?? "?"))"
            }
        }
    }

    func start() {
        queue.async {
            guard !self.started else { return }
            self.started = true
            self.startListener()
        }
    }

    func stop() {
        queue.async {
            self.started = false
            self.listener?.cancel()
            self.listener = nil
            self.clients.values.forEach { $0.connection.cancel() }
            self.clients = [:]
            for (id, pending) in self.pendingLookups {
                self.pendingLookups[id] = nil
                pending.continuation.resume(returning: nil)
            }
        }
    }

    // MARK: Lookup

    /// Asks connected pages for the element at a global Cocoa point and merges the
    /// answer over the AX snapshot. Returns nil when no page claims the point, so the
    /// caller can fall back to the AX snapshot unchanged.
    @MainActor
    func snapshot(atCocoaPoint cocoaPoint: CGPoint, merging ax: FlaggedElementSnapshot?) async -> FlaggedElementSnapshot? {
        let primaryHeight = Self.primaryScreenHeight()
        let topLeft = CGPoint(x: cocoaPoint.x, y: primaryHeight - cocoaPoint.y)
        guard let payload = await lookup(atTopLeftPoint: topLeft) else { return nil }
        var snapshot = Self.flaggedSnapshot(payload: payload, primaryScreenHeight: primaryHeight, merging: ax)
        // Chrome's AX hit-test fails often, losing app/window context; the window
        // list still knows whose window is under the point.
        if snapshot != nil, snapshot?.appBundleID == nil,
           let owner = Self.windowOwner(atTopLeftPoint: topLeft) {
            snapshot?.appName = owner.appName
            snapshot?.appBundleID = owner.bundleID
            snapshot?.windowTitle = owner.windowTitle
        }
        return snapshot
    }

    /// Frontmost on-screen window (excluding Syn's own overlays) containing the point.
    private static func windowOwner(
        atTopLeftPoint point: CGPoint
    ) -> (appName: String?, bundleID: String?, windowTitle: String?)? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return nil }
        let ownPid = ProcessInfo.processInfo.processIdentifier
        for window in windows {
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, pid != ownPid,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let boundsDict = window[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let bounds = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )
            guard bounds.contains(point) else { continue }
            let app = NSRunningApplication(processIdentifier: pid)
            return (
                appName: (window[kCGWindowOwnerName as String] as? String) ?? app?.localizedName,
                bundleID: app?.bundleIdentifier,
                windowTitle: window[kCGWindowName as String] as? String
            )
        }
        return nil
    }

    private func lookup(atTopLeftPoint point: CGPoint) async -> WebElementSnapshotPayload? {
        await withCheckedContinuation { continuation in
            queue.async {
                let ready = self.clients.values.filter { $0.hello != nil }
                guard !ready.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }
                let id = UUID().uuidString
                self.pendingLookups[id] = PendingLookup(continuation: continuation, remaining: ready.count)
                let message = """
                {"type":"lookup","id":"\(id)","screenX":\(point.x),"screenY":\(point.y)}
                """
                for client in ready {
                    self.send(text: message, over: client.connection)
                }
                self.queue.asyncAfter(deadline: .now() + Self.lookupTimeout) {
                    self.resolveLookup(id: id, snapshot: nil, force: true)
                }
            }
        }
    }

    /// On `queue`. First non-nil snapshot wins; nil answers count down until exhausted.
    private func resolveLookup(id: String, snapshot: WebElementSnapshotPayload?, force: Bool = false) {
        guard var pending = pendingLookups[id] else { return }
        if let snapshot {
            pendingLookups[id] = nil
            pending.continuation.resume(returning: snapshot)
            return
        }
        pending.remaining -= 1
        if force || pending.remaining <= 0 {
            pendingLookups[id] = nil
            pending.continuation.resume(returning: nil)
        } else {
            pendingLookups[id] = pending
        }
    }

    // MARK: Listener / connections

    /// On `queue`.
    private func startListener() {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        // Loopback only: pages on this machine can reach Syn; nothing else can.
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: .ipv4(.loopback),
            port: NWEndpoint.Port(rawValue: Self.port)!
        )
        let webSocketOptions = NWProtocolWebSocket.Options()
        webSocketOptions.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(webSocketOptions, at: 0)

        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            NSLog("Syn web element bridge failed to create listener on :\(Self.port): \(error)")
            scheduleListenerRetry()
            return
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.queue.async { self?.accept(connection) }
        }
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            self.queue.async {
                if case .failed(let error) = state {
                    NSLog("Syn web element bridge listener failed: \(error)")
                    self.listener?.cancel()
                    self.listener = nil
                    self.scheduleListenerRetry()
                }
            }
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    /// On `queue`. The port can be briefly occupied (stale instance); retry quietly.
    private func scheduleListenerRetry() {
        queue.asyncAfter(deadline: .now() + 5) {
            guard self.started, self.listener == nil else { return }
            self.startListener()
        }
    }

    /// On `queue`.
    private func accept(_ connection: NWConnection) {
        let client = Client(connection: connection)
        clients[ObjectIdentifier(connection)] = client
        connection.stateUpdateHandler = { [weak self, weak client] state in
            guard let self else { return }
            self.queue.async {
                switch state {
                case .failed, .cancelled:
                    if let client { self.remove(client) }
                default:
                    break
                }
            }
        }
        connection.start(queue: queue)
        receiveLoop(on: client)
    }

    /// On `queue`.
    private func remove(_ client: Client) {
        clients[ObjectIdentifier(client.connection)] = nil
        client.connection.cancel()
    }

    /// On `queue`.
    private func receiveLoop(on client: Client) {
        client.connection.receiveMessage { [weak self, weak client] data, context, _, error in
            guard let self, let client else { return }
            self.queue.async {
                if let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
                    as? NWProtocolWebSocket.Metadata, metadata.opcode == .close {
                    self.remove(client)
                    return
                }
                if error != nil {
                    self.remove(client)
                    return
                }
                if let data, !data.isEmpty {
                    self.handle(data: data, from: client)
                }
                self.receiveLoop(on: client)
            }
        }
    }

    /// On `queue`.
    private func handle(data: Data, from client: Client) {
        guard let message = try? JSONDecoder().decode(IncomingMessage.self, from: data) else { return }
        switch message.type {
        case "hello":
            client.hello = HelloInfo(
                sdkVersion: message.sdkVersion,
                framework: message.framework,
                adapter: message.adapter,
                url: message.url,
                devicePixelRatio: message.devicePixelRatio
            )
            let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
            send(text: #"{"type":"helloAck","app":"Syn","version":"\#(version)"}"#, over: client.connection)
        case "element":
            if let id = message.id {
                resolveLookup(id: id, snapshot: message.snapshot)
            }
        default:
            break
        }
    }

    /// On `queue`.
    private func send(text: String, over connection: NWConnection) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "text", metadata: [metadata])
        connection.send(
            content: Data(text.utf8),
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed { _ in }
        )
    }

    // MARK: Snapshot conversion

    static func primaryScreenHeight() -> CGFloat {
        (NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.screens.first)?
            .frame.height ?? 0
    }

    /// Browser snapshot wins; app/window context comes from AX (the page cannot know
    /// it); the AX identity is preserved in `rawProviders` per the PRD merge rule.
    static func flaggedSnapshot(
        payload: WebElementSnapshotPayload,
        primaryScreenHeight: CGFloat,
        merging ax: FlaggedElementSnapshot?
    ) -> FlaggedElementSnapshot? {
        guard let screen = payload.bounds.screen, screen.width > 0.5, screen.height > 0.5 else { return nil }
        let cocoaBounds = CGRect(
            x: screen.x,
            y: primaryScreenHeight - screen.y - screen.height,
            width: screen.width,
            height: screen.height
        )
        var rawProviders: [RawProviderSnapshot] = []
        if let ax {
            rawProviders.append(RawProviderSnapshot(
                provider: ax.provider,
                role: ax.role,
                label: ax.label,
                value: ax.value,
                identifier: ax.identifier
            ))
        }
        return FlaggedElementSnapshot(
            index: 0,
            timestamp: 0,
            provider: payload.provider,
            role: payload.identity?.role ?? payload.web?.tagName,
            label: payload.identity?.label,
            value: payload.identity?.text,
            identifier: payload.identity?.testId ?? payload.web?.selector,
            appName: ax?.appName,
            appBundleID: ax?.appBundleID,
            windowTitle: ax?.windowTitle,
            screenBounds: CodableRect(cocoaBounds),
            videoBounds: nil,
            web: payload.web,
            framework: payload.framework,
            rawProviders: rawProviders.isEmpty ? nil : rawProviders
        )
    }
}
