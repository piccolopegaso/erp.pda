package com.miclinker.mic_pda

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Native bridge for the PDA:
 *  - hardware scanner results delivered as broadcast intents (most PDA brands)
 *  - beeps via ToneGenerator (no audio files / plugins needed, works on Android 5+)
 *  - vibration, keep-screen-on
 */
class MainActivity : FlutterActivity() {
    private val methodChannelName = "mic_pda/device"
    private val scanChannelName = "mic_pda/scan"

    private var scanSink: EventChannel.EventSink? = null
    private var scanReceiver: BroadcastReceiver? = null
    private var scanActions: List<String> = emptyList()
    private var scanExtraKeys: List<String> = emptyList()
    private var toneGenerator: ToneGenerator? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, methodChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "configureScanner" -> {
                    @Suppress("UNCHECKED_CAST")
                    scanActions = (call.argument<List<String>>("actions") ?: emptyList())
                        .map { it.trim() }.filter { it.isNotEmpty() }.distinct()
                    @Suppress("UNCHECKED_CAST")
                    scanExtraKeys = (call.argument<List<String>>("extras") ?: emptyList())
                        .map { it.trim() }.filter { it.isNotEmpty() }.distinct()
                    registerScanReceiver()
                    result.success(scanActions.size)
                }
                "beep" -> {
                    beep(call.argument<String>("type") ?: "ok")
                    result.success(null)
                }
                "vibrate" -> {
                    vibrate((call.argument<Int>("ms") ?: 80).toLong())
                    result.success(null)
                }
                "keepScreenOn" -> {
                    val on = call.argument<Boolean>("on") ?: true
                    if (on) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    result.success(null)
                }
                "deviceInfo" -> {
                    result.success(
                        mapOf(
                            "manufacturer" to Build.MANUFACTURER,
                            "model" to Build.MODEL,
                            "brand" to Build.BRAND,
                            "sdk" to Build.VERSION.SDK_INT,
                            "release" to Build.VERSION.RELEASE
                        )
                    )
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, scanChannelName).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                scanSink = events
            }

            override fun onCancel(arguments: Any?) {
                scanSink = null
            }
        })
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun onResume() {
        super.onResume()
        registerScanReceiver()
    }

    override fun onPause() {
        // Scanner broadcasts are only consumed while the app is in front,
        // so a scan made in another app never lands in a warehouse operation.
        unregisterScanReceiver()
        super.onPause()
    }

    override fun onDestroy() {
        unregisterScanReceiver()
        toneGenerator?.release()
        toneGenerator = null
        super.onDestroy()
    }

    private fun registerScanReceiver() {
        unregisterScanReceiver()
        if (scanActions.isEmpty()) return
        val filter = IntentFilter()
        scanActions.forEach { filter.addAction(it) }
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent == null) return
                val code = extractBarcode(intent) ?: return
                mainHandler.post {
                    scanSink?.success(mapOf("code" to code, "action" to (intent.action ?: "")))
                }
            }
        }
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            registerReceiver(receiver, filter)
        }
        scanReceiver = receiver
    }

    private fun unregisterScanReceiver() {
        scanReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {
            }
        }
        scanReceiver = null
    }

    /** Tries the configured extra keys first, then any String / byte[] extra as fallback. */
    private fun extractBarcode(intent: Intent): String? {
        val extras = intent.extras ?: return null
        for (key in scanExtraKeys) {
            if (!extras.containsKey(key)) continue
            val v = readExtra(intent, key, extras.get(key))
            if (!v.isNullOrBlank()) return v.trim()
        }
        for (key in extras.keySet()) {
            val raw = extras.get(key)
            if (raw is String && raw.isNotBlank() && !key.contains("type", true) && !key.contains("source", true)) {
                return raw.trim()
            }
        }
        return null
    }

    private fun readExtra(intent: Intent, key: String, raw: Any?): String? {
        return when (raw) {
            is String -> raw
            is ByteArray -> {
                // Urovo-style: byte[] + "length"
                val len = intent.getIntExtra("length", raw.size).coerceIn(0, raw.size)
                String(raw, 0, len, Charsets.UTF_8)
            }
            is CharSequence -> raw.toString()
            else -> raw?.toString()
        }
    }

    private fun tone(): ToneGenerator? {
        if (toneGenerator == null) {
            toneGenerator = try {
                ToneGenerator(AudioManager.STREAM_MUSIC, 100)
            } catch (_: Exception) {
                null
            }
        }
        return toneGenerator
    }

    private fun beep(type: String) {
        val tg = tone() ?: return
        when (type) {
            "ok" -> tg.startTone(ToneGenerator.TONE_PROP_BEEP, 120)
            "error" -> tg.startTone(ToneGenerator.TONE_CDMA_ABBR_ALERT, 900)
            "warn" -> tg.startTone(ToneGenerator.TONE_PROP_BEEP2, 400)
            "double" -> {
                tg.startTone(ToneGenerator.TONE_PROP_ACK, 300)
            }
            else -> tg.startTone(ToneGenerator.TONE_PROP_BEEP, 120)
        }
    }

    @Suppress("DEPRECATION")
    private fun vibrate(ms: Long) {
        val v = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator ?: return
        if (!v.hasVibrator()) return
        if (Build.VERSION.SDK_INT >= 26) {
            v.vibrate(VibrationEffect.createOneShot(ms, VibrationEffect.DEFAULT_AMPLITUDE))
        } else {
            v.vibrate(ms)
        }
    }
}
