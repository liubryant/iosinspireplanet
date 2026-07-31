import Foundation

enum InspireChatRole: String, Codable {
    case system, user, assistant
}

struct InspireChatMessage: Codable {
    let role: InspireChatRole
    let content: String
}

final class InspireConversationService {
    private let endpoint = URL(string: "https://www.cjym123.cn/v1/chat/completions")!

    func reply(to messages: [InspireChatMessage], completion: @escaping (Result<String, Error>) -> Void) {
        var request = URLRequest(url: endpoint, timeoutInterval: 300)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": "glm-4.7",
            "stream": false,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        ])
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error { completion(.failure(error)); return }
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode,
                  let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                completion(.failure(NSError(
                    domain: "InspireConversationService",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "智能体服务暂时不可用"]
                )))
                return
            }
            completion(.success(content))
        }.resume()
    }
}
