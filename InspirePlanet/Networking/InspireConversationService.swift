import Foundation

enum InspireChatRole: String, Codable {
    case system, user, assistant
}

struct InspireChatMessage: Codable {
    let role: InspireChatRole
    let content: String
}

final class InspireConversationService {
    private let endpoint = URL(string: "https://www.cjym123.cn/v1/apps/inspireplanet/chat/completions")!
    private var stream: InspireSSEStream?

    @discardableResult
    func reply(
        to messages: [InspireChatMessage],
        onDelta: @escaping (String) -> Void,
        completion: @escaping (Result<String, Error>) -> Void
    ) -> URLSessionDataTask? {
        cancel()
        var request = URLRequest(url: endpoint, timeoutInterval: 180)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if let token = InspireAccountSession.accessToken(), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": "doubao-seed-evolving",
            "stream": true,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        ])

        let stream = InspireSSEStream(onDelta: onDelta) { [weak self] result in
            self?.stream = nil
            completion(result)
        }
        self.stream = stream
        stream.start(request)
        return stream.task
    }

    func cancel() {
        stream?.cancel()
        stream = nil
    }
}

private final class InspireSSEStream: NSObject, URLSessionDataDelegate {
    private let onDelta: (String) -> Void
    private let completion: (Result<String, Error>) -> Void
    private var session: URLSession?
    private var buffer = ""
    private var answer = ""
    private var errorBody = Data()
    private var statusCode = 0
    private var finished = false
    fileprivate private(set) var task: URLSessionDataTask?

    init(onDelta: @escaping (String) -> Void, completion: @escaping (Result<String, Error>) -> Void) {
        self.onDelta = onDelta
        self.completion = completion
    }

    func start(_ request: URLRequest) {
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        self.session = session
        let task = session.dataTask(with: request)
        self.task = task
        task.resume()
    }

    func cancel() {
        finished = true
        task?.cancel()
        session?.invalidateAndCancel()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard 200..<300 ~= statusCode else { errorBody.append(data); return }
        buffer += String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\r\n", with: "\n")
        while let range = buffer.range(of: "\n\n") {
            let event = String(buffer[..<range.lowerBound])
            buffer.removeSubrange(buffer.startIndex..<range.upperBound)
            consume(event)
        }
    }

    private func consume(_ event: String) {
        for line in event.split(separator: "\n", omittingEmptySubsequences: true) {
            guard line.hasPrefix("data:") else { continue }
            let data = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if data == "[DONE]" { return }
            guard let bytes = data.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let content = delta["content"] as? String, !content.isEmpty else { continue }
            answer += content
            onDelta(content)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !finished else { return }
        finished = true
        defer { session.finishTasksAndInvalidate() }
        if let error { completion(.failure(error)); return }
        guard 200..<300 ~= statusCode else {
            let message = serverErrorMessage() ?? "智能体服务暂时不可用（HTTP \(statusCode)）"
            completion(.failure(NSError(domain: "InspireConversationService", code: statusCode,
                                        userInfo: [NSLocalizedDescriptionKey: message])))
            return
        }
        completion(.success(answer))
    }

    private func serverErrorMessage() -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: errorBody) as? [String: Any],
              let error = json["error"] as? [String: Any] else { return nil }
        return error["message"] as? String
    }
}
