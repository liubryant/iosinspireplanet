import SwiftUI
import UIKit
import Combine
import Security

struct DigitalHumanConversationView: View {
    @ObservedObject var model: DigitalHumanConversationModel
    @ObservedObject private var lily: LilyDigitalHumanController
    @StateObject private var keyboard = DigitalHumanKeyboardObserver()
    @State private var showLiveLily = false
    @State private var isSidebarPresented = false
    @State private var presentedSheet: InspirePresentedSheet?
    @State private var showAccountOverlay = false
    @AppStorage("inspire.user.isLoggedIn") private var isLoggedIn = false
    @AppStorage("inspire.user.phone") private var userPhone = ""
    @FocusState private var inputFocused: Bool

    init(model: DigitalHumanConversationModel) {
        self.model = model
        _lily = ObservedObject(wrappedValue: model.lily)
    }

    var body: some View {
        GeometryReader { proxy in
            let sidebarWidth = min(proxy.size.width * 0.84, 344)

            ZStack(alignment: .leading) {
                InspireSidebarView(
                    isLoggedIn: isLoggedIn,
                    phone: userPhone,
                    onLogin: {
                        if isLoggedIn && !userPhone.isEmpty {
                            withAnimation(.easeInOut(duration: 0.28)) { showAccountOverlay = true }
                        } else {
                            withAnimation(.easeInOut(duration: 0.28)) { presentedSheet = .account }
                        }
                        closeSidebar()
                    },
                    onSelect: { page in
                        withAnimation(.easeInOut(duration: 0.28)) { presentedSheet = .sidebar(page) }
                        closeSidebar()
                    },
                    onLogout: {
                        withAnimation(.easeInOut(duration: 0.28)) { showAccountOverlay = true }
                        closeSidebar()
                    }
                )
                .frame(width: sidebarWidth)
                .offset(x: isSidebarPresented ? 0 : -sidebarWidth)
                .zIndex(2)

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

                HStack(spacing: 2) {
                    Button {
                        inputFocused = false
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                            isSidebarPresented.toggle()
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 48, height: 48)
                            .background(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.32), lineWidth: 0.8)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    topIdentityBadge
                    Spacer(minLength: 12)
                }
                    .padding(.top, proxy.safeAreaInsets.top + 12)
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                if model.activity != .idle {
                    DigitalHumanLoadingCarousel(activity: model.activity)
                        .transition(.scale.combined(with: .opacity))
                        .padding(.top, proxy.safeAreaInsets.top + 7)
                        .padding(.trailing, 18)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }

                VStack(spacing: 0) {
                    Spacer()
                        .frame(
                            height: inputFocused
                                ? max(80, proxy.size.height * 0.16)
                                : max(270, proxy.size.height * 0.43)
                        )

                    longPressHint
                        .padding(.trailing, 14)
                        .padding(.bottom, 6)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .allowsHitTesting(false)

                    conversation
                        .frame(maxHeight: proxy.size.height * (inputFocused ? 0.147 : 0.18))

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
                .frame(width: proxy.size.width, height: proxy.size.height)
                .offset(x: isSidebarPresented ? sidebarWidth : 0)
                .overlay {
                    if isSidebarPresented {
                        Color.black.opacity(0.20)
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture(perform: closeSidebar)
                    }
                }
                .shadow(color: .black.opacity(isSidebarPresented ? 0.42 : 0), radius: 22, x: -8)
                .zIndex(1)

                if showAccountOverlay {
                    InspireAccountView(onClose: {
                        withAnimation(.easeInOut(duration: 0.28)) { showAccountOverlay = false }
                    })
                        .preferredColorScheme(.light)
                        .transition(.move(edge: .trailing))
                        .zIndex(10)
                }

                if let presentedSheet {
                    presentedPage(presentedSheet)
                        .transition(.move(edge: .trailing))
                        .zIndex(11)
                }
            }
            .background(Color(red: 0.11, green: 0.13, blue: 0.15).ignoresSafeArea())
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: isSidebarPresented)
        }
        // 由当前页面统一按照通知中的实际键盘高度避让，避免 SwiftUI 自动
        // 压缩与手动 padding 同时生效造成输入框过高。
        .ignoresSafeArea(.keyboard, edges: .bottom)
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

    @ViewBuilder
    private func presentedPage(_ sheet: InspirePresentedSheet) -> some View {
        switch sheet {
        case .account:
            InspireAccountView(onClose: closePresentedPage)
                .preferredColorScheme(.light)
        case .sidebar(let page):
            InspireSidebarDetailView(page: page, isLoggedIn: isLoggedIn, onClose: closePresentedPage)
                .preferredColorScheme(.dark)
        }
    }

    private func closePresentedPage() {
        withAnimation(.easeInOut(duration: 0.28)) {
            presentedSheet = nil
        }
    }

    private func closeSidebar() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            isSidebarPresented = false
        }
    }

    private func lilyStage() -> some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                if let portraitAssetName = lily.persona.portraitAssetName {
                    Image(portraitAssetName)
                        .resizable().scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height).clipped()
                        .opacity(showLiveLily ? 0 : 1)
                }
                LilyDigitalHumanSurface(controller: lily)
                    .opacity(showLiveLily ? 1 : 0)
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

    private var longPressHint: some View {
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
                            Image(persona.thumbnailAssetName)
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
                                    colors: selectedPersonaGradient(for: persona),
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

    private func selectedPersonaGradient(for persona: DigitalHumanPersona) -> [Color] {
        switch persona {
        case .leo:
            return [Color(red: 0.12, green: 0.46, blue: 0.86), Color(red: 0.18, green: 0.72, blue: 0.72)]
        case .lily:
            return [Color(red: 0.48, green: 0.39, blue: 0.94), Color(red: 0.91, green: 0.42, blue: 0.72)]
        case .sofia:
            return [Color(red: 0.23, green: 0.52, blue: 0.91), Color(red: 0.55, green: 0.43, blue: 0.86)]
        }
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
            .onChange(of: model.turns.last?.content) { _ in
                if let last = model.turns.last { reader.scrollTo(last.id, anchor: .bottom) }
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

private enum InspirePresentedSheet: Identifiable {
    case account
    case sidebar(InspireSidebarPage)

    var id: String {
        switch self {
        case .account: return "account"
        case .sidebar(let page): return "sidebar-\(page.rawValue)"
        }
    }
}

private enum InspireSidebarPage: String, Identifiable {
    case membership
    case inspiration
    case customerService
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .membership: return "会员中心"
        case .inspiration: return "灵感值中心"
        case .customerService: return "客服中心"
        case .about: return "关于我们"
        }
    }

    var icon: String {
        switch self {
        case .membership: return "diamond.fill"
        case .inspiration: return "flame.fill"
        case .customerService: return "headphones"
        case .about: return "info.circle.fill"
        }
    }
}

private struct InspireSidebarView: View {
    let isLoggedIn: Bool
    let phone: String
    let onLogin: () -> Void
    let onSelect: (InspireSidebarPage) -> Void
    let onLogout: () -> Void

    var body: some View {
        ZStack {
            Color(red: 0.11, green: 0.13, blue: 0.15).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    accountHeader
                    membershipCard
                    menuCard

                    if isLoggedIn {
                        Button(action: onLogout) {
                            Text("退出登录")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(Color(red: 1, green: 0.31, blue: 0.22))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 18)
                                .frame(height: 64)
                                .background(cardColor)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 26)
                .padding(.horizontal, 18)
                .padding(.bottom, 36)
            }
        }
    }

    private var accountHeader: some View {
        Button(action: onLogin) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.07))
                        .frame(width: 58, height: 58)
                    Image(systemName: isLoggedIn ? "person.crop.circle.fill" : "person.fill")
                        .font(.system(size: isLoggedIn ? 54 : 25))
                        .foregroundColor(isLoggedIn ? .white.opacity(0.82) : .white.opacity(0.28))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(isLoggedIn ? maskedPhone : "点击登录")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(isLoggedIn ? "账号已登录" : "登录后同步会员与灵感值")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.38))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.28))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var membershipCard: some View {
        Button { onSelect(.membership) } label: {
            HStack(spacing: 13) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 24, weight: .bold))
                    Image(systemName: "sparkle")
                        .font(.system(size: 10, weight: .bold))
                        .offset(x: 7, y: -6)
                }
                .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 6) {
                    Text("即刻成为灵感星球会员")
                        .font(.system(size: 17, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Text("解锁更多数字人能力与专属权益")
                        .font(.system(size: 13))
                        .opacity(0.68)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundColor(Color(red: 0.12, green: 0.10, blue: 0.08))
            .padding(.horizontal, 18)
            .frame(height: 92)
            .background(
                LinearGradient(
                    colors: [Color(red: 1.0, green: 0.91, blue: 0.70), Color(red: 0.98, green: 0.84, blue: 0.59)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var menuCard: some View {
        VStack(spacing: 0) {
            row(title: "灵感值中心", icon: "flame.fill", tint: Color(red: 0.36, green: 1, blue: 0.25), trailing: isLoggedIn ? "216.00" : "--") {
                onSelect(.inspiration)
            }
            Divider().overlay(Color.white.opacity(0.055)).padding(.leading, 18)
            row(title: "客服中心", icon: "headphones", tint: .white.opacity(0.72)) {
                onSelect(.customerService)
            }
            Divider().overlay(Color.white.opacity(0.055)).padding(.leading, 18)
            row(title: "关于我们", icon: "info.circle", tint: .white.opacity(0.72)) {
                onSelect(.about)
            }
        }
        .background(cardColor)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func row(
        title: String,
        icon: String,
        tint: Color,
        trailing: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(tint)
                    .frame(width: 22)
                Text(title)
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.88))
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(tint)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.22))
            }
            .padding(.horizontal, 18)
            .frame(height: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var cardColor: Color {
        Color(red: 0.075, green: 0.09, blue: 0.10)
    }

    private var maskedPhone: String {
        guard phone.count >= 7 else { return phone }
        return String(phone.prefix(3)) + " **** " + String(phone.suffix(4))
    }
}

private struct InspireLoginView: View {
    var body: some View {
        InspireAccountView()
    }
}

private struct InspireAccountView: View {
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @AppStorage("inspire.user.isLoggedIn") private var isLoggedIn = false
    @AppStorage("inspire.user.phone") private var savedPhone = ""
    @State private var phone = ""
    @State private var code = ""
    @State private var password = ""
    @State private var isCodeMode = true
    @State private var countdown = 0
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var timer: AnyCancellable?
    @State private var showSetPassword = false
    @State private var showDeleteAccount = false

    var body: some View {
        Group {
            if isLoggedIn && !savedPhone.isEmpty {
                accountContent
            } else {
                loginContent
            }
        }
        .sheet(isPresented: $showSetPassword) {
            InspireSetPasswordView(phone: savedPhone)
                .preferredColorScheme(.light)
        }
        .sheet(isPresented: $showDeleteAccount) {
            InspireDeleteAccountView(phone: savedPhone) {
                close()
            }
            .preferredColorScheme(.light)
        }
        .onDisappear { timer?.cancel() }
        .edgeSwipeBack(perform: close)
    }

    private var loginContent: some View {
        NavigationView {
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [inspirePurple, Color(red: 0.61, green: 0.48, blue: 1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 64, height: 64)
                        Text("✦")
                            .font(.system(size: 28))
                            .foregroundColor(.white)
                    }
                    .padding(.top, 32)
                    Text("登录账号")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(inspireText)
                    Text(isCodeMode ? "手机验证码快速登录" : "手机号密码登录")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
                .padding(.bottom, 32)

                VStack(spacing: 16) {
                    labeledField("手机号") {
                        HStack {
                            Text("+86").font(.system(size: 15, weight: .medium)).foregroundColor(inspirePurple)
                            Divider().frame(height: 20)
                            TextField("请输入手机号", text: Binding(get: { phone }, set: { phone = String($0.filter { $0.isNumber }.prefix(11)) }))
                                .keyboardType(.numberPad)
                                .font(.system(size: 15))
                                .foregroundColor(inspireText)
                        }
                    }

                    if isCodeMode {
                        labeledField("验证码") {
                            HStack {
                                TextField("请输入6位验证码", text: Binding(get: { code }, set: { code = String($0.filter { $0.isNumber }.prefix(6)) }))
                                    .keyboardType(.numberPad)
                                    .font(.system(size: 15))
                                    .foregroundColor(inspireText)
                                Divider().frame(height: 20)
                                Button(countdown > 0 ? "\(countdown)s" : "获取验证码", action: sendCode)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(canSendCode ? inspirePurple : .gray)
                                    .frame(width: 72)
                                    .disabled(!canSendCode)
                            }
                        }
                    } else {
                        labeledField("密码") {
                            SecureField("请输入密码（6位以上）", text: $password)
                                .font(.system(size: 15))
                                .foregroundColor(inspireText)
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage).font(.system(size: 13)).foregroundColor(.red).multilineTextAlignment(.center)
                    }

                    Button(action: login) {
                        ZStack {
                            if isLoading { ProgressView().tint(.white) }
                            else { Text("登录").font(.system(size: 16, weight: .semibold)).foregroundColor(.white) }
                        }
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(canLogin ? inspirePurple : Color.gray.opacity(0.4))
                        .cornerRadius(14)
                    }
                    .disabled(!canLogin)
                    .padding(.top, 8)

                    Button(isCodeMode ? "使用密码登录" : "使用验证码登录") {
                        isCodeMode.toggle()
                        errorMessage = nil
                    }
                    .font(.system(size: 13))
                    .foregroundColor(inspirePurple)
                }
                .padding(.horizontal, 28)

                Spacer()
                Text("登录即代表您同意《用户协议》和《隐私政策》")
                    .font(.system(size: 12)).foregroundColor(.gray).padding(.bottom, 24)
            }
            .background(Color.white.ignoresSafeArea())
            .navigationBarTitle("", displayMode: .inline)
            .navigationBarItems(leading: navigationBackButton(action: close))
        }
        .navigationViewStyle(.stack)
    }

    private var accountContent: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.28).ignoresSafeArea().onTapGesture { close() }
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        Button(action: close) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(inspireText)
                                .frame(width: 34, height: 34)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("账号管理").font(.system(size: 22, weight: .bold)).foregroundColor(inspireText)
                            Text("管理当前登录账号").font(.system(size: 13)).foregroundColor(.gray)
                        }
                        Spacer()
                    }

                    HStack(spacing: 14) {
                        ZStack {
                            LinearGradient(colors: [inspirePurple, Color(red: 0.57, green: 0.47, blue: 1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                .frame(width: 52, height: 52).clipShape(Circle())
                            Image(systemName: "person.fill").font(.system(size: 21, weight: .semibold)).foregroundColor(.white)
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            Text("已登录").font(.system(size: 12, weight: .medium)).foregroundColor(Color(red: 0.09, green: 0.63, blue: 0.42))
                            Text(maskedPhone).font(.system(size: 16, weight: .semibold)).foregroundColor(inspireText)
                        }
                        Spacer()
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 20)).foregroundColor(Color(red: 0.09, green: 0.63, blue: 0.42))
                    }
                    .padding(.horizontal, 16).frame(height: 82)
                    .background(Color(red: 0.97, green: 0.96, blue: 1)).cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(red: 0.91, green: 0.89, blue: 1), lineWidth: 1))
                    .padding(.top, 26)

                    Spacer(minLength: 22)
                    accountButton("设置密码", foreground: .white, background: LinearGradient(colors: [Color(red: 0.09, green: 0.10, blue: 0.14), Color(red: 0.21, green: 0.25, blue: 0.35)], startPoint: .leading, endPoint: .trailing)) { showSetPassword = true }
                    accountButton("退出登录", foreground: Color(red: 0.76, green: 0.25, blue: 0.05), background: LinearGradient(colors: [Color(red: 0.94, green: 0.92, blue: 0.89)], startPoint: .leading, endPoint: .trailing)) { InspireAccountSession.logout(); close() }
                    accountButton("注销账号", foreground: Color(red: 0.90, green: 0.28, blue: 0.30), background: LinearGradient(colors: [Color(red: 1, green: 0.95, blue: 0.95)], startPoint: .leading, endPoint: .trailing)) { showDeleteAccount = true }
                }
                .padding(28)
                .frame(width: min(proxy.size.width - 20, 520), height: min(max(proxy.size.height * 0.68, 490), 560))
                .background(Color.white).cornerRadius(14)
                .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
            }
        }
    }

    private func labeledField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13, weight: .medium)).foregroundColor(.gray)
            content().padding(.horizontal, 14).frame(height: 48)
                .background(Color(red: 0.97, green: 0.95, blue: 1)).cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(inspirePurple.opacity(0.2), lineWidth: 1))
        }
    }

    private func accountButton(_ title: String, foreground: Color, background: LinearGradient, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 15, weight: .bold)).foregroundColor(foreground)
                .frame(maxWidth: .infinity, minHeight: 46).background(background).cornerRadius(12)
        }.buttonStyle(.plain).padding(.top, 10)
    }

    private var canSendCode: Bool { phone.count == 11 && countdown == 0 && !isLoading }
    private var canLogin: Bool { !isLoading && phone.count == 11 && (isCodeMode ? code.count == 6 : password.count >= 6) }
    private var maskedPhone: String { savedPhone.count >= 7 ? String(savedPhone.prefix(3)) + " **** " + String(savedPhone.suffix(4)) : savedPhone }
    private var inspirePurple: Color { Color(red: 0.40, green: 0.31, blue: 0.96) }
    private var inspireText: Color { Color(red: 0.10, green: 0.10, blue: 0.18) }

    private func sendCode() {
        guard canSendCode else { return }
        isLoading = true; errorMessage = nil
        Task {
            do {
                try await InspireAuthService.shared.sendCode(phone: phone)
                await MainActor.run { isLoading = false; startCountdown() }
            } catch { await MainActor.run { isLoading = false; errorMessage = error.localizedDescription } }
        }
    }

    private func login() {
        guard canLogin else { return }
        isLoading = true; errorMessage = nil
        Task {
            do {
                let result: InspireAuthService.LoginResult
                if isCodeMode {
                    result = try await InspireAuthService.shared.loginByCode(phone: phone, code: code)
                } else {
                    result = try await InspireAuthService.shared.loginByPassword(phone: phone, password: password)
                }
                await MainActor.run { InspireAccountSession.login(phone: result.phone, token: result.token); isLoading = false; close() }
            } catch { await MainActor.run { isLoading = false; errorMessage = error.localizedDescription } }
        }
    }

    private func startCountdown() {
        countdown = 60; timer?.cancel()
        timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { _ in
            if countdown > 0 { countdown -= 1 } else { timer?.cancel() }
        }
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }

    private func navigationBackButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(inspireText)
        }
    }
}

private struct InspireSetPasswordView: View {
    let phone: String
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var password = ""
    @State private var countdown = 0
    @State private var isSending = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showSuccess = false
    @State private var timer: AnyCancellable?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("设置密码").font(.system(size: 24, weight: .bold)).foregroundColor(Color(red: 0.10, green: 0.10, blue: 0.18))
                        Text("验证手机号 \(maskedPhone) 后修改密码").font(.system(size: 13)).foregroundColor(.secondary)
                    }.padding(.top, 24)
                    codeField
                    VStack(alignment: .leading, spacing: 7) {
                        Text("新密码").font(.system(size: 13, weight: .medium)).foregroundColor(.secondary)
                        SecureField("请输入至少6位新密码", text: $password)
                            .padding(.horizontal, 14).frame(height: 50).background(fieldColor).cornerRadius(12)
                    }
                    if let errorMessage { Text(errorMessage).font(.system(size: 13)).foregroundColor(.red) }
                    Button(action: submit) {
                        ZStack {
                            if isSubmitting { ProgressView().tint(.white) }
                            else { Text("确认修改").font(.system(size: 16, weight: .semibold)).foregroundColor(.white) }
                        }.frame(maxWidth: .infinity, minHeight: 50).background(canSubmit ? purple : Color.gray.opacity(0.4)).cornerRadius(14)
                    }.disabled(!canSubmit)
                }.padding(.horizontal, 24)
            }
            .background(Color.white)
            .navigationBarTitle("修改密码", displayMode: .inline)
            .navigationBarItems(leading: Button(action: { dismiss() }) {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold))
            })
        }
        .navigationViewStyle(.stack)
        .alert("修改成功", isPresented: $showSuccess) {
            Button("完成") { dismiss() }
        } message: { Text("现在可以使用新密码登录。") }
        .onDisappear { timer?.cancel() }
        .edgeSwipeBack { dismiss() }
    }

    private var codeField: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("验证码").font(.system(size: 13, weight: .medium)).foregroundColor(.secondary)
            HStack {
                TextField("请输入6位验证码", text: Binding(get: { code }, set: { code = String($0.filter { $0.isNumber }.prefix(6)) })).keyboardType(.numberPad)
                Button(countdown > 0 ? "\(countdown)s" : (isSending ? "发送中…" : "获取验证码"), action: sendCode)
                    .font(.system(size: 13, weight: .medium)).foregroundColor(canSend ? purple : .gray).frame(width: 82).disabled(!canSend)
            }.padding(.horizontal, 14).frame(height: 50).background(fieldColor).cornerRadius(12)
        }
    }

    private var maskedPhone: String { phone.count >= 7 ? String(phone.prefix(3)) + "****" + String(phone.suffix(4)) : phone }
    private var canSend: Bool { phone.count == 11 && countdown == 0 && !isSending && !isSubmitting }
    private var canSubmit: Bool { code.count == 6 && password.count >= 6 && !isSubmitting }
    private var purple: Color { Color(red: 0.40, green: 0.31, blue: 0.96) }
    private var fieldColor: Color { Color(red: 0.97, green: 0.95, blue: 1) }
    private func sendCode() { authCodeAction(isDelete: false) }
    private func authCodeAction(isDelete: Bool) {
        guard canSend else { return }; isSending = true; errorMessage = nil
        Task { do { try await InspireAuthService.shared.sendCode(phone: phone); await MainActor.run { isSending = false; startTimer() } }
            catch { await MainActor.run { isSending = false; errorMessage = error.localizedDescription } } }
    }
    private func submit() {
        guard canSubmit else { return }; isSubmitting = true; errorMessage = nil
        Task { do { try await InspireAuthService.shared.setPassword(phone: phone, code: code, password: password); await MainActor.run { isSubmitting = false; showSuccess = true } }
            catch { await MainActor.run { isSubmitting = false; errorMessage = error.localizedDescription } } }
    }
    private func startTimer() {
        countdown = 120; timer?.cancel()
        timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { _ in if countdown > 0 { countdown -= 1 } else { timer?.cancel() } }
    }
}

private struct InspireDeleteAccountView: View {
    let phone: String
    let onDeleted: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var countdown = 0
    @State private var isSending = false
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @State private var showConfirmation = false
    @State private var timer: AnyCancellable?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("注销账号").font(.system(size: 24, weight: .bold))
                        Text("验证手机号 \(maskedPhone) 后将永久注销账号").font(.system(size: 13)).foregroundColor(.secondary)
                    }.padding(.top, 24)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("注销账号前请确认：").font(.system(size: 14, weight: .semibold))
                        Text("• 账号信息及相关数据将被永久删除，无法恢复。\n• 注销后该手机号可重新注册新账号。")
                            .font(.system(size: 13)).foregroundColor(Color(red: 0.46, green: 0.35, blue: 0.23)).lineSpacing(4)
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Color(red: 1, green: 0.97, blue: 0.93)).cornerRadius(12)
                    VStack(alignment: .leading, spacing: 7) {
                        Text("短信验证码").font(.system(size: 13, weight: .medium)).foregroundColor(.secondary)
                        HStack {
                            TextField("请输入6位验证码", text: Binding(get: { code }, set: { code = String($0.filter { $0.isNumber }.prefix(6)) })).keyboardType(.numberPad)
                            Button(countdown > 0 ? "\(countdown)s" : (isSending ? "发送中…" : "获取验证码"), action: sendCode)
                                .font(.system(size: 13, weight: .medium)).foregroundColor(canSend ? purple : .gray).frame(width: 82).disabled(!canSend)
                        }.padding(.horizontal, 14).frame(height: 50).background(Color(red: 0.97, green: 0.96, blue: 0.98)).cornerRadius(12)
                    }
                    if let errorMessage { Text(errorMessage).font(.system(size: 13)).foregroundColor(.red) }
                    Button(action: { showConfirmation = true }) {
                        ZStack {
                            if isDeleting { ProgressView().tint(.white) }
                            else { Text("注销账号").font(.system(size: 16, weight: .semibold)).foregroundColor(.white) }
                        }.frame(maxWidth: .infinity, minHeight: 50).background(canDelete ? Color(red: 0.90, green: 0.28, blue: 0.30) : Color.gray.opacity(0.4)).cornerRadius(14)
                    }.disabled(!canDelete)
                }.padding(.horizontal, 24)
            }
            .background(Color.white)
            .navigationBarTitle("注销账号", displayMode: .inline)
            .navigationBarItems(leading: Button(action: { dismiss() }) {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold))
            })
        }
        .navigationViewStyle(.stack)
        .alert("确认注销账号？", isPresented: $showConfirmation) {
            Button("确认注销", role: .destructive, action: deleteAccount)
            Button("取消", role: .cancel) {}
        } message: { Text("注销后账号及数据将被永久删除，且无法恢复。") }
        .onDisappear { timer?.cancel() }
        .edgeSwipeBack { dismiss() }
    }
    private var maskedPhone: String { phone.count >= 7 ? String(phone.prefix(3)) + "****" + String(phone.suffix(4)) : phone }
    private var canSend: Bool { phone.count == 11 && countdown == 0 && !isSending && !isDeleting }
    private var canDelete: Bool { code.count == 6 && !isDeleting }
    private var purple: Color { Color(red: 0.40, green: 0.31, blue: 0.96) }
    private func sendCode() {
        guard canSend else { return }; isSending = true; errorMessage = nil
        Task { do { try await InspireAuthService.shared.sendCode(phone: phone); await MainActor.run { isSending = false; startTimer() } }
            catch { await MainActor.run { isSending = false; errorMessage = error.localizedDescription } } }
    }
    private func deleteAccount() {
        guard canDelete else { return }; isDeleting = true; errorMessage = nil
        Task { do { try await InspireAuthService.shared.deleteAccount(phone: phone, code: code); await MainActor.run { isDeleting = false; InspireAccountSession.logout(); dismiss(); onDeleted() } }
            catch { await MainActor.run { isDeleting = false; errorMessage = error.localizedDescription } } }
    }
    private func startTimer() {
        countdown = 120; timer?.cancel()
        timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { _ in if countdown > 0 { countdown -= 1 } else { timer?.cancel() } }
    }
}

enum InspireAccountSession {
    static func login(phone: String, token: String) {
        UserDefaults.standard.set(true, forKey: "inspire.user.isLoggedIn")
        UserDefaults.standard.set(phone, forKey: "inspire.user.phone")
        try? InspireKeychainStore().set(token, account: "inspire.user.accessToken")
    }
    static func logout() {
        UserDefaults.standard.set(false, forKey: "inspire.user.isLoggedIn")
        UserDefaults.standard.removeObject(forKey: "inspire.user.phone")
        InspireKeychainStore().delete(account: "inspire.user.accessToken")
    }
    static func accessToken() -> String? {
        InspireKeychainStore().get(account: "inspire.user.accessToken")
    }
}

final class InspireKeychainStore {
    private var service: String { Bundle.main.bundleIdentifier ?? "cn.cjym.inspireplanet" }
    func set(_ value: String, account: String) throws {
        delete(account: account)
        guard !value.isEmpty else { return }
        let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecValueData as String: Data(value.utf8)]
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
    func delete(account: String) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] as CFDictionary)
    }
    func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

private final class InspireAuthService {
    static let shared = InspireAuthService()
    struct LoginResult { let phone: String; let token: String }
    private let baseURL = "https://www.cjym123.cn"
    private func post(_ path: String, body: [String: Any]) async throws -> [String: Any] {
        guard let url = URL(string: baseURL + path) else { throw URLError(.badURL) }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw NSError(domain: "InspireAuth", code: 0, userInfo: [NSLocalizedDescriptionKey: "网络请求失败，请稍后重试"]) }
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let success = json["code"] as? Int == 0 || json["code"] as? String == "0"
        guard success else { throw NSError(domain: "InspireAuth", code: 0, userInfo: [NSLocalizedDescriptionKey: json["msg"] as? String ?? "请求失败"]) }
        return json
    }
    func sendCode(phone: String) async throws { _ = try await post("/im/bot/login-code", body: ["phone": phone]) }
    func loginByCode(phone: String, code: String) async throws -> LoginResult { try await login("/im/bot/login-by-code", phone: phone, credential: ["code": code]) }
    func loginByPassword(phone: String, password: String) async throws -> LoginResult { try await login("/im/bot/login-by-password", phone: phone, credential: ["password": password]) }
    private func login(_ path: String, phone: String, credential: [String: Any]) async throws -> LoginResult {
        let device = await MainActor.run { (UIDevice.current.model, UIDevice.current.systemVersion) }
        var body = credential; body["phone"] = phone; body["deviceModel"] = device.0; body["osVersion"] = device.1; body["appName"] = "InspirePlanet"
        let json = try await post(path, body: body); let data = json["data"] as? [String: Any] ?? [:]
        return LoginResult(phone: data["phone"] as? String ?? phone, token: data["accessToken"] as? String ?? data["token"] as? String ?? "")
    }
    func setPassword(phone: String, code: String, password: String) async throws { _ = try await post("/im/bot/set-password", body: ["phone": phone, "code": code, "password": password]) }
    func deleteAccount(phone: String, code: String) async throws { _ = try await post("/im/bot/remove_account", body: ["phone": phone, "code": code]) }
}

private struct InspireSidebarDetailView: View {
    let page: InspireSidebarPage
    let isLoggedIn: Bool
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Group {
                if page == .about {
                    aboutContent
                } else {
                    VStack(spacing: 18) {
                        Image(systemName: page.icon)
                            .font(.system(size: 54))
                            .foregroundStyle(page == .membership ? Color.yellow : Color.indigo)
                        Text(page.title)
                            .font(.title2.bold())
                        Text(description)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(5)
                        Spacer()
                    }
                    .padding(28)
                }
            }
            .navigationTitle(page.title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(leading: Button(action: close) {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold))
            })
        }
        .navigationViewStyle(.stack)
        .edgeSwipeBack(perform: close)
    }

    private var description: String {
        switch page {
        case .membership:
            return isLoggedIn ? "会员权益与订阅服务正在准备中。" : "请先登录账户，再查看和开通会员权益。"
        case .inspiration:
            return isLoggedIn ? "当前灵感值：216.00\n后续可在这里查看获取与使用记录。" : "登录后可查看灵感值余额与明细。"
        case .customerService:
            return "如需帮助，请通过应用商店中的开发者联系方式联系我们。"
        case .about:
            return "灵感星球\n与 AI 数字人自然对话，随时记录和激发你的灵感。"
        }
    }

    private var aboutContent: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(LinearGradient(colors: [Color.indigo, Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 82, height: 82)
                        Image(systemName: "sparkles")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    Text("灵感星球")
                        .font(.system(size: 24, weight: .bold))
                    Text("版本 \(appVersion)")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 12)

                Text("灵感星球是一款 AI 数字人灵感助手。你可以通过文字或语音与数字人自然交流，在陪伴、创作和思考中随时发现并记录灵感。")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(spacing: 0) {
                    aboutRow(icon: "doc.text", title: "用户协议")
                    Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 52)
                    aboutRow(icon: "hand.raised", title: "隐私政策")
                    Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 52)
                    aboutRow(icon: "headphones", title: "联系客服")
                }
                .background(Color.white.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(spacing: 5) {
                    Text("灵感星球 · 让每一次对话都有灵感")
                    Text("Copyright © 2026 All Rights Reserved")
                }
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.top, 8)
            }
            .padding(22)
        }
        .background(Color(red: 0.08, green: 0.09, blue: 0.11).ignoresSafeArea())
    }

    private func aboutRow(icon: String, title: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.indigo)
                .frame(width: 26)
            Text(title).font(.system(size: 15))
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 15)
        .frame(height: 56)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }
}

private extension View {
    /// 自定义二级页面没有 UINavigationController 的交互返回能力，统一补充
    /// 左侧边缘右滑手势；严格限制起点与方向，避免抢占 ScrollView 等操作。
    func edgeSwipeBack(perform action: @escaping () -> Void) -> some View {
        simultaneousGesture(
            DragGesture(minimumDistance: 12, coordinateSpace: .global)
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = abs(value.translation.height)
                    guard value.startLocation.x <= 28,
                          horizontal >= 80,
                          horizontal > vertical * 1.25 else { return }
                    action()
                }
        )
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
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.56))
                Text(attributedText)
                    .font(.system(size: 16))
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
