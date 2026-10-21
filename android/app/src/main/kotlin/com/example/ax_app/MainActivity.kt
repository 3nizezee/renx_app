package com.example.ax_app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.ax_app/renpy_bridge"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isPluginInstalled" -> {
                    val isInstalled = checkPackageInstalled("cyou.joiplay.renpy") || 
                                     checkPackageInstalled("org.renpy.android") ||
                                     checkPackageInstalled("cyou.joiplay.joiplay")
                    result.success(isInstalled)
                }
                "hasAllFilesAccess" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        result.success(Environment.isExternalStorageManager())
                    } else {
                        result.success(true)
                    }
                }
                "requestAllFilesAccess" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        try {
                            val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
                            intent.data = Uri.parse("package:$packageName")
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            try {
                                val intent = Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
                                startActivity(intent)
                                result.success(true)
                            } catch (ex: Exception) {
                                result.error("PERMISSION_ERROR", ex.message, null)
                            }
                        }
                    } else {
                        result.success(true)
                    }
                }
                "launchRenpyGame" -> {
                    val gamePath = call.argument<String>("gamePath") ?: ""
                    val executable = call.argument<String>("executable") ?: ""
                    val success = launchGameWithPlugin(gamePath, executable)
                    result.success(success)
                }
                "openUrl" -> {
                    val url = call.argument<String>("url") ?: "https://joiplay.cyou/"
                    try {
                        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "getAppDataPath" -> {
                    result.success(filesDir.absolutePath)
                }
                "getExternalStoragePath" -> {
                    result.success(Environment.getExternalStorageDirectory().absolutePath)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun checkPackageInstalled(packageName: String): Boolean {
        return try {
            packageManager.getPackageInfo(packageName, 0)
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun launchGameWithPlugin(gamePath: String, executable: String): Boolean {
        val packages = listOf("cyou.joiplay.renpy", "org.renpy.android", "cyou.joiplay.joiplay")
        for (pkg in packages) {
            if (checkPackageInstalled(pkg)) {
                try {
                    val launchIntent = packageManager.getLaunchIntentForPackage(pkg)
                    if (launchIntent != null) {
                        launchIntent.putExtra("game_dir", gamePath)
                        launchIntent.putExtra("game_path", gamePath)
                        launchIntent.putExtra("executable", executable)
                        launchIntent.putExtra("target", gamePath)
                        launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(launchIntent)
                        return true
                    }
                } catch (e: Exception) {
                    // Try next package
                }
            }
        }
        return false
    }
}
