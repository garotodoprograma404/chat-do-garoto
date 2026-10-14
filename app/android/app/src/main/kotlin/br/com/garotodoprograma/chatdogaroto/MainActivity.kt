package br.com.garotodoprograma.chatdogaroto

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    // A field, so its result launchers are registered in time.
    private val media = MediaChannel(this)
    private val backup = BackupChannel(this)
    private val contacts = ContactPickerChannel(this)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // No screenshots and no thumbnail in recent apps.
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        media.cleanLeftovers()
    }

    override fun onResume() {
        super.onResume()
        // Back from the app that opened a document: its copy goes.
        media.cleanOpened()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        securityChannel(flutterEngine)
        media.attach(flutterEngine)
        backup.attach(flutterEngine)
        contacts.attach(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "chatdogaroto/connection")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        askNotificationPermission()
                        val intent = Intent(this, ConnectionService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(null)
                    }
                    "stop" -> {
                        stopService(Intent(this, ConnectionService::class.java))
                        result.success(null)
                    }
                    // The wa.db key, for the Dart side to open the session.
                    "waKey" -> result.success(WaKey.get(this))
                    "batteryStatus" -> result.success(
                        mapOf(
                            "unrestricted" to isUnrestricted(),
                            "xiaomi" to isXiaomi(),
                        ),
                    )
                    "openBatterySettings" -> {
                        openFirst(
                            Intent(
                                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                Uri.parse("package:$packageName"),
                            ),
                        )
                        result.success(null)
                    }
                    "openAutostart" -> {
                        openFirst(
                            Intent().setComponent(
                                ComponentName(
                                    "com.miui.securitycenter",
                                    "com.miui.permcenter.autostart.AutoStartManagementActivity",
                                ),
                            ),
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** Biometrics and key information for the app lock. */
    private fun securityChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "chatdogaroto/security")
            .setMethodCallHandler { call, result ->
                val reply: (Result<String>) -> Unit = { outcome ->
                    outcome.fold(
                        onSuccess = { result.success(it) },
                        onFailure = {
                            result.error((it as? BiometricKey.Failure)?.code ?: "failed", null, null)
                        },
                    )
                }
                when (call.method) {
                    "bioAvailable" -> result.success(BiometricKey.available(this))
                    "bioEnroll" -> BiometricKey.enroll(this, call.arguments as String, reply)
                    "bioUnlock" -> BiometricKey.unlock(this, call.arguments as String, reply)
                    "bioDisable" -> {
                        BiometricKey.delete()
                        result.success(null)
                    }
                    "keyInfo" -> result.success(BiometricKey.keyInfo())
                    else -> result.notImplemented()
                }
            }
    }

    /** Whether Android may stop the app to save battery. */
    private fun isUnrestricted(): Boolean =
        getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(packageName)

    private fun isXiaomi(): Boolean =
        listOf("xiaomi", "redmi", "poco").any {
            Build.MANUFACTURER.equals(it, ignoreCase = true) || Build.BRAND.equals(it, ignoreCase = true)
        }

    /** Opens [intent], or this app's details screen when it is unavailable. */
    private fun openFirst(intent: Intent) {
        try {
            startActivity(intent)
        } catch (e: ActivityNotFoundException) {
            startActivity(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")),
            )
        } catch (e: SecurityException) {
            startActivity(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")),
            )
        }
    }

    /** Android 13+ asks before showing the persistent notification. */
    private fun askNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 0)
        }
    }
}
