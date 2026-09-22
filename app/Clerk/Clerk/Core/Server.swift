import Foundation
import Combine
import Network

/// The loopback bridge the browser extension talks to.
///
/// It listens on 127.0.0.1 only and sends NO CORS headers on purpose: a web page
/// can fire a request at it, but the browser will not let that page read the
/// answer. The extension is exempt because it holds a host permission. A token
/// is still required, so no other program on this Mac can ask it questions.
@MainActor
final class Server: ObservableObject {
    static let port: NWEndpoint.Port = 8771

    @Published private(set) var running = false
    @Published private(set) var lastError: String?
    @Published private(set) var fills = 0
    /// When the browser extension last spoke to us. `nil` means it never has,
    /// which is almost always the answer to "why does nothing happen".
    @Published private(set) var lastSeen: Date?

    private var listener: NWListener?
    private var data = StoreData()
    private var jevKey = ""

    /// Reads the store. `demo` data is handed in instead, so `-DemoScreen` can
    /// answer the extension with made-up people and the whole path can be tried
    /// without real data anywhere near it.
    func reload(_ demo: StoreData? = nil) {
        data = demo ?? Store.load()
        jevKey = data.jevKey
        Match.offline = data.offline
    }

    private var demoData: StoreData?

    func start(demo: StoreData? = nil) {
        stop()
        demoData = demo
        reload(demo)
        do {
            // Bind through requiredLocalEndpoint ALONE. Passing `on: port` as
            // well makes the listener fail silently and nothing ever listens.
            let params = NWParameters.tcp
            params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: Self.port)
            params.allowLocalEndpointReuse = true
            let l = try NWListener(using: params)
            l.newConnectionHandler = { [weak self] conn in
                conn.start(queue: .main)
                Task { @MainActor in self?.serve(conn) }
            }
            l.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready: self?.running = true; self?.lastError = nil
                    case .failed(let e):
                        self?.running = false
                        self?.lastError = "\(e)"
                        NSLog("Clerk: listener failed: \(e)")
                    case .waiting(let e):
                        self?.lastError = "waiting: \(e)"
                        NSLog("Clerk: listener waiting: \(e)")
                    case .cancelled: self?.running = false
                    default: break
                    }
                }
            }
            l.start(queue: .main)
            listener = l
            Self.appendLog("helper started on \(Self.port)")
        } catch {
            lastError = "\(error)"
            running = false
            NSLog("Clerk: listener could not start: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        running = false
    }

    // MARK: - a very small HTTP server

    private func serve(_ conn: NWConnection, buffer: Data = Data()) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] chunk, _, done, _ in
            Task { @MainActor in
                guard let self else { return }
                var buf = buffer
                if let chunk { buf.append(chunk) }
                guard let head = Self.headerEnd(buf) else {
                    if done { conn.cancel() } else { self.serve(conn, buffer: buf) }
                    return
                }
                let header = String(decoding: buf[..<head.0], as: UTF8.self)
                let length = Self.contentLength(header)
                let body = buf[head.1...]
                if body.count < length {
                    if done { conn.cancel() } else { self.serve(conn, buffer: buf) }
                    return
                }
                await self.respond(conn, header: header, body: Data(body.prefix(length)))
            }
        }
    }

    private static func headerEnd(_ d: Data) -> (Int, Int)? {
        let marker = Data("\r\n\r\n".utf8)
        guard let r = d.range(of: marker) else { return nil }
        return (r.lowerBound, r.upperBound)
    }

    private static func contentLength(_ header: String) -> Int {
        for line in header.split(separator: "\r\n") where line.lowercased().hasPrefix("content-length:") {
            return Int(line.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) ?? 0
        }
        return 0
    }

    private static func headerValue(_ header: String, _ name: String) -> String? {
        let want = name.lowercased() + ":"
        for line in header.split(separator: "\r\n") where line.lowercased().hasPrefix(want) {
            return String(line.dropFirst(want.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private func respond(_ conn: NWConnection, header: String, body: Data) async {
        let first = header.split(separator: "\r\n").first ?? ""
        let method = first.split(separator: " ").first.map(String.init) ?? "GET"
        let path = first.split(separator: " ").dropFirst().first.map(String.init) ?? "/"

        // Who is allowed in. A browser sets `Origin` itself on an extension's
        // request and a web page cannot forge it, so an extension origin is
        // proof enough and Nolan never has to paste anything. The token stays
        // as a way in for anything that is not an extension.
        let origin = Self.headerValue(header, "Origin") ?? ""
        let fromExtension = origin.hasPrefix("safari-web-extension://")
            || origin.hasPrefix("chrome-extension://")
            || origin.hasPrefix("moz-extension://")
        // Write-only diagnostics. No origin check on purpose: the whole point is
        // to hear from an extension that CANNOT reach the normal endpoints.
        if path == "/log" {
            let line = String(decoding: body, as: UTF8.self)
            lastSeen = Date()
            Self.appendLog(origin.isEmpty ? line : "\(line)   [origin \(origin)]")
            return send(conn, 200, Suggestion(ok: true), origin: origin)
        }

        // Safari enforces CORS on an extension's fetch; Chrome does not. Without
        // an answer to the preflight, and without Access-Control-Allow-Origin on
        // the reply, every call failed with a bare "TypeError: Load failed".
        //
        // The header is echoed back ONLY to an extension origin. A web page's
        // origin is https://..., gets no header, and so still cannot read a word
        // of the answer - which was the point of sending none at all.
        if method == "OPTIONS" {
            return sendRaw(conn, 204, Data(), origin: origin)
        }

        // NO origin requirement. The log proved why: a GET carries no `Origin`
        // header, so /config was refused with 403 and the extension reported
        // "no shortcut came back from the app". Browsers also omit Origin on an
        // extension's fetch to a host it already has permission for, so the
        // check could refuse /suggest too - silently, and only in Safari.
        //
        // The real protection is elsewhere and does not depend on a header:
        // the listener is bound to 127.0.0.1, and NO CORS headers are sent, so
        // a web page can fire a request here but the browser will never let that
        // page read the answer.
        if fromExtension { lastSeen = Date() }

        // A form to try things on, served by the app so the extension can run on
        // it: a file:// page is not somewhere Safari will let an extension go.
        if path == "/test" || path == "/test/" {
            let url = Bundle.main.url(forResource: "testpage", withExtension: "html")
                ?? Bundle.main.builtInPlugInsURL?
                    .appendingPathComponent("Clerk Extension.appex/Contents/Resources/testpage.html")
            let html = url.flatMap { try? Data(contentsOf: $0) }
                ?? Data("<h1>testpage.html is missing from the build</h1>".utf8)
            return sendRaw(conn, 200, html, origin: origin, contentType: "text/html; charset=utf-8")
        }
        if path == "/profiles" {
            let page = try? JSONDecoder().decode(FormPayload.self, from: body)
            let list = Match.profiles(data, page: page)
            return sendRaw(conn, 200, (try? JSONEncoder().encode(list)) ?? Data("[]".utf8),
                           origin: origin)
        }
        if path == "/config" {
            // The extension asks for the shortcut on every page load, so it is
            // set here in the app and nowhere else.
            return sendRaw(conn, 200,
                           (try? JSONEncoder().encode(data.shortcut)) ?? Data("{}".utf8),
                           origin: origin)
        }
        guard path == "/suggest" || path == "/fill-form" else {
            return send(conn, 404, Suggestion(ok: false, error: "no such path"), origin: origin)
        }
        guard let payload = try? JSONDecoder().decode(FormPayload.self, from: body) else {
            return send(conn, 400, Suggestion(ok: false, error: "bad json"), origin: origin)
        }
        if path == "/fill-form" {
            let all = await Match.suggestAll(payload, data: data, jevKey: jevKey)
            fills += all.results.count
            return sendRaw(conn, 200, (try? JSONEncoder().encode(all)) ?? Data("{}".utf8),
                           origin: origin)
        }
        let out = await Match.suggest(payload, data: data, jevKey: jevKey)
        if out.ok { fills += 1 }
        send(conn, 200, out, origin: origin)
    }

    static let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Clerk.log")

    /// Values never reach this file - the extension sends field labels and
    /// outcomes, nothing it filled in.
    static func appendLog(_ line: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        guard let d = "\(stamp)  \(line)\n".data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: logURL) {
            h.seekToEndOfFile()
            try? h.write(contentsOf: d)
            try? h.close()
        } else {
            try? d.write(to: logURL)
        }
    }

    private func send(_ conn: NWConnection, _ code: Int, _ obj: Suggestion,
                      origin: String = "") {
        sendRaw(conn, code, (try? JSONEncoder().encode(obj)) ?? Data("{}".utf8), origin: origin)
    }

    static func isExtension(_ origin: String) -> Bool {
        origin.hasPrefix("safari-web-extension://") || origin.hasPrefix("chrome-extension://")
            || origin.hasPrefix("moz-extension://") || origin == "null"
    }

    private func sendRaw(_ conn: NWConnection, _ code: Int, _ json: Data,
                         origin: String = "",
                         contentType: String = "application/json") {
        var head = "HTTP/1.1 \(code) \(code == 200 ? "OK" : "No Content")\r\n"
        head += "Content-Type: \(contentType)\r\n"
        if Self.isExtension(origin) {
            head += "Access-Control-Allow-Origin: \(origin)\r\n"
            head += "Access-Control-Allow-Methods: POST, GET, OPTIONS\r\n"
            head += "Access-Control-Allow-Headers: Content-Type\r\n"
            head += "Access-Control-Max-Age: 600\r\n"
        }
        head += "Content-Length: \(json.count)\r\n"
        head += "Connection: close\r\n\r\n"
        conn.send(content: Data(head.utf8) + json,
                  completion: .contentProcessed { _ in conn.cancel() })
    }
}
