import AVFoundation
import Flutter
import Speech

/// Reconnaissance vocale on-device pour iOS, exposée à Dart via un
/// MethodChannel (`NativeSttEngine`).
///
/// Deux moteurs, comme la matrice du doc 02 §3 : `SpeechAnalyzer` à partir
/// d'iOS 26, `SFSpeechRecognizer` en deçà. Dans les deux cas on **pousse notre
/// propre PCM** — jamais le micro, que le pipeline maison possède déjà
/// (doc 02 §2). L'audio reçu vit en mémoire le temps de la reconnaissance et
/// n'est jamais écrit sur disque (CLAUDE.md règle 2).
final class SttChannel: NSObject {

    static let channelName = "notalone/stt"

    /// Miroir de `SttErrorCode` côté Dart.
    private enum ErrorCode {
        static let unavailable = "stt_unavailable"
        static let modelMissing = "stt_model_missing"
        static let permissionDenied = "stt_permission_denied"
        static let failed = "stt_failed"
    }

    private enum Engine {
        static let analyzer = "ios_speech_analyzer"
        static let legacy = "ios_sf_speech_recognizer"
    }

    /// Moteur retenu par `prepare`. `transcribe` s'y fie plutôt que de
    /// re-tester la disponibilité à chaque segment.
    private var preparedEngine: String?

    @discardableResult
    static func register(with messenger: FlutterBinaryMessenger) -> SttChannel {
        let instance = SttChannel()
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
        channel.setMethodCallHandler { call, result in
            instance.handle(call, result: result)
        }
        return instance
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [:]
        let languageTag = arguments["languageTag"] as? String ?? "fr-FR"

        switch call.method {
        case "prepare":
            prepare(languageTag: languageTag, result: result)
        case "transcribe":
            guard
                let samples = arguments["samples"] as? FlutterStandardTypedData,
                let sampleRate = arguments["sampleRate"] as? Int
            else {
                result(FlutterError(code: ErrorCode.failed, message: "segment audio absent", details: nil))
                return
            }
            transcribe(
                samples: samples.data,
                sampleRate: Double(sampleRate),
                languageTag: languageTag,
                result: result
            )
        case "dispose":
            preparedEngine = nil
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - prepare

    private func prepare(languageTag: String, result: @escaping FlutterResult) {
        if #available(iOS 26, *) {
            prepareAnalyzer(languageTag: languageTag, result: result)
        } else {
            prepareLegacy(languageTag: languageTag, result: result)
        }
    }

    /// iOS 26+ : le modèle se télécharge par `AssetInventory`, sans passer par
    /// les Réglages — et `SpeechAnalyzer` ne réclame aucune autorisation,
    /// l'audio ne quittant pas l'appareil.
    @available(iOS 26, *)
    private func prepareAnalyzer(languageTag: String, result: @escaping FlutterResult) {
        Task {
            let locale = Locale(identifier: languageTag)
            let supported = await SpeechTranscriber.supportedLocales
            guard supported.contains(where: { Self.matches($0, languageTag) }) else {
                // Le moteur récent ne connaît pas cette langue : le moteur
                // hérité la gère peut-être encore.
                self.prepareLegacy(languageTag: languageTag, result: result)
                return
            }

            let installed = await SpeechTranscriber.installedLocales
            if !installed.contains(where: { Self.matches($0, languageTag) }) {
                let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
                do {
                    if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                        try await request.downloadAndInstall()
                    }
                } catch {
                    result(FlutterError(
                        code: ErrorCode.modelMissing,
                        message: "téléchargement du modèle \(languageTag) impossible : \(error.localizedDescription)",
                        details: nil
                    ))
                    return
                }
            }

            self.preparedEngine = Engine.analyzer
            result([
                "engine": Engine.analyzer,
                "languageTag": languageTag,
                "supportsPartials": true,
                "isOnDevice": true,
                "requiresNetwork": false,
            ])
        }
    }

    /// iOS < 26 : `SFSpeechRecognizer` exige une autorisation explicite, même
    /// pour du 100 % on-device. Aucune API ne permet de télécharger le modèle
    /// à la place de l'utilisateur : s'il manque, on le dit franchement et
    /// l'écran de capture invite à l'installer depuis les Réglages.
    private func prepareLegacy(languageTag: String, result: @escaping FlutterResult) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    result(FlutterError(
                        code: ErrorCode.permissionDenied,
                        message: "autorisation de reconnaissance vocale refusée",
                        details: nil
                    ))
                    return
                }
                guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: languageTag)) else {
                    result(FlutterError(
                        code: ErrorCode.unavailable,
                        message: "aucun moteur pour \(languageTag)",
                        details: nil
                    ))
                    return
                }
                guard recognizer.supportsOnDeviceRecognition else {
                    result(FlutterError(
                        code: ErrorCode.modelMissing,
                        message: "modèle \(languageTag) non installé sur cet appareil",
                        details: nil
                    ))
                    return
                }
                self.preparedEngine = Engine.legacy
                result([
                    "engine": Engine.legacy,
                    "languageTag": languageTag,
                    "supportsPartials": false,
                    "isOnDevice": true,
                    "requiresNetwork": false,
                ])
            }
        }
    }

    // MARK: - transcribe

    private func transcribe(
        samples: Data,
        sampleRate: Double,
        languageTag: String,
        result: @escaping FlutterResult
    ) {
        guard let buffer = Self.pcmBuffer(from: samples, sampleRate: sampleRate) else {
            result(FlutterError(code: ErrorCode.failed, message: "buffer PCM invalide", details: nil))
            return
        }
        if #available(iOS 26, *), preparedEngine == Engine.analyzer {
            transcribeWithAnalyzer(buffer: buffer, languageTag: languageTag, result: result)
        } else {
            transcribeWithLegacy(buffer: buffer, languageTag: languageTag, result: result)
        }
    }

    @available(iOS 26, *)
    private func transcribeWithAnalyzer(
        buffer: AVAudioPCMBuffer,
        languageTag: String,
        result: @escaping FlutterResult
    ) {
        Task {
            do {
                // `.transcription` et non `.progressiveTranscription` : le
                // segment soumis est déjà complet, on ne veut que le final
                // (décision partiels du 20/07/2026).
                let transcriber = SpeechTranscriber(
                    locale: Locale(identifier: languageTag),
                    preset: .transcription
                )
                let analyzer = SpeechAnalyzer(modules: [transcriber])

                // L'analyseur impose son format d'entrée : notre 16 kHz float
                // mono n'est pas forcément celui-là, d'où la conversion.
                let input: AVAudioPCMBuffer
                if let target = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) {
                    input = try Self.convert(buffer, to: target)
                } else {
                    input = buffer
                }

                let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
                try await analyzer.start(inputSequence: stream)
                continuation.yield(AnalyzerInput(buffer: input))
                continuation.finish()
                try await analyzer.finalizeAndFinishThroughEndOfInput()

                var text = ""
                for try await transcription in transcriber.results where transcription.isFinal {
                    text += String(transcription.text.characters)
                }

                result([
                    "text": text.trimmingCharacters(in: .whitespacesAndNewlines),
                    "engine": Engine.analyzer,
                    "languageTag": languageTag,
                ])
            } catch {
                result(FlutterError(
                    code: ErrorCode.failed,
                    message: error.localizedDescription,
                    details: nil
                ))
            }
        }
    }

    /// Une session `SFSpeechRecognizer` **par segment** : c'est ce qui rend
    /// sans objet la limite d'une minute par session (doc 02 §2).
    private func transcribeWithLegacy(
        buffer: AVAudioPCMBuffer,
        languageTag: String,
        result: @escaping FlutterResult
    ) {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: languageTag)) else {
            result(FlutterError(code: ErrorCode.unavailable, message: "aucun moteur pour \(languageTag)", details: nil))
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = false
        // Sans cela le segment partirait chez Apple : le contrat du produit est
        // que rien ne quitte le téléphone (doc 01 §1, doc 03 §2).
        request.requiresOnDeviceRecognition = true
        request.append(buffer)
        request.endAudio()

        // `recognitionTask` peut rappeler plusieurs fois ; `FlutterResult` ne
        // se répond qu'une seule.
        var settled = false
        recognizer.recognitionTask(with: request) { recognition, error in
            guard !settled else { return }
            if let error = error {
                settled = true
                result(FlutterError(
                    code: ErrorCode.failed,
                    message: error.localizedDescription,
                    details: nil
                ))
                return
            }
            guard let recognition = recognition, recognition.isFinal else { return }
            settled = true
            result([
                "text": recognition.bestTranscription.formattedString,
                "engine": Engine.legacy,
                "languageTag": languageTag,
            ])
        }
    }

    // MARK: - helpers

    private static func matches(_ locale: Locale, _ languageTag: String) -> Bool {
        return locale.identifier(.bcp47).caseInsensitiveCompare(languageTag) == .orderedSame
    }

    /// Reconstruit un buffer float32 mono à partir des samples envoyés par
    /// Dart, dans le format que `SFSpeechRecognizer` accepte tel quel.
    private static func pcmBuffer(from samples: Data, sampleRate: Double) -> AVAudioPCMBuffer? {
        let frameCount = samples.count / MemoryLayout<Float>.size
        guard frameCount > 0,
              let format = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: sampleRate,
                  channels: 1,
                  interleaved: false
              ),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)),
              let channel = buffer.floatChannelData?[0]
        else { return nil }

        buffer.frameLength = AVAudioFrameCount(frameCount)
        samples.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: Float.self).baseAddress else { return }
            channel.update(from: base, count: frameCount)
        }
        return buffer
    }

    private enum ConversionError: Error {
        case unavailable
    }

    private static func convert(
        _ buffer: AVAudioPCMBuffer,
        to format: AVAudioFormat
    ) throws -> AVAudioPCMBuffer {
        if buffer.format == format { return buffer }
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else {
            throw ConversionError.unavailable
        }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw ConversionError.unavailable
        }

        var consumed = false
        var conversionError: NSError?
        converter.convert(to: output, error: &conversionError) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        if let conversionError = conversionError { throw conversionError }
        return output
    }
}
