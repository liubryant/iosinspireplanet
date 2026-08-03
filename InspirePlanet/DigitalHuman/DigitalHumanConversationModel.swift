import Foundation

@MainActor
final class DigitalHumanConversationModel: ObservableObject {
    @Published var draft = ""
    @Published private(set) var turns: [DigitalHumanTurn]
    @Published private(set) var activity: DigitalHumanActivity = .idle
    @Published var errorMessage: String?
    @Published private(set) var highlightedTurnID: UUID?
    @Published private(set) var highlightedRange: NSRange?
    @Published private(set) var inspirationPoints: Int
    @Published var isInsufficientPointsAlertPresented = false
    @Published var isLoginRequiredAlertPresented = false

    let lily = LilyDigitalHumanController.shared
    private let service = InspireConversationService()
    private let recognizer = InspireSpeechRecognizer()
    private let speaker = InspireSpeechSynthesizer()
    private let historyKey = "inspireplanet.digital-human.history"
    private static let inspirationPointsKey = "inspireplanet.inspiration-points"
    private static let loginGiftedAccountsKey = "inspireplanet.inspiration-login-gift-accounts"
    private static let loginGiftAmount = 50
    private var requestGeneration = 0
    private var streamingTurnID: UUID?
    private let lilyGreetings = [
        "你好，我是 Lily，很高兴认识你。",
        "嗨，见到你真开心，今天想聊点什么？",
        "你好呀，我一直在这里等你。",
        "欢迎回来，我是你的数字人伙伴 Lily。",
        "很高兴和你见面，有什么可以帮你的吗？",
        "嗨，我是 Lily，愿你今天有个好心情。",
        "你好，轻松一点，我们慢慢聊。",
        "见到你真好，我已经准备好听你说啦。",
        "你好呀，今天也让我陪在你身边吧。",
        "嗨，朋友，又到了我们打招呼的时间。"
    ]
    private let leoGreetings = [
        "你好，我是 Leo，很高兴认识你。",
        "嗨，我是 Leo，今天想一起聊点什么？",
        "欢迎来到灵感星球，我已经准备好啦。",
        "你好呀，有什么新想法都可以告诉我。",
        "见到你真高兴，让我们开始今天的对话吧。",
        "嗨，朋友，我会认真听你说。",
        "你好，我是你的创意伙伴 Leo。",
        "欢迎回来，今天也一起寻找灵感吧。"
    ]
    private let sofiaGreetings = [
        "你好，我是 Sofia，很高兴认识你。",
        "嗨，我是 Sofia，今天想聊些什么？",
        "欢迎来到灵感星球，我会认真听你说。",
        "你好呀，很高兴能陪你一起寻找灵感。",
        "见到你真好，有什么想法都可以告诉我。",
        "欢迎回来，我是你的知心伙伴 Sofia。",
        "嗨，朋友，今天也让我们轻松地聊一聊吧。",
        "你好，我已经准备好陪伴你啦。"
    ]
    private let kaiGreetings = [
        "你好，我是 Kai，很高兴认识你。",
        "嗨，我是 Kai，今天想一起聊点什么？",
        "欢迎来到灵感星球，我已经准备好啦。",
        "你好呀，有什么有趣的想法都可以告诉我。",
        "见到你真开心，让我们开始今天的对话吧。",
        "嗨，朋友，我会认真听你说。",
        "你好，我是你的活力伙伴 Kai。",
        "欢迎回来，今天也一起发现新灵感吧。"
    ]
    private let elenaFrostGreetings = [
        "你好，我是 Elena Frost，很高兴认识你。",
        "嗨，我是 Elena Frost，今天想聊些什么？",
        "欢迎来到灵感星球，我会认真倾听你的想法。",
        "你好呀，很高兴能陪你一起寻找灵感。",
        "见到你真好，有什么想说的都可以告诉我。",
        "欢迎回来，我是你的温暖伙伴 Elena Frost。",
        "嗨，朋友，让我们轻松地聊一聊吧。",
        "你好，我已经准备好陪伴你啦。"
    ]

    init() {
        if UserDefaults.standard.object(forKey: Self.inspirationPointsKey) == nil {
            UserDefaults.standard.set(100, forKey: Self.inspirationPointsKey)
        }
        inspirationPoints = max(0, UserDefaults.standard.integer(forKey: Self.inspirationPointsKey))

        if let data = UserDefaults.standard.data(forKey: historyKey),
           let saved = try? JSONDecoder().decode([DigitalHumanTurn].self, from: data), !saved.isEmpty {
            turns = saved
        } else {
            turns = [DigitalHumanTurn(role: .assistant, content: "你好，我是 Lily。你可以直接说话，也可以输入文字和我交流。")]
        }
        migrateDefaultGreeting(for: lily.persona)

        if UserDefaults.standard.bool(forKey: "inspire.user.isLoggedIn"),
           let phone = UserDefaults.standard.string(forKey: "inspire.user.phone") {
            applyLoginGiftIfNeeded(phone: phone)
        }
    }

    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && activity != .thinking
    }

    var canPlayGreeting: Bool {
        activity == .idle
    }

    var persona: DigitalHumanPersona {
        lily.persona
    }

    func applyLoginGiftIfNeeded(phone: String) {
        let account = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !account.isEmpty else { return }

        let defaults = UserDefaults.standard
        var giftedAccounts = Set(defaults.stringArray(forKey: Self.loginGiftedAccountsKey) ?? [])
        guard giftedAccounts.insert(account).inserted else { return }

        inspirationPoints += Self.loginGiftAmount
        defaults.set(inspirationPoints, forKey: Self.inspirationPointsKey)
        defaults.set(Array(giftedAccounts), forKey: Self.loginGiftedAccountsKey)
    }

    func selectPersona(_ persona: DigitalHumanPersona) {
        guard activity == .idle, lily.persona != persona else { return }
        errorMessage = nil
        migrateDefaultGreeting(for: persona)
        lily.switchPersona(to: persona)
    }

    func toggleListening() {
        activity == .listening ? stopListeningAndSend() : startListening()
    }

    func startListening() {
        guard activity != .thinking else { return }
        stopSpeaking()
        errorMessage = nil
        recognizer.requestAuthorization { [weak self] granted, message in
            guard let self else { return }
            if !granted {
                self.errorMessage = message ?? "语音权限未开启"
                return
            }
            self.activity = .listening
            self.recognizer.start { [weak self] text in
                DispatchQueue.main.async { self?.draft = text }
            } onError: { [weak self] message in
                DispatchQueue.main.async {
                    self?.errorMessage = "语音识别失败：\(message)"
                    self?.activity = .idle
                }
            }
        }
    }

    func stopListeningAndSend() {
        recognizer.stop()
        activity = .idle
        send()
    }

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, activity != .thinking else { return }
        guard let accessToken = InspireAccountSession.accessToken(), !accessToken.isEmpty else {
            // 同步清理可能残留的本地登录标记，确保“去登录”进入登录页而非账号管理页。
            InspireAccountSession.logout()
            errorMessage = "请先登录账号，再继续和数字人对话。"
            isLoginRequiredAlertPresented = true
            return
        }
        guard inspirationPoints >= 10 else {
            errorMessage = "当前灵感值不足，暂时无法继续对话。"
            isInsufficientPointsAlertPresented = true
            return
        }
        stopSpeaking()
        draft = ""
        errorMessage = nil
        turns.append(DigitalHumanTurn(role: .user, content: text))
        save()
        activity = .thinking
        requestGeneration += 1
        let generation = requestGeneration
        let context = [InspireChatMessage(
            role: .system,
            content: "你是灵感星球的拟人数字人 \(persona.displayName)。请用自然、口语化、简洁的中文回答，内容适合语音播报。"
        )] + turns.suffix(12).map { InspireChatMessage(role: $0.role, content: $0.content) }
        let assistantID = UUID()
        streamingTurnID = assistantID
        service.reply(to: context, onDelta: { [weak self] delta in
            DispatchQueue.main.async {
                guard let self, generation == self.requestGeneration else { return }
                if let index = self.turns.firstIndex(where: { $0.id == assistantID }) {
                    let content = self.turns[index].content + delta
                    self.turns[index] = DigitalHumanTurn(id: assistantID, role: .assistant, content: content)
                } else if !delta.isEmpty {
                    // 思考阶段只显示加载状态，收到首段正文后再创建人物回复框。
                    self.turns.append(DigitalHumanTurn(id: assistantID, role: .assistant, content: delta))
                }
            }
        }) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, generation == self.requestGeneration else { return }
                self.streamingTurnID = nil
                switch result {
                case .success(let text):
                    let answer = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    let finalText = answer.isEmpty ? "我暂时没有拿到有效回答，请稍后再试。" : answer
                    let turn = DigitalHumanTurn(id: assistantID, role: .assistant, content: finalText)
                    if let index = self.turns.firstIndex(where: { $0.id == assistantID }) {
                        self.turns[index] = turn
                    } else {
                        self.turns.append(turn)
                    }
                    self.save()
                    self.consumeInspirationPoints()
                    self.activity = .idle
                    self.read(turn)
                case .failure(let error):
                    self.turns.removeAll { $0.id == assistantID && $0.content.isEmpty }
                    self.save()
                    self.activity = .idle
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func read(_ turn: DigitalHumanTurn) {
        guard activity != .thinking, activity != .listening else { return }
        speak(turn.content, turnID: turn.id)
    }

    func playRandomGreeting() {
        guard canPlayGreeting else { return }
        let greetings: [String]
        switch persona {
        case .leo: greetings = leoGreetings
        case .lily: greetings = lilyGreetings
        case .sofia: greetings = sofiaGreetings
        case .kai: greetings = kaiGreetings
        case .elenaFrost: greetings = elenaFrostGreetings
        }
        speak(greetings.randomElement() ?? greetings[0])
    }

    private func speak(_ text: String, turnID: UUID? = nil) {
        stopSpeaking()
        highlightedTurnID = turnID
        let spoken = speechText(text)
        speaker.speak(spoken, voice: persona.voice, digitalHuman: lily) { [weak self] in
            DispatchQueue.main.async { self?.activity = .speaking }
        } onFinish: { [weak self] in
            DispatchQueue.main.async {
                self?.activity = .idle
                self?.highlightedTurnID = nil
                self?.highlightedRange = nil
            }
        } onRangeChange: { [weak self] range in
            DispatchQueue.main.async { self?.highlightedRange = range }
        }
    }

    func stopAll() {
        requestGeneration += 1
        service.cancel()
        if let id = streamingTurnID {
            turns.removeAll { $0.id == id && $0.content.isEmpty }
            streamingTurnID = nil
        }
        recognizer.stop()
        stopSpeaking()
        activity = .idle
    }

    private func stopSpeaking() {
        speaker.stop()
        highlightedTurnID = nil
        highlightedRange = nil
        if activity == .speaking { activity = .idle }
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(turns), forKey: historyKey)
    }

    private func consumeInspirationPoints() {
        inspirationPoints = max(0, inspirationPoints - 10)
        UserDefaults.standard.set(inspirationPoints, forKey: Self.inspirationPointsKey)
    }

    private func migrateDefaultGreeting(for persona: DigitalHumanPersona) {
        guard turns.count == 1, turns[0].role == .assistant,
              turns[0].content.contains("你可以直接说话") else { return }
        turns[0] = DigitalHumanTurn(
            role: .assistant,
            content: "你好，我是 \(persona.displayName)。你可以直接说话，也可以输入文字和我交流。"
        )
        save()
    }

    private func speechText(_ value: String) -> String {
        var text = value.replacingOccurrences(of: #"(?s)```.*?```"#, with: "代码内容已显示在对话中。", options: .regularExpression)
        text = text.replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"[*_#>`~-]"#, with: "", options: .regularExpression)
        return String(text.prefix(700))
    }
}
