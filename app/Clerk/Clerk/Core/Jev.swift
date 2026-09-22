import Foundation

/// TypeSafe System One. Yes/no questions in, numbers out.
///
/// It is only ever asked what KIND of thing a field wants. No value from the
/// page and no value from the store is put in a prompt - see `Match.maskedState`
/// and `Match.scrub`.
enum Jev {
    static let url = URL(string: "https://api.typesafe.ai/v1/systemone")!
    /// With no key of your own the app posts here instead, and the key stays on
    /// the server. The app ships no key at all: it is published as a public zip,
    /// so anything inside it can be read by anyone who unzips it.
    static let proxy = URL(string: "https://dancykier.com/clerk/ai")!
    static let model = "jev-latest"

    struct Answer: Decodable { let noul: Double? }
    struct Reply: Decodable { let answers: [String: Answer] }

    /// questions: [name: instruction] -> [name: score]. One call, whatever the
    /// count: extra questions barely cost latency and decomposing beats one big
    /// multiple choice.
    static func nouls(state: String, questions: [String: String], key: String,
                      retries: Int = 3) async throws -> [String: Double] {
        guard !questions.isEmpty else { return [:] }
        let body: [String: Any] = [
            "state": state,
            "model": model,
            "questions": questions.mapValues { ["type": "noul", "instructions": $0] },
        ]
        // An empty key means "use the shared one", which only the proxy holds.
        var req = URLRequest(url: key.isEmpty ? proxy : url)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        if !key.isEmpty {
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        var last: Error = JevError.failed("no attempt ran")
        for attempt in 0..<retries {
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                    throw JevError.failed("HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0)")
                }
                let reply = try JSONDecoder().decode(Reply.self, from: data)
                return reply.answers.compactMapValues(\.noul)
            } catch {
                last = error
                try? await Task.sleep(nanoseconds: UInt64(400_000_000 * (attempt + 1)))
            }
        }
        throw last
    }
}

enum JevError: LocalizedError {
    case failed(String)
    var errorDescription: String? {
        switch self {
        case .failed(let m): return "Jev failed: \(m)"
        }
    }
}
