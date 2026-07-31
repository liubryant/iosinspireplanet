import SwiftUI
import UIKit
import Combine

struct DigitalHumanConversationView: View {
    @ObservedObject var model: DigitalHumanConversationModel
    @ObservedObject private var lily: LilyDigitalHumanController
    @StateObject private var keyboard = DigitalHumanKeyboardObserver()
    @State private var showLiveLily = false
    @FocusState private var inputFocused: Bool

    init(model: DigitalHumanConversationModel) {
        self.model = model
        _lily = ObservedObject(wrappedValue: model.lily)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                    .ignoresSafeArea()

                lilyStage()
                    .frame(
                        width: proxy.size.width,
                        height: proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
                    )
                    .ignoresSafeArea()

                LinearGradient(
                    colors: [.clear, .clear, Color.black.opacity(0.16), Color.black.opacity(0.48)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                HStack(spacing: 10) {
                    topIdentityBadge
                    Spacer(minLength: 12)
                    if model.activity != .idle {
                        DigitalHumanLoadingCarousel(activity: model.activity)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                    .padding(.top, proxy.safeAreaInsets.top + 2)
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                VStack(spacing: 0) {
                    Spacer()
                        .frame(
                            height: inputFocused
                                ? max(80, proxy.size.height * 0.16)
                                : max(270, proxy.size.height * 0.43)
                        )

                    conversation
                        .frame(maxHeight: proxy.size.height * (inputFocused ? 0.22 : 0.27))

                    composer

                    if !inputFocused {
                        personaSwitcher
                            .transition(.opacity)
                    }
                }
                .padding(
                    .bottom,
                    inputFocused
                        ? keyboard.height + 8
                        : max(2, proxy.safeAreaInsets.bottom * 0.15)
                )
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .bottom
                )
                .animation(.easeOut(duration: keyboard.animationDuration), value: keyboard.height)
                .animation(.easeOut(duration: 0.22), value: inputFocused)
            }
            .ignoresSafeArea(.all)
        }
        .onAppear {
            model.lily.setPageVisible(true)
            if model.lily.state.isReady {
                revealReadyLily()
                model.lily.activateIdleMotion()
            }
        }
        .onDisappear {
            model.lily.setPageVisible(false)
            model.stopAll()
        }
    }

    private func lilyStage() -> some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                Image("LilyPortrait")
                    .resizable().scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height).clipped()
                    .opacity(showLiveLily ? 0 : (lily.persona == .lily ? 1 : 0))
                LilyDigitalHumanSurface(controller: lily)
                    .opacity(showLiveLily ? 1 : 0)
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                    Text("长按试一试")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.94))
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(
                    LinearGradient(
                        colors: model.canPlayGreeting
                            ? [Color(red: 0.72, green: 0.64, blue: 0.94), Color(red: 0.86, green: 0.73, blue: 0.96)]
                            : [Color.gray.opacity(0.75), Color.gray.opacity(0.55)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(6)
                .padding(.trailing, 14)
                .padding(.bottom, max(330, proxy.size.height * 0.48))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.55) {
                model.playRandomGreeting()
            }
        }
        .onChange(of: model.lily.state) { state in
            guard state.isReady else { showLiveLily = false; return }
            revealReadyLily()
            model.lily.activateIdleMotion()
        }
        .onAppear {
            guard model.lily.state.isReady else { return }
            revealReadyLily()
            model.lily.activateIdleMotion()
        }
    }

    private var topIdentityBadge: some View {
        HStack(spacing: 8) {
            Text("AI数字人")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(identityTextGradient)

            Rectangle()
                .fill(Color.black.opacity(0.14))
                .frame(width: 1, height: 18)

            Text(lily.persona.displayName.uppercased())
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(identityTextGradient)
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.32), lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.black.opacity(0.14), radius: 8, y: 3)
    }

    private var identityTextGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.20, green: 0.66, blue: 0.96),
                Color(red: 0.54, green: 0.42, blue: 0.94),
                Color(red: 0.94, green: 0.38, blue: 0.72)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var personaSwitcher: some View {
        HStack(spacing: 8) {
            ForEach(DigitalHumanPersona.allCases) { persona in
                Button {
                    guard lily.persona != persona else { return }
                    showLiveLily = false
                    model.stopAll()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        model.selectPersona(persona)
                    }
                } label: {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(lily.persona == persona ? Color.white.opacity(0.24) : Color.black.opacity(0.12))
                                .frame(width: 30, height: 30)
                            Image(persona == .lily ? "LilyThumbnail" : "LeoThumbnail")
                                .resizable()
                                .scaledToFill()
                                .frame(width: 30, height: 30)
                                .clipShape(Circle())
                        }
                        Text(persona.displayName)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                        if lily.persona == persona {
                            Image(systemName: lily.state.isReady ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                                .font(.system(size: 12, weight: .bold))
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 13)
                    .frame(height: 46)
                    .background(
                        Group {
                            if lily.persona == persona {
                                LinearGradient(
                                    colors: persona == .lily
                                        ? [Color(red: 0.48, green: 0.39, blue: 0.94), Color(red: 0.91, green: 0.42, blue: 0.72)]
                                        : [Color(red: 0.12, green: 0.46, blue: 0.86), Color(red: 0.18, green: 0.72, blue: 0.72)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            } else {
                                Color.black.opacity(0.30)
                            }
                        }
                    )
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(lily.persona == persona ? 0.55 : 0.22), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.18), radius: 10, y: 4)
                }
                .buttonStyle(.plain)
                .disabled(model.activity != .idle || lily.state == .loading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial.opacity(0.72))
        .clipShape(Capsule())
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func revealReadyLily() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard model.lily.state.isReady else { return }
            showLiveLily = true
        }
    }

    private var conversation: some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if let error = model.errorMessage {
                        Text(error).font(.caption).foregroundColor(.red)
                            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.08)).cornerRadius(10)
                    }
                    ForEach(model.turns) { turn in
                        DigitalHumanBubble(
                            turn: turn,
                            assistantName: lily.persona.displayName,
                            highlightedRange: model.highlightedTurnID == turn.id ? model.highlightedRange : nil,
                            onRead: { model.read(turn) }
                        ).id(turn.id)
                    }
                    if model.activity == .thinking {
                        DigitalHumanThinkingCarousel()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("thinking")
                    }
                }.padding(14)
            }
            .background(Color.black.opacity(0.20))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.24), lineWidth: 0.8)
            )
            .padding(.horizontal, 10)
            .onChange(of: model.turns.count) { _ in
                if let last = model.turns.last { withAnimation { reader.scrollTo(last.id, anchor: .bottom) } }
            }
            .onAppear {
                guard let last = model.turns.last else { return }
                DispatchQueue.main.async {
                    reader.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 7) {
            HStack(spacing: 10) {
                Button(action: model.toggleListening) {
                    Image(systemName: model.activity == .listening ? "stop.fill" : "mic.fill")
                        .foregroundColor(.white).frame(width: 40, height: 40)
                        .background(model.activity == .listening ? Color.red : Color.indigo).clipShape(Circle())
                }
                TextField(
                    "",
                    text: $model.draft,
                    prompt: Text("和 \(lily.persona.displayName) 说点什么")
                        .foregroundColor(Color.white.opacity(0.42))
                )
                    .focused($inputFocused)
                    .foregroundColor(Color.white.opacity(0.78))
                    .padding(.horizontal, 12).frame(height: 42)
                    .background(Color.black.opacity(0.24)).cornerRadius(10)
                    .submitLabel(.send)
                    .onSubmit {
                        inputFocused = false
                        model.send()
                    }
                Button {
                    inputFocused = false
                    model.send()
                } label: {
                    Image(systemName: "paperplane.fill").foregroundColor(.white)
                        .frame(width: 42, height: 42)
                        .background(model.canSend ? Color.indigo : Color.gray.opacity(0.4)).cornerRadius(10)
                }.disabled(!model.canSend)
            }
            if model.activity != .idle {
                Button(action: model.stopAll) {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 13, weight: .semibold))
                        Text("停止当前会话")
                    }
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.22))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.24), lineWidth: 0.8)
        )
        .padding(.horizontal, 10)
    }
}

private final class DigitalHumanKeyboardObserver: ObservableObject {
    @Published private(set) var height: CGFloat = 0
    @Published private(set) var animationDuration: Double = 0.25

    private var cancellables: Set<AnyCancellable> = []

    init() {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
            .merge(with: NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification))
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self else { return }
                let info = notification.userInfo ?? [:]
                animationDuration = (info[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25

                if notification.name == UIResponder.keyboardWillHideNotification {
                    height = 0
                    return
                }
                guard let value = info[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else {
                    height = 0
                    return
                }
                let frame = value.cgRectValue
                let screenHeight = UIScreen.main.bounds.height
                // Floating/hardware keyboards do not intersect the bottom edge.
                height = frame.maxY >= screenHeight - 1
                    ? max(0, screenHeight - frame.minY)
                    : 0
            }
            .store(in: &cancellables)
    }
}

private struct DigitalHumanThinkingCarousel: View {
    private static let statuses = [
        "思考中…",
        "正在理解你的需求…",
        "正在规划回答步骤…",
        "正在查询相关信息…",
        "正在筛选可用结果…",
        "正在分析关键信息…",
        "正在组织语言…",
        "正在生成回答…"
    ]

    @State private var index = 0
    @State private var opacity = 1.0
    @State private var offset: CGFloat = 0
    @State private var timer: Timer?

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .indigo))
                .scaleEffect(0.72)
            Text(Self.statuses[index])
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.82))
                .opacity(opacity)
                .offset(y: offset)
        }
        .padding(.vertical, 8)
        .onAppear(perform: start)
        .onDisappear(perform: stop)
    }

    private func start() {
        index = 0
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { _ in advance() }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func advance() {
        withAnimation(.easeIn(duration: 0.14)) {
            opacity = 0
            offset = -4
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            index = (index + 1) % Self.statuses.count
            offset = 4
            withAnimation(.easeOut(duration: 0.20)) {
                opacity = 1
                offset = 0
            }
        }
    }
}

private struct DigitalHumanLoadingCarousel: View {
    let activity: DigitalHumanActivity
    @State private var phase = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { index in
                Capsule().fill(Color.indigo)
                    .frame(width: 4, height: CGFloat(14 + (index * 7) % 22))
                    .scaleEffect(y: phase ? 1 : 0.35)
                    .animation(.easeInOut(duration: 0.42).repeatForever(autoreverses: true).delay(Double(index) * 0.05), value: phase)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 54)
        .background(Color.black.opacity(0.24))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.20), lineWidth: 0.8)
        )
        .cornerRadius(14)
        .onAppear { phase = true }
    }
}

private struct DigitalHumanBubble: View {
    let turn: DigitalHumanTurn
    let assistantName: String
    let highlightedRange: NSRange?
    let onRead: () -> Void

    var body: some View {
        HStack {
            if turn.role == .user { Spacer(minLength: 45) }
            VStack(alignment: .leading, spacing: 5) {
                Text(turn.role == .user ? "我" : assistantName)
                    .font(.caption.bold())
                    .foregroundColor(Color.white.opacity(0.56))
                Text(attributedText)
                    .font(.system(size: 17))
                    .foregroundColor(Color.white.opacity(0.82))
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    .contextMenu {
                        Button(action: onRead) { Label("朗读", systemImage: "speaker.wave.2.fill") }
                        Button {
                            UIPasteboard.general.string = turn.content
                        } label: { Label("复制", systemImage: "doc.on.doc") }
                    }
            }
            .padding(11)
            .background(
                turn.role == .user
                    ? Color(red: 0.30, green: 0.28, blue: 0.72).opacity(0.42)
                    : Color.black.opacity(0.30)
            )
            .cornerRadius(10)
            if turn.role != .user { Spacer(minLength: 45) }
        }
    }

    private var attributedText: AttributedString {
        var result = AttributedString(turn.content)
        guard let range = highlightedRange,
              range.location != NSNotFound,
              let swiftRange = Range(range, in: turn.content),
              let attributedRange = Range(swiftRange, in: result) else { return result }
        result[attributedRange].backgroundColor = .init(Color.indigo.opacity(0.18))
        return result
    }
}
