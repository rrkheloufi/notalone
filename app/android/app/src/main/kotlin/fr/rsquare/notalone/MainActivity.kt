package fr.rsquare.notalone

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        /** Miroir de `ForegroundServiceCaptureGuard` côté Dart. */
        const val CHANNEL = "notalone/background_capture"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> startCaptureService(
                        call.argument<String>("title").orEmpty(),
                        call.argument<String>("text").orEmpty(),
                        result,
                    )
                    "stop" -> {
                        stopService(Intent(this, CaptureForegroundService::class.java))
                        result.success(null)
                    }
                    "isBatteryOptimizationDisabled" ->
                        result.success(isBatteryOptimizationDisabled())
                    "requestBatteryOptimizationExemption" -> {
                        requestBatteryOptimizationExemption()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun startCaptureService(
        title: String,
        text: String,
        result: MethodChannel.Result,
    ) {
        val intent = Intent(this, CaptureForegroundService::class.java)
            .putExtra(CaptureForegroundService.EXTRA_TITLE, title)
            .putExtra(CaptureForegroundService.EXTRA_TEXT, text)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
            result.success(null)
        } catch (error: Exception) {
            // Notamment ForegroundServiceStartNotAllowedException (Android 12+)
            // quand l'app n'est plus au premier plan à cet instant.
            result.error("start_failed", error.message, null)
        }
    }

    private fun isBatteryOptimizationDisabled(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        return power.isIgnoringBatteryOptimizations(packageName)
    }

    private fun requestBatteryOptimizationExemption() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        if (isBatteryOptimizationDisabled()) return
        startActivity(
            Intent(
                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                Uri.parse("package:$packageName"),
            ),
        )
    }
}
