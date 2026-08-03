import Foundation
import ObjectiveC
import UIKit

enum DuixDigitalHumanState: Equatable {
    case idle
    case loading
    case ready
    case unavailable(String)
    case failed(String)

    var message: String {
        switch self {
        case .idle:
            return "数字人待初始化"
        case .loading:
            return "数字人加载中"
        case .ready:
            return "数字人已接入"
        case .unavailable(let message), .failed(let message):
            return message
        }
    }

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

private enum DuixRuntimeResult {
    case success
    case failure(String)
}

final class LilyDigitalHumanController: ObservableObject {
    static let shared = LilyDigitalHumanController()

    @Published private(set) var state: DuixDigitalHumanState = .idle
    @Published private(set) var persona: DigitalHumanPersona = {
        let saved = UserDefaults.standard.string(forKey: "inspireplanet.selected-persona")
        return DigitalHumanPersona(rawValue: saved ?? "") ?? .leo
    }()

    private let runtime = DuixDigitalHumanRuntimeBridge()
    private var initializedViewID: ObjectIdentifier?
    private var isInitializing = false
    private var didStartRunning = false
    private var speechMotionTimer: Timer?
    private var currentSpeechPCMByteCount = 0
    private var didKickSpeechPlayback = false
    private var currentPlaybackFailed: (() -> Void)?
    private weak var latestHostView: UIView?
    private var isPageVisible = false
    private var initializationStartedAt: TimeInterval = 0
    private var speechStartedAt: TimeInterval = 0

    var canDriveSpeech: Bool {
        state.isReady && runtime.isReady
    }

    func attach(to view: UIView) {
        latestHostView = view
        let viewID = ObjectIdentifier(view)

        guard persona.supportsLiveDigitalHuman else {
            initializedViewID = nil
            isInitializing = false
            didStartRunning = false
            updateState(.unavailable("\(persona.displayName) 使用静态形象"))
            return
        }

        if initializedViewID == viewID {
            // The same persistent host is already initialized. SwiftUI may update the
            // representable frequently; do not rebind/restart Duix on those updates.
            return
        }
        #if DEBUG
        print("duix attach host=\(viewID) state=\(state.message) bounds=\(view.bounds)")
        #endif
        if runtime.isReady {
            initializedViewID = viewID
            reattachReadyRuntime(to: view, shouldStartRunning: didStartRunning)
            return
        }
        if isInitializing {
            return
        }

        guard let paths = LilyResourceCatalog.paths(for: persona) else {
            updateState(.unavailable("缺少 \(persona.displayName) 或基础模型资源"))
            return
        }

        guard runtime.isSDKAvailable else {
            updateState(.unavailable("未检测到 Duix SDK，当前显示静态形象"))
            return
        }

        initializedViewID = viewID
        isInitializing = true
        initializationStartedAt = ProcessInfo.processInfo.systemUptime
        didStartRunning = false
        updateState(.loading)
        runtime.initialize(basePath: paths.baseModelPath, digitalPath: paths.digitalModelPath, showView: view) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success:
                    self.runtime.setDiagnosticsHandlers()
                    self.runtime.start { [weak self] startResult in
                        DispatchQueue.main.async {
                            guard let self = self else { return }
                            self.isInitializing = false
                            switch startResult {
                            case .success:
                                self.runtime.setRecordEnabled(false)
                                if let view = self.latestHostView {
                                    let latestViewID = ObjectIdentifier(view)
                                    if self.initializedViewID == latestViewID {
                                        // initBaseModel already owns this host; only start the
                                        // render loop once, without another show/rebind cycle.
                                        self.runtime.startRunning()
                                        #if DEBUG
                                        print("duix initial_host_started host=\(latestViewID)")
                                        #endif
                                    } else {
                                        self.initializedViewID = latestViewID
                                        self.reattachReadyRuntime(to: view, shouldStartRunning: true)
                                    }
                                } else {
                                    self.runtime.startRunning()
                                }
                                self.didStartRunning = true
                                self.updateState(.ready)
                                self.startIdleMotion()
                                #if DEBUG
                                let elapsed = ProcessInfo.processInfo.systemUptime - self.initializationStartedAt
                                print("duix init_ready elapsed=\(String(format: "%.3f", elapsed))s visible=\(self.isPageVisible)")
                                #endif
                                #if DEBUG
                                print("Duix ready auth=\(self.runtime.authStatus())")
                                #endif
                            case .failure(let message):
                                self.updateState(.failed(message))
                            }
                        }
                    }
                case .failure(let message):
                    self.isInitializing = false
                    self.updateState(.failed(message))
                }
            }
        }
    }

    private func reattachReadyRuntime(to view: UIView, shouldStartRunning: Bool) {
        runtime.show(in: view)
        if shouldStartRunning {
            runtime.startRunning()
        }
        #if DEBUG
        print("duix host_bound host=\(ObjectIdentifier(view)) startRunning=\(shouldStartRunning)")
        #endif
    }

    func startSpeechSession(onPlaybackEnd: @escaping () -> Void, onPlaybackFailed: @escaping () -> Void) -> Bool {
        guard canDriveSpeech else { return false }
        currentPlaybackFailed = onPlaybackFailed
        if !didStartRunning {
            runtime.setRecordEnabled(false)
            runtime.startRunning()
            didStartRunning = true
        }
        currentSpeechPCMByteCount = 0
        speechStartedAt = ProcessInfo.processInfo.systemUptime
        didKickSpeechPlayback = false
        let authStatus = runtime.authStatus()
        #if DEBUG
        print("Duix start speech auth=\(authStatus)")
        #endif
        guard authStatus == 1 else {
            updateState(.failed("Duix 授权或播放状态未就绪：\(authStatus)"))
            currentPlaybackFailed = nil
            return false
        }
        runtime.setPlaybackEndHandler(onPlaybackEnd)
        runtime.setRenderReportHandler()
        runtime.newSession()
        runtime.setVolume(1.0)
        runtime.setMuted(false)
        runtime.startPlaying()
        if runtime.startMotion() == 0 {
            _ = runtime.randomMotion()
        }
        startSpeechMotionTimer()
        return true
    }

    func appendPCM(_ data: Data) {
        guard canDriveSpeech, !data.isEmpty else { return }
        currentSpeechPCMByteCount += data.count
        #if DEBUG
        if currentSpeechPCMByteCount == data.count || currentSpeechPCMByteCount % 32_000 < data.count {
            print("Duix PCM pushed totalBytes=\(currentSpeechPCMByteCount)")
        }
        #endif
        runtime.appendPCM(data)
        if !didKickSpeechPlayback, currentSpeechPCMByteCount >= 32_000 {
            didKickSpeechPlayback = true
            runtime.setVolume(1.0)
            runtime.setMuted(false)
            runtime.startPlaying()
            #if DEBUG
            print("Duix playback kicked after PCM cache")
            #endif
        }
    }

    func finishPushingSpeechAudio() {
        guard canDriveSpeech else { return }
        #if DEBUG
        print("Duix finish pushing PCM totalBytes=\(currentSpeechPCMByteCount)")
        #endif
        runtime.finishSession()
    }

    func finishSpeechSession() {
        guard runtime.isReady else { return }
        stopSpeechMotionTimer()
        runtime.setPlaybackEndHandler(nil)
        currentPlaybackFailed = nil
        runtime.clearAudioBuffer()
        _ = runtime.stopMotion(quickly: true)
        #if DEBUG
        let elapsed = ProcessInfo.processInfo.systemUptime - speechStartedAt
        print("duix speech_end callback elapsed=\(String(format: "%.3f", elapsed))s")
        #endif
        // Match Android: session cleanup runs off the UI thread so the final rendered
        // frame is not blocked by the SDK's synchronous continueSession call.
        let runtime = runtime
        DispatchQueue.global(qos: .userInitiated).async {
            let started = ProcessInfo.processInfo.systemUptime
            runtime.continueSession()
            #if DEBUG
            let elapsed = ProcessInfo.processInfo.systemUptime - started
            print("duix speech_cleanup continueSession elapsed=\(String(format: "%.3f", elapsed))s")
            #endif
        }
    }

    func stopSpeechSession() {
        guard runtime.isReady else { return }
        stopSpeechMotionTimer()
        runtime.setPlaybackEndHandler(nil)
        currentPlaybackFailed = nil
        runtime.continueSession()
        runtime.clearAudioBuffer()
        _ = runtime.stopMotion(quickly: true)
    }

    func stopRenderer() {
        stopSpeechMotionTimer()
        runtime.stop()
        state = .idle
        initializedViewID = nil
        isInitializing = false
        didStartRunning = false
    }

    func switchPersona(to newPersona: DigitalHumanPersona) {
        guard persona != newPersona, !isInitializing else { return }
        stopSpeechMotionTimer()
        runtime.setPlaybackEndHandler(nil)
        currentPlaybackFailed = nil
        runtime.clearAudioBuffer()
        _ = runtime.stopMotion(quickly: true)
        runtime.stop()
        initializedViewID = nil
        didStartRunning = false
        persona = newPersona
        UserDefaults.standard.set(newPersona.rawValue, forKey: "inspireplanet.selected-persona")

        guard newPersona.supportsLiveDigitalHuman else {
            updateState(.unavailable("\(newPersona.displayName) 使用静态形象"))
            return
        }

        updateState(.loading)

        guard let hostView = latestHostView else {
            updateState(.idle)
            return
        }
        // Official lifecycle: toStop releases the old digital model, then the
        // same base model is initialized again with the new digitalModel path.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self, weak hostView] in
            guard let self, let hostView else { return }
            self.attach(to: hostView)
        }
    }

    func setPageVisible(_ visible: Bool) {
        isPageVisible = visible
        if visible, state.isReady {
            startIdleMotion()
        }
        #if DEBUG
        print("duix tab_visibility visible=\(visible) ready=\(state.isReady) uptime=\(String(format: "%.3f", ProcessInfo.processInfo.systemUptime))")
        #endif
    }

    /// Keeps Lily's renderer and natural idle motion active as soon as the page appears.
    /// Without this explicit kick, Duix can remain on its first rendered frame until a
    /// later layout or speech session wakes the render loop.
    func activateIdleMotion() {
        guard state.isReady else { return }
        startIdleMotion()
    }

    private func startIdleMotion() {
        guard runtime.isReady else { return }
        runtime.setRecordEnabled(false)
        runtime.startRunning()
        didStartRunning = true
        if runtime.randomMotion() == 0 {
            _ = runtime.startMotion()
        }
    }

    private func startSpeechMotionTimer() {
        stopSpeechMotionTimer()
        speechMotionTimer = Timer.scheduledTimer(withTimeInterval: 1.15, repeats: true) { [weak self] _ in
            guard let self = self, self.canDriveSpeech else { return }
            if self.runtime.randomMotion() == 0 {
                _ = self.runtime.startMotion()
            }
        }
    }

    private func stopSpeechMotionTimer() {
        speechMotionTimer?.invalidate()
        speechMotionTimer = nil
    }

    private func updateState(_ newState: DuixDigitalHumanState) {
        if Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.state = newState
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.state = newState
            }
        }
    }

    private func handlePlaybackFailure() {
        let failure = currentPlaybackFailed
        currentPlaybackFailed = nil
        failure?()
    }
}

private final class DuixDigitalHumanRuntimeBridge {
    private var manager: AnyObject?

    var isSDKAvailable: Bool {
        NSClassFromString("GJLDigitalManager") != nil
    }

    var isReady: Bool {
        manager != nil
    }

    func initialize(basePath: String, digitalPath: String, showView: UIView, completion: @escaping (DuixRuntimeResult) -> Void) {
        DispatchQueue.main.async {
            guard let manager = self.resolveManager() else {
                completion(.failure("未检测到 GJLDigitalManager"))
                return
            }

            self.setValue(0, forKey: "backType", on: manager)
            self.setValue(1, forKey: "pcmType", on: manager)
            self.setValue(false, forKey: "isVoiceProcessingIO", on: manager)
            self.setValue(false, forKey: "isFadeInOut", on: manager)

            let selector = NSSelectorFromString("initBaseModel:digitalModel:showView:")
            guard manager.responds(to: selector), let method = manager.method(for: selector) else {
                completion(.failure("Duix SDK 缺少初始化方法"))
                return
            }

            typealias InitFunction = @convention(c) (AnyObject, Selector, NSString, NSString, UIView) -> Int
            let function = unsafeBitCast(method, to: InitFunction.self)
            let code = function(manager, selector, basePath as NSString, digitalPath as NSString, showView)
            if code == 1 {
                self.manager = manager
                completion(.success)
            } else {
                completion(.failure("Duix 模型初始化失败：\(code)"))
            }
        }
    }

    func start(completion: @escaping (DuixRuntimeResult) -> Void) {
        guard let manager = manager else {
            completion(.failure("Duix 尚未初始化"))
            return
        }

        let selector = NSSelectorFromString("toStart:")
        guard manager.responds(to: selector), let method = manager.method(for: selector) else {
            completion(.failure("Duix SDK 缺少启动方法"))
            return
        }

        typealias StartBlock = @convention(block) (Bool, NSString?) -> Void
        typealias StartFunction = @convention(c) (AnyObject, Selector, StartBlock) -> Void
        let function = unsafeBitCast(method, to: StartFunction.self)
        let block: StartBlock = { isSuccess, errorMessage in
            if isSuccess {
                completion(.success)
            } else {
                completion(.failure(errorMessage as String? ?? "Duix 渲染启动失败"))
            }
        }
        function(manager, selector, block)
    }

    func startRunning() {
        performVoid("toStartRuning")
    }

    func pauseRendering() {
        performVoid("toPause")
    }

    func resumeRendering() {
        performVoid("toPlay")
    }

    func setRecordEnabled(_ isEnabled: Bool) {
        guard let manager = manager else { return }
        let selector = NSSelectorFromString("toEnableRecord:")
        guard manager.responds(to: selector), let method = manager.method(for: selector) else { return }
        typealias RecordFunction = @convention(c) (AnyObject, Selector, Bool) -> Void
        let function = unsafeBitCast(method, to: RecordFunction.self)
        function(manager, selector, isEnabled)
    }

    func stop() {
        performVoid("toStop")
        manager = nil
    }

    func show(in view: UIView) {
        guard let manager = manager else { return }
        let selector = NSSelectorFromString("toShow:")
        guard manager.responds(to: selector), let method = manager.method(for: selector) else { return }
        typealias ShowFunction = @convention(c) (AnyObject, Selector, UIView) -> Void
        let function = unsafeBitCast(method, to: ShowFunction.self)
        function(manager, selector, view)
    }

    func newSession() {
        performVoid("newSession")
    }

    func finishSession() {
        performVoid("finishSession")
    }

    func continueSession() {
        performVoid("continueSession")
    }

    func clearAudioBuffer() {
        performVoid("clearAudioBuffer")
    }

    func startPlaying() {
        performVoid("startPlaying")
    }

    func authStatus() -> Int {
        performInt("isGetAuth")
    }

    func setMuted(_ isMuted: Bool) {
        guard let manager = manager else { return }
        let selector = NSSelectorFromString("toMute:")
        guard manager.responds(to: selector), let method = manager.method(for: selector) else { return }
        typealias MuteFunction = @convention(c) (AnyObject, Selector, Bool) -> Void
        let function = unsafeBitCast(method, to: MuteFunction.self)
        function(manager, selector, isMuted)
    }

    func setVolume(_ volume: Float) {
        guard let manager = manager else { return }
        let selector = NSSelectorFromString("toSetVolume:")
        guard manager.responds(to: selector), let method = manager.method(for: selector) else { return }
        typealias VolumeFunction = @convention(c) (AnyObject, Selector, Float) -> Void
        let function = unsafeBitCast(method, to: VolumeFunction.self)
        function(manager, selector, volume)
    }

    func setPlaybackEndHandler(_ handler: (() -> Void)?) {
        guard let manager = manager else { return }
        if let handler = handler {
            let block: @convention(block) () -> Void = {
                #if DEBUG
                print("Duix audioPlayEnd")
                #endif
                handler()
            }
            manager.setValue(block, forKey: "audioPlayEnd")
        } else {
            manager.setValue(nil, forKey: "audioPlayEnd")
        }
    }

    func setRenderReportHandler() {
        guard let manager = manager else { return }
        var lipReportCount = 0
        let block: @convention(block) (Int32, Bool, Float) -> Void = { resultCode, isLip, useTime in
            #if DEBUG
            if isLip {
                lipReportCount += 1
                if lipReportCount == 1 || lipReportCount % 80 == 0 {
                    print("Duix lip frame result=\(resultCode) count=\(lipReportCount) useTime=\(useTime)")
                }
            }
            #endif
        }
        manager.setValue(block, forKey: "onRenderReportBlock")
    }

    func setDiagnosticsHandlers() {
        guard let manager = manager else { return }

        let playFailed: @convention(block) (Int, NSString?) -> Void = { code, message in
            #if DEBUG
            print("Duix playFailed code=\(code) message=\(message as String? ?? "")")
            #endif
        }
        manager.setValue(playFailed, forKey: "playFailed")

        let pcmReady: @convention(block) () -> Void = {
            #if DEBUG
            print("Duix pcmReady")
            #endif
        }
        manager.setValue(pcmReady, forKey: "pcmReadyBlock")
    }

    func appendPCM(_ data: Data) {
        guard let manager = manager else { return }
        let selector = NSSelectorFromString("toWavPcmData:")
        guard manager.responds(to: selector), let method = manager.method(for: selector) else { return }
        typealias PCMFunction = @convention(c) (AnyObject, Selector, NSData) -> Void
        let function = unsafeBitCast(method, to: PCMFunction.self)
        function(manager, selector, data as NSData)
    }

    func randomMotion() -> Int {
        performInt("toRandomMotion")
    }

    func startMotion() -> Int {
        performInt("toStartMotion")
    }

    func stopMotion(quickly: Bool) -> Int {
        guard let manager = manager else { return 0 }
        let selector = NSSelectorFromString("toSopMotion:")
        guard manager.responds(to: selector), let method = manager.method(for: selector) else { return 0 }
        typealias StopMotionFunction = @convention(c) (AnyObject, Selector, Bool) -> Int
        let function = unsafeBitCast(method, to: StopMotionFunction.self)
        return function(manager, selector, quickly)
    }

    private func resolveManager() -> AnyObject? {
        if let manager = manager {
            return manager
        }
        guard let managerClass = NSClassFromString("GJLDigitalManager") else {
            return nil
        }
        let selector = NSSelectorFromString("manager")
        guard (managerClass as AnyObject).responds(to: selector) else {
            return nil
        }
        return (managerClass as AnyObject).perform(selector)?.takeUnretainedValue()
    }

    private func performVoid(_ selectorName: String) {
        guard let manager = manager else { return }
        let selector = NSSelectorFromString(selectorName)
        guard manager.responds(to: selector) else { return }
        _ = manager.perform(selector)
    }

    private func performInt(_ selectorName: String) -> Int {
        guard let manager = manager else { return 0 }
        let selector = NSSelectorFromString(selectorName)
        guard manager.responds(to: selector), let method = manager.method(for: selector) else { return 0 }
        typealias IntFunction = @convention(c) (AnyObject, Selector) -> Int
        let function = unsafeBitCast(method, to: IntFunction.self)
        return function(manager, selector)
    }

    private func setValue(_ value: Any, forKey key: String, on object: AnyObject) {
        guard object.responds(to: NSSelectorFromString("set\(key.prefix(1).uppercased())\(key.dropFirst()):")) else {
            return
        }
        object.setValue(value, forKey: key)
    }
}
