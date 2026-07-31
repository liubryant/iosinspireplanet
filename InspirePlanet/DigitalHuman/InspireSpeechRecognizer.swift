import Foundation
import AVFoundation
import Speech

final class InspireSpeechRecognizer {
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private var activeSessionID: UUID?

    var isAvailable: Bool {
        recognizer?.isAvailable == true
    }

    func requestAuthorization(completion: @escaping (Bool, String?) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            switch status {
            case .authorized:
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        completion(granted, granted ? nil : "麦克风权限已被拒绝，请在系统设置中开启")
                    }
                }
            case .denied:
                DispatchQueue.main.async {
                    completion(false, "语音识别权限已被拒绝，请在系统设置中开启")
                }
            case .restricted:
                DispatchQueue.main.async {
                    completion(false, "当前设备不支持语音识别")
                }
            case .notDetermined:
                DispatchQueue.main.async {
                    completion(false, "语音识别权限尚未授权")
                }
            @unknown default:
                DispatchQueue.main.async {
                    completion(false, "语音识别授权状态未知")
                }
            }
        }
    }

    func start(
        onPartialResult: @escaping (String) -> Void,
        onError: @escaping (String) -> Void
    ) {
        stop()
        let sessionID = UUID()
        activeSessionID = sessionID

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            activeSessionID = nil
            onError("无法启动麦克风：\(error.localizedDescription)")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        guard let recognizer = recognizer, recognizer.isAvailable else {
            activeSessionID = nil
            onError("语音识别服务当前不可用")
            return
        }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            activeSessionID = nil
            inputNode.removeTap(onBus: 0)
            onError("麦克风启动失败：\(error.localizedDescription)")
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self, self.activeSessionID == sessionID else {
                return
            }
            if let result = result {
                onPartialResult(result.bestTranscription.formattedString)
            }
            if let error = error {
                guard !self.shouldIgnoreRecognitionError(error) else {
                    return
                }
                onError(error.localizedDescription)
            }
        }
    }

    func stop() {
        activeSessionID = nil
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func shouldIgnoreRecognitionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return true
        }
        let message = nsError.localizedDescription.lowercased()
        return message.contains("cancel") || message.contains("cancelled")
    }
}
