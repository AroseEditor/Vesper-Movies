package com.vespermovies.app

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var exo: VesperExoPlugin? = null
    private var external: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        exo = VesperExoPlugin(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
            flutterEngine.renderer,
        )
        external = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vesper/external")
        external?.setMethodCallHandler { call, result ->
            if (call.method != "openVlc") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val url = call.argument<String>("url")
            if (url == null) {
                result.success(false)
                return@setMethodCallHandler
            }
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setPackage("org.videolan.vlc")
                setDataAndTypeAndNormalize(Uri.parse(url), "video/*")
                putExtra("title", call.argument<String>("title") ?: "")
                putExtra("from_start", false)
                putExtra("position", (call.argument<Number>("positionMs") ?: 0).toLong())
            }
            try {
                startActivityForResult(intent, VLC_REQUEST)
                result.success(true)
            } catch (_: ActivityNotFoundException) {
                try {
                    startActivity(
                        Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=org.videolan.vlc"))
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    )
                } catch (_: ActivityNotFoundException) {
                }
                result.success(false)
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != VLC_REQUEST || data == null) return
        val position = data.getLongExtra("extra_position", -1L)
        val duration = data.getLongExtra("extra_duration", -1L)
        if (position < 0 || duration <= 0) return
        external?.invokeMethod("vlcResult", mapOf("position" to position, "duration" to duration))
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        exo?.dispose()
        exo = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private companion object {
        const val VLC_REQUEST = 4127
    }
}
