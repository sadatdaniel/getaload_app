package io.github.sadatdaniel.dmn_app

import android.webkit.CookieManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // "Sign in to a site": reads the in-app web page's cookies (including HttpOnly ones, which the page itself
    // cannot see) so they can go to the server, then clears them off the phone.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dmn/cookies").setMethodCallHandler { call, result ->
            val cm = CookieManager.getInstance()
            when (call.method) {
                "get" -> result.success(cm.getCookie(call.argument<String>("url")) ?: "")
                "clear" -> cm.removeAllCookies { cm.flush(); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }
}
