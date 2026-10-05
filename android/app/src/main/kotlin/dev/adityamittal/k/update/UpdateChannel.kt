package dev.adityamittal.k.update

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * `k/update`: the installed version, and handing a downloaded APK to the
 * system installer. k is sideloaded, so updates come from GitHub releases
 * and Android asks the owner to confirm every install.
 */
class UpdateChannel(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, NAME)

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "appVersion" -> {
                    val info = activity.packageManager.getPackageInfo(activity.packageName, 0)
                    val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else {
                        @Suppress("DEPRECATION")
                        info.versionCode.toLong()
                    }
                    result.success(mapOf("name" to info.versionName, "code" to code))
                }
                "canInstall" -> result.success(activity.packageManager.canRequestPackageInstalls())
                "openInstallSettings" -> {
                    activity.startActivity(
                        Intent(
                            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                            Uri.parse("package:${activity.packageName}"),
                        ),
                    )
                    result.success(null)
                }
                "install" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("bad_args", "path missing", null)
                        return@setMethodCallHandler
                    }
                    val uri = FileProvider.getUriForFile(
                        activity,
                        "${activity.packageName}.updates",
                        File(path),
                    )
                    activity.startActivity(
                        Intent(Intent.ACTION_VIEW)
                            .setDataAndType(uri, "application/vnd.android.package-archive")
                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun dispose() = channel.setMethodCallHandler(null)

    companion object {
        const val NAME = "k/update"
    }
}
