package com.vespermovies.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var exo: VesperExoPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        exo = VesperExoPlugin(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
            flutterEngine.renderer,
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        exo?.dispose()
        exo = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
