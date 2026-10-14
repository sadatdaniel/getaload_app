package io.github.sadatdaniel.getaload

import android.content.Intent
import android.os.Build
import android.webkit.CookieManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "getaload/system").setMethodCallHandler { call, result ->
            val cm = CookieManager.getInstance()
            when (call.method) {
                // "Sign in to a site": the in-app page's cookies (HttpOnly ones too), then forget them.
                "cookies" -> result.success(cm.getCookie(call.argument<String>("url")) ?: "")
                "clearCookies" -> cm.removeAllCookies { cm.flush(); result.success(null) }
                // Self-update: which APK fits this phone, and hand a downloaded one to Android's installer.
                "abi" -> result.success(Build.SUPPORTED_ABIS.firstOrNull() ?: "")
                "installApk" -> {
                    val file = File(call.argument<String>("path")!!)
                    val uri = FileProvider.getUriForFile(this, "$packageName.updates", file)
                    startActivity(
                        Intent(Intent.ACTION_VIEW)
                            .setDataAndType(uri, "application/vnd.android.package-archive")
                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
