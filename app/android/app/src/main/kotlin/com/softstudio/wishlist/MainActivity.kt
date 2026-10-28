package com.softstudio.wishlist

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val SHARE_CHANNEL = "com.softstudio.wishlist/share"
        private const val TAKE_PENDING_SHARE = "takePendingShareText"
        private const val SHARED_TEXT = "sharedText"
    }

    private var shareChannel: MethodChannel? = null
    private var pendingShareText: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingShareText = sharedTextFrom(intent) ?: pendingShareText
        shareChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SHARE_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == TAKE_PENDING_SHARE) {
                    result.success(pendingShareText)
                    pendingShareText = null
                } else {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val text = sharedTextFrom(intent) ?: return
        val channel = shareChannel
        if (channel == null) {
            pendingShareText = text
        } else {
            channel.invokeMethod(SHARED_TEXT, text)
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        shareChannel?.setMethodCallHandler(null)
        shareChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun sharedTextFrom(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_SEND &&
            intent?.action != Intent.ACTION_SEND_MULTIPLE
        ) {
            return null
        }
        val title = intent.getCharSequenceExtra(Intent.EXTRA_TITLE)
            ?.toString()
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
        val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)
            ?.toString()
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
        return listOfNotNull(title, text)
            .distinct()
            .joinToString("\n")
            .takeIf { it.isNotEmpty() }
    }
}
