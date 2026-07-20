package fr.rsquare.notalone

import android.content.Context
import android.content.Intent
import android.media.AudioFormat
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.speech.ModelDownloadListener
import android.speech.RecognitionListener
import android.speech.RecognitionSupport
import android.speech.RecognitionSupportCallback
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.DataOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.Locale
import java.util.concurrent.Executors
import kotlin.math.roundToInt

/**
 * Reconnaissance vocale on-device pour Android, exposée à Dart via un
 * MethodChannel (`NativeSttEngine`).
 *
 * Le point délicat : `SpeechRecognizer` veut normalement le micro, or le
 * pipeline maison le possède déjà (doc 02 §2). On lui pousse donc **notre**
 * PCM via `EXTRA_AUDIO_SOURCE` (API 33+), un tube dont on écrit l'autre bout.
 * Rien n'est écrit sur disque (CLAUDE.md règle 2) : le tube est un descripteur
 * en mémoire.
 */
class SttChannel(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        /** Miroir de `NativeSttEngine.defaultChannel` côté Dart. */
        const val CHANNEL = "notalone/stt"

        /** Miroir de `SttErrorCode` côté Dart. */
        private const val ERROR_UNAVAILABLE = "stt_unavailable"
        private const val ERROR_MODEL_MISSING = "stt_model_missing"
        private const val ERROR_PERMISSION_DENIED = "stt_permission_denied"
        private const val ERROR_AUDIO_SOURCE_UNSUPPORTED = "stt_audio_source_unsupported"
        private const val ERROR_FAILED = "stt_failed"

        private const val ENGINE_ON_DEVICE = "android_on_device"
        private const val ENGINE_STANDARD = "android_standard"

        fun register(messenger: BinaryMessenger, context: Context): SttChannel {
            val instance = SttChannel(context)
            MethodChannel(messenger, CHANNEL).setMethodCallHandler(instance)
            return instance
        }
    }

    private val main = Handler(Looper.getMainLooper())
    private val audioWriters = Executors.newSingleThreadExecutor()

    /** Le recognizer vit sur le thread principal, comme l'exige l'API. */
    private var recognizer: SpeechRecognizer? = null
    private var engine: String = ENGINE_ON_DEVICE

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val languageTag = call.argument<String>("languageTag") ?: "fr-FR"
        when (call.method) {
            "prepare" -> prepare(languageTag, result)
            "transcribe" -> {
                val samples = call.argument<FloatArray>("samples")
                val sampleRate = call.argument<Int>("sampleRate")
                if (samples == null || sampleRate == null) {
                    result.error(ERROR_FAILED, "segment audio absent", null)
                } else {
                    transcribe(samples, sampleRate, languageTag, result)
                }
            }
            "dispose" -> {
                releaseRecognizer()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // region prepare

    private fun prepare(languageTag: String, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            // `createOnDeviceSpeechRecognizer` et `EXTRA_AUDIO_SOURCE` datent
            // tous deux d'API 33. En deçà, aucun moyen de pousser notre audio
            // sans laisser le recognizer prendre le micro : on préfère le dire.
            result.error(
                ERROR_UNAVAILABLE,
                "reconnaissance on-device indisponible avant Android 13",
                null,
            )
            return
        }
        if (!SpeechRecognizer.isOnDeviceRecognitionAvailable(context)) {
            result.error(
                ERROR_UNAVAILABLE,
                "aucun service de reconnaissance on-device sur cet appareil",
                null,
            )
            return
        }

        val recognizer = obtainRecognizer()
        val intent = recognitionIntent(languageTag)
        var settled = false

        recognizer.checkRecognitionSupport(
            intent,
            Executors.newSingleThreadExecutor(),
            object : RecognitionSupportCallback {
                override fun onSupportResult(support: RecognitionSupport) {
                    if (settled) return
                    val installed = support.installedOnDeviceLanguages.any { matches(it, languageTag) }
                    if (installed) {
                        settled = true
                        main.post { result.success(capabilities(languageTag)) }
                        return
                    }
                    val downloadable = support.supportedOnDeviceLanguages.any { matches(it, languageTag) } ||
                        support.pendingOnDeviceLanguages.any { matches(it, languageTag) }
                    if (!downloadable) {
                        settled = true
                        main.post {
                            result.error(
                                ERROR_MODEL_MISSING,
                                "modèle $languageTag ni installé ni téléchargeable",
                                null,
                            )
                        }
                        return
                    }
                    settled = true
                    main.post { downloadModel(intent, languageTag, result) }
                }

                override fun onError(error: Int) {
                    if (settled) return
                    settled = true
                    main.post {
                        result.error(
                            ERROR_UNAVAILABLE,
                            "support de reconnaissance non vérifiable (code $error)",
                            null,
                        )
                    }
                }
            },
        )
    }

    /**
     * Téléchargement du modèle français au premier lancement. Il peut être
     * long : on rend la main dès qu'il est terminé, et l'écran de capture
     * n'aura pas démarré le micro entre-temps.
     */
    private fun downloadModel(
        intent: Intent,
        languageTag: String,
        result: MethodChannel.Result,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val recognizer = obtainRecognizer()
        var settled = false
        recognizer.triggerModelDownload(
            intent,
            Executors.newSingleThreadExecutor(),
            object : ModelDownloadListener {
                override fun onProgress(completedPercent: Int) = Unit

                override fun onSuccess() {
                    if (settled) return
                    settled = true
                    main.post { result.success(capabilities(languageTag)) }
                }

                /** L'OS a pris la demande en charge sans nous tenir informés. */
                override fun onScheduled() {
                    if (settled) return
                    settled = true
                    main.post {
                        result.error(
                            ERROR_MODEL_MISSING,
                            "téléchargement du modèle $languageTag programmé, réessaie dans un instant",
                            null,
                        )
                    }
                }

                override fun onError(error: Int) {
                    if (settled) return
                    settled = true
                    main.post {
                        result.error(
                            ERROR_MODEL_MISSING,
                            "téléchargement du modèle $languageTag échoué (code $error)",
                            null,
                        )
                    }
                }
            },
        )
    }

    private fun capabilities(languageTag: String): Map<String, Any> = mapOf(
        "engine" to engine,
        "languageTag" to languageTag,
        "supportsPartials" to false,
        "isOnDevice" to true,
        "requiresNetwork" to false,
    )

    // endregion

    // region transcribe

    private fun transcribe(
        samples: FloatArray,
        sampleRate: Int,
        languageTag: String,
        result: MethodChannel.Result,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.error(ERROR_UNAVAILABLE, "Android 13 minimum", null)
            return
        }
        val pipe = try {
            ParcelFileDescriptor.createPipe()
        } catch (error: Exception) {
            result.error(ERROR_FAILED, "tube audio indisponible : ${error.message}", null)
            return
        }
        val readEnd = pipe[0]
        val writeEnd = pipe[1]

        val intent = recognitionIntent(languageTag).apply {
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE, readEnd)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_CHANNEL_COUNT, 1)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_ENCODING, AudioFormat.ENCODING_PCM_16BIT)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_SAMPLING_RATE, sampleRate)
        }

        var settled = false
        fun settle(action: () -> Unit) {
            if (settled) return
            settled = true
            action()
        }

        val recognizer = obtainRecognizer()
        recognizer.setRecognitionListener(object : RecognitionListener {
            override fun onResults(results: Bundle) {
                val text = results
                    .getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    ?.firstOrNull()
                    .orEmpty()
                settle {
                    result.success(
                        mapOf(
                            "text" to text,
                            "engine" to engine,
                            "languageTag" to languageTag,
                        ),
                    )
                }
            }

            override fun onError(error: Int) = settle { failWith(error, languageTag, result) }

            override fun onReadyForSpeech(params: Bundle?) = Unit
            override fun onBeginningOfSpeech() = Unit
            override fun onRmsChanged(rmsdB: Float) = Unit
            override fun onBufferReceived(buffer: ByteArray?) = Unit
            override fun onEndOfSpeech() = Unit
            override fun onPartialResults(partialResults: Bundle?) = Unit
            override fun onEvent(eventType: Int, params: Bundle?) = Unit
        })

        recognizer.startListening(intent)
        // Notre bout du tube ne sert plus : seul le service lit.
        closeQuietly(readEnd)
        writePcm(samples, writeEnd)
    }

    /**
     * Convertit le float [-1;1] du domaine en PCM 16 bits little-endian, le
     * seul encodage que `EXTRA_AUDIO_SOURCE_ENCODING` garantisse, puis ferme
     * le tube : c'est cette fermeture qui signale la fin du segment au
     * moteur — sans elle il attendrait indéfiniment.
     */
    private fun writePcm(samples: FloatArray, writeEnd: ParcelFileDescriptor) {
        audioWriters.execute {
            try {
                DataOutputStream(
                    ParcelFileDescriptor.AutoCloseOutputStream(writeEnd),
                ).use { output ->
                    val bytes = ByteBuffer
                        .allocate(samples.size * 2)
                        .order(ByteOrder.LITTLE_ENDIAN)
                    for (sample in samples) {
                        val clamped = sample.coerceIn(-1f, 1f)
                        bytes.putShort((clamped * Short.MAX_VALUE).roundToInt().toShort())
                    }
                    output.write(bytes.array())
                }
            } catch (error: Exception) {
                // Le listener rendra l'erreur : ici on ne fait que ne pas
                // laisser filer l'exception hors du thread.
            }
        }
    }

    private fun failWith(error: Int, languageTag: String, result: MethodChannel.Result) {
        when (error) {
            // Rien de reconnaissable dans ce segment : ce n'est pas une panne.
            // Le domaine compte ces segments vides sans les afficher.
            SpeechRecognizer.ERROR_NO_MATCH,
            SpeechRecognizer.ERROR_SPEECH_TIMEOUT,
            -> result.success(
                mapOf("text" to "", "engine" to engine, "languageTag" to languageTag),
            )

            SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS ->
                result.error(ERROR_PERMISSION_DENIED, "permission micro refusée", null)

            SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE,
            SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED,
            -> result.error(ERROR_MODEL_MISSING, "modèle $languageTag indisponible", null)

            // Le service n'a pas su lire le tube qu'on lui a tendu : sur cet
            // appareil, `EXTRA_AUDIO_SOURCE` n'est pas honoré. On ne bascule
            // pas sur le micro (doc 02 §2), on le signale.
            SpeechRecognizer.ERROR_AUDIO,
            SpeechRecognizer.ERROR_CANNOT_LISTEN_TO_DOWNLOAD_EVENTS,
            -> result.error(
                ERROR_AUDIO_SOURCE_UNSUPPORTED,
                "le moteur du téléphone refuse l'audio fourni par l'app (code $error)",
                null,
            )

            else -> result.error(ERROR_FAILED, "reconnaissance échouée (code $error)", null)
        }
    }

    // endregion

    private fun recognitionIntent(languageTag: String): Intent =
        Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
            )
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, languageTag)
            // Ceinture et bretelles avec le recognizer on-device : aucun
            // segment ne doit partir sur le réseau (doc 01 §1).
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
        }

    private fun obtainRecognizer(): SpeechRecognizer {
        recognizer?.let { return it }
        val created = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            SpeechRecognizer.isOnDeviceRecognitionAvailable(context)
        ) {
            engine = ENGINE_ON_DEVICE
            SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
        } else {
            engine = ENGINE_STANDARD
            SpeechRecognizer.createSpeechRecognizer(context)
        }
        recognizer = created
        return created
    }

    private fun releaseRecognizer() {
        recognizer?.destroy()
        recognizer = null
    }

    private fun matches(candidate: String, languageTag: String): Boolean =
        Locale.forLanguageTag(candidate).language
            .equals(Locale.forLanguageTag(languageTag).language, ignoreCase = true)

    private fun closeQuietly(descriptor: ParcelFileDescriptor) {
        try {
            descriptor.close()
        } catch (error: Exception) {
            // Rien à faire : le service a déjà son propre descripteur.
        }
    }
}
