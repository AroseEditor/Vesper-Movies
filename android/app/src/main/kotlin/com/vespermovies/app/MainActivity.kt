package com.vespermovies.app

import android.app.UiModeManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterShellArgs
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var exo: VesperExoPlugin? = null
    private var external: MethodChannel? = null

    private fun isTelevision(): Boolean {
        val features = packageManager
        val uiMode = getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
        return uiMode?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION ||
            features.hasSystemFeature("android.software.leanback") ||
            features.hasSystemFeature("android.software.leanback_only") ||
            features.hasSystemFeature("amazon.hardware.fire_tv") ||
            !features.hasSystemFeature("android.hardware.touchscreen")
    }

    override fun getFlutterShellArgs(): FlutterShellArgs {
        val args = super.getFlutterShellArgs()
        if (isTelevision()) args.add("--enable-impeller=false")
        return args
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vesper/update").setMethodCallHandler { call, result ->
            when (call.method) {
                "abi" -> result.success(Build.SUPPORTED_ABIS.firstOrNull() ?: "arm64-v8a")
                "install" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.success("failed")
                        return@setMethodCallHandler
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
                        startActivity(
                            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                        )
                        result.success("permission")
                        return@setMethodCallHandler
                    }
                    val uri = FileProvider.getUriForFile(this, "$packageName.updates", File(path))
                    startActivity(
                        Intent(Intent.ACTION_VIEW)
                            .setDataAndType(uri, "application/vnd.android.package-archive")
                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK),
                    )
                    result.success("started")
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vesper/device").setMethodCallHandler { call, result ->
            if (call.method == "isTelevision") result.success(isTelevision()) else result.notImplemented()
        }
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
