import AVFoundation
import Foundation

final class InspireSpeechSynthesizer: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private let pcmSynthesizer = AVSpeechSynthesizer()
    private var activeUtterance: AVSpeechUtterance?
    private var onStart: (() -> Void)?
    private var onFinish: (() -> Void)?
    private var onRangeChange: ((NSRange) -> Void)?
    private var activePCMUtterance: AVSpeechUtterance?
    private weak var activeDigitalHuman: LilyDigitalHumanController?
    private var didFinishCurrentSpeech = false
    private var speechGeneration = 0
    private var digitalHumanFinishWorkItem: DispatchWorkItem?
    private var sentenceHighlightWorkItems: [DispatchWorkItem] = []
    private var duixPCMConverter: AVAudioConverter?
    private var duixPCMSourceFormat: AVAudioFormat?
    private let duixPCMTargetFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16_000,
        channels: 1,
        interleaved: true
    )

    override init() {
        super.init()
        synthesizer.delegate = self
        pcmSynthesizer.delegate = self
    }

    func speak(
        _ text: String,
        voice: DigitalHumanVoice = .female,
        digitalHuman: LilyDigitalHumanController? = nil,
        onStart: @escaping () -> Void,
        onFinish: @escaping () -> Void,
        onRangeChange: ((NSRange) -> Void)? = nil
    ) {
        stop(deactivateAudioSession: false)
        self.onStart = onStart
        self.onFinish = onFinish
        self.onRangeChange = onRangeChange
        didFinishCurrentSpeech = false
        speechGeneration &+= 1
        resetDuixPCMConverter()
        let currentGeneration = speechGeneration

        let utterance = makeUtterance(text, voice: voice)
        activeUtterance = utterance

        if let digitalHuman = digitalHuman, digitalHuman.canDriveSpeech {
            activeDigitalHuman = digitalHuman
            try? AVAudioSession.sharedInstance().setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetooth, .duckOthers]
            )
            try? AVAudioSession.sharedInstance().setActive(true)
            let didStartDigitalHuman = digitalHuman.startSpeechSession {
                [weak self] in
                DispatchQueue.main.async {
                    #if DEBUG
                    print("Duix playback end callback received")
                    #endif
                    self?.finishSpeech()
                }
            } onPlaybackFailed: { [weak self] in
                DispatchQueue.main.async {
                    self?.fallbackToSystemSpeech(utterance)
                }
            }
            guard didStartDigitalHuman else {
                activeDigitalHuman = nil
                fallbackToSystemSpeech(utterance)
                return
            }
            self.onStart?()
            driveDigitalHuman(
                with: text,
                voice: voice,
                digitalHuman: digitalHuman,
                generation: currentGeneration
            )
            scheduleDigitalHumanSafetyTimeout(for: text, generation: currentGeneration)
            return
        }

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        synthesizer.speak(utterance)
    }

    func stop(deactivateAudioSession: Bool = true) {
        let digitalHuman = activeDigitalHuman
        speechGeneration &+= 1
        activeUtterance = nil
        onStart = nil
        onFinish = nil
        onRangeChange = nil
        activePCMUtterance = nil
        didFinishCurrentSpeech = true
        activeDigitalHuman = nil
        digitalHumanFinishWorkItem?.cancel()
        digitalHumanFinishWorkItem = nil
        sentenceHighlightWorkItems.forEach { $0.cancel() }
        sentenceHighlightWorkItems.removeAll()
        resetDuixPCMConverter()
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        if pcmSynthesizer.isSpeaking {
            pcmSynthesizer.stopSpeaking(at: .immediate)
        }
        digitalHuman?.stopSpeechSession()
        if deactivateAudioSession {
            deactivateAudioSessionWithoutBlockingUI()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        guard utterance === activeUtterance else { return }
        onStart?()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard utterance === activeUtterance else { return }
        finishSpeech()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        guard utterance === activeUtterance else { return }
        finishSpeech()
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        guard utterance === activeUtterance else { return }
        let completeSentenceRange = sentenceRange(containing: characterRange, in: utterance.speechString)
        DispatchQueue.main.async { [weak self] in self?.onRangeChange?(completeSentenceRange) }
    }

    private func driveDigitalHuman(
        with text: String,
        voice: DigitalHumanVoice,
        digitalHuman: LilyDigitalHumanController,
        generation: Int
    ) {
        let pcmUtterance = makeUtterance(text, voice: voice)
        activePCMUtterance = pcmUtterance
        var totalPCMBytes = 0

        pcmSynthesizer.write(pcmUtterance) { [weak self, weak digitalHuman] buffer in
            guard let self = self, generation == self.speechGeneration, !self.didFinishCurrentSpeech else {
                return
            }

            guard let pcmBuffer = buffer as? AVAudioPCMBuffer else {
                return
            }

            if pcmBuffer.frameLength == 0 {
                DispatchQueue.main.async {
                    self.scheduleSentenceHighlights(
                        for: text,
                        pcmByteCount: totalPCMBytes,
                        generation: generation
                    )
                    digitalHuman?.finishPushingSpeechAudio()
                }
                return
            }

            if let pcmData = self.convertToDuixPCM(pcmBuffer) {
                totalPCMBytes += pcmData.count
                digitalHuman?.appendPCM(pcmData)
            }
        }
    }

    private func scheduleSentenceHighlights(for text: String, pcmByteCount: Int, generation: Int) {
        sentenceHighlightWorkItems.forEach { $0.cancel() }
        sentenceHighlightWorkItems.removeAll()
        let ranges = sentenceRanges(in: text)
        guard !ranges.isEmpty else { return }

        // 16 kHz, 16-bit mono = 32,000 bytes/sec. Use the generated PCM duration,
        // then allocate it by sentence length like Android's sentence-by-sentence playback.
        let totalDuration = max(0.4, Double(pcmByteCount) / 32_000.0)
        let totalUnits = max(1, ranges.reduce(0) { $0 + $1.length })
        var elapsed: TimeInterval = 0.12
        for range in ranges {
            let item = DispatchWorkItem { [weak self] in
                guard let self = self, generation == self.speechGeneration, !self.didFinishCurrentSpeech else { return }
                self.onRangeChange?(range)
            }
            sentenceHighlightWorkItems.append(item)
            DispatchQueue.main.asyncAfter(deadline: .now() + elapsed, execute: item)
            elapsed += totalDuration * Double(range.length) / Double(totalUnits)
        }
    }

    private func sentenceRanges(in text: String) -> [NSRange] {
        let nsText = text as NSString
        guard let regex = try? NSRegularExpression(pattern: #"[^。！？!?；;\n]+[。！？!?；;]?|\n+"#) else { return [] }
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).compactMap { match in
            let raw = nsText.substring(with: match.range)
            let sentence = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sentence.isEmpty else { return nil }
            let localRange = (raw as NSString).range(of: sentence)
            return NSRange(location: match.range.location + localRange.location, length: localRange.length)
        }
    }

    private func sentenceRange(containing range: NSRange, in text: String) -> NSRange {
        sentenceRanges(in: text).first(where: { NSIntersectionRange($0, range).length > 0 }) ?? range
    }

    private func finishSpeech() {
        guard !didFinishCurrentSpeech else { return }
        didFinishCurrentSpeech = true
        digitalHumanFinishWorkItem?.cancel()
        digitalHumanFinishWorkItem = nil
        sentenceHighlightWorkItems.forEach { $0.cancel() }
        sentenceHighlightWorkItems.removeAll()
        let digitalHuman = activeDigitalHuman
        activeUtterance = nil
        activeDigitalHuman = nil
        resetDuixPCMConverter()
        digitalHuman?.finishSpeechSession()
        onFinish?()
        onStart = nil
        onFinish = nil
        onRangeChange = nil
        activePCMUtterance = nil
        deactivateAudioSessionWithoutBlockingUI()
    }

    private func deactivateAudioSessionWithoutBlockingUI() {
        DispatchQueue.global(qos: .utility).async {
            let started = ProcessInfo.processInfo.systemUptime
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            #if DEBUG
            let elapsed = ProcessInfo.processInfo.systemUptime - started
            print("duix audio_session_deactivated elapsed=\(String(format: "%.3f", elapsed))s")
            #endif
        }
    }

    private func fallbackToSystemSpeech(_ utterance: AVSpeechUtterance) {
        activeDigitalHuman?.stopSpeechSession()
        activeDigitalHuman = nil
        activeUtterance = utterance
        didFinishCurrentSpeech = false
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        synthesizer.speak(utterance)
    }

    private func makeUtterance(_ text: String, voice: DigitalHumanVoice) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice == .male ? preferredMandarinMaleVoice() : preferredMandarinFemaleVoice()
        utterance.rate = voice == .male ? 0.48 : 0.50
        utterance.pitchMultiplier = voice == .male ? 1.0 : 1.12
        utterance.volume = 1.0
        return utterance
    }

    private func preferredMandarinMaleVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()

        // Leo 固定优先使用系统“彬彬”普通话男声。系统版本和语言不同
        // 时可能显示为彬彬、Binbin 或 Bin-bin，因此同时匹配名称与标识符。
        let binbinAliases = ["彬彬", "binbin", "bin-bin", "bin_bin", "bin bin"]
        if let binbinVoice = voices.first(where: { voice in
            let searchable = "\(voice.name) \(voice.identifier)".lowercased()
            return voice.language.hasPrefix("zh") && binbinAliases.contains { searchable.contains($0) }
        }) {
            return binbinVoice
        }

        let mandarinMaleVoices = voices
            .filter { $0.language == "zh-CN" && $0.gender == .male }
            .sorted { $0.quality.rawValue > $1.quality.rawValue }
        if let best = mandarinMaleVoices.first {
            return best
        }

        if let chineseMaleVoice = voices
            .filter({ $0.language.hasPrefix("zh") && $0.gender == .male })
            .sorted(by: { $0.quality.rawValue > $1.quality.rawValue })
            .first {
            return chineseMaleVoice
        }

        let maleAliases = ["yunyang", "yunxi", "yunfeng", "male", "daniel"]
        if let namedVoice = voices.first(where: { voice in
            let searchable = "\(voice.name) \(voice.identifier)".lowercased()
            return voice.language.hasPrefix("zh") && maleAliases.contains { searchable.contains($0) }
        }) {
            return namedVoice
        }
        return AVSpeechSynthesisVoice(language: "zh-CN")
    }

    private func preferredMandarinFemaleVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let mandarinVoices = voices.filter { $0.language == "zh-CN" }

        // Lily 固定优先使用设备中的“黎潋”女声。不同系统版本可能使用
        // 中文名或 Li-Lian/Lilian 作为 name、identifier，因此同时兼容匹配。
        let liLianAliases = ["黎潋", "li-lian", "li_lian", "li lian", "lilian"]
        if let liLianVoice = voices.first(where: { voice in
            let searchable = "\(voice.name) \(voice.identifier)".lowercased()
            return voice.language.hasPrefix("zh") && liLianAliases.contains { searchable.contains($0) }
        }) {
            return liLianVoice
        }

        if let enhancedFemaleVoice = mandarinVoices
            .filter({ isLikelyFemaleMandarinVoice($0) })
            .sorted(by: { $0.quality.rawValue > $1.quality.rawValue })
            .first {
            return enhancedFemaleVoice
        }

        if let femaleChineseVoice = voices
            .filter({ $0.language.hasPrefix("zh") && isLikelyFemaleMandarinVoice($0) })
            .sorted(by: { $0.quality.rawValue > $1.quality.rawValue })
            .first {
            return femaleChineseVoice
        }

        return AVSpeechSynthesisVoice(language: "zh-CN")
    }

    private func isLikelyFemaleMandarinVoice(_ voice: AVSpeechSynthesisVoice) -> Bool {
        let searchable = "\(voice.name) \(voice.identifier)".lowercased()
        let preferredFemaleNames = [
            "tingting",
            "mei-jia",
            "meijia",
            "sin-ji",
            "sinji",
            "female",
            "siri"
        ]
        return preferredFemaleNames.contains { searchable.contains($0) }
    }

    private func scheduleDigitalHumanSafetyTimeout(for text: String, generation: Int) {
        digitalHumanFinishWorkItem?.cancel()
        let timeout = max(45.0, min(120.0, Double(text.count) * 0.45 + 20.0))
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, generation == self.speechGeneration else { return }
            #if DEBUG
            print("Duix speech safety timeout, forcing stop")
            #endif
            self.finishSpeech()
        }
        digitalHumanFinishWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: workItem)
    }

    private func convertToDuixPCM(_ sourceBuffer: AVAudioPCMBuffer) -> Data? {
        guard let targetFormat = duixPCMTargetFormat else {
            return nil
        }

        let converter: AVAudioConverter
        if
            let existingConverter = duixPCMConverter,
            let existingSourceFormat = duixPCMSourceFormat,
            isSameAudioFormat(existingSourceFormat, sourceBuffer.format)
        {
            converter = existingConverter
        } else {
            guard let newConverter = AVAudioConverter(from: sourceBuffer.format, to: targetFormat) else {
                return nil
            }
            newConverter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
            duixPCMConverter = newConverter
            duixPCMSourceFormat = sourceBuffer.format
            converter = newConverter
        }

        let ratio = targetFormat.sampleRate / sourceBuffer.format.sampleRate
        let capacity = AVAudioFrameCount(max(1, Double(sourceBuffer.frameLength) * ratio + 32))
        guard let targetBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return nil
        }

        var didProvideInput = false
        var conversionError: NSError?
        converter.convert(to: targetBuffer, error: &conversionError) { _, status in
            if didProvideInput {
                status.pointee = .noDataNow
                return nil
            }
            didProvideInput = true
            status.pointee = .haveData
            return sourceBuffer
        }

        guard conversionError == nil, targetBuffer.frameLength > 0 else {
            return nil
        }

        let byteCount = Int(targetBuffer.frameLength) * Int(targetFormat.streamDescription.pointee.mBytesPerFrame)
        guard let dataPointer = targetBuffer.int16ChannelData?[0] else {
            return nil
        }
        return Data(bytes: dataPointer, count: byteCount)
    }

    private func resetDuixPCMConverter() {
        duixPCMConverter = nil
        duixPCMSourceFormat = nil
    }

    private func isSameAudioFormat(_ lhs: AVAudioFormat, _ rhs: AVAudioFormat) -> Bool {
        lhs.commonFormat == rhs.commonFormat
            && lhs.sampleRate == rhs.sampleRate
            && lhs.channelCount == rhs.channelCount
            && lhs.isInterleaved == rhs.isInterleaved
    }
}
