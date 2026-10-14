package br.com.garotodoprograma.chatdogaroto

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.provider.ContactsContract.CommonDataKinds.Phone
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * "Escolher da agenda", on the "chatdogaroto/contacts"
 * channel: the system's contact picker, on phone numbers. Android grants a
 * one-time read of the picked number only, so the app has no permission
 * to read the address book. Nothing is kept here. Created as a field of
 * the activity, so the result launcher is registered in time.
 */
class ContactPickerChannel(private val activity: FlutterFragmentActivity) {
    private var pending: MethodChannel.Result? = null

    private val pick =
        activity.registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { out ->
            val result = pending.also { pending = null } ?: return@registerForActivityResult
            val uri = out.data?.data
            if (out.resultCode != Activity.RESULT_OK || uri == null) {
                result.success(null)
                return@registerForActivityResult
            }
            val picked = runCatching {
                activity.contentResolver.query(
                    uri,
                    arrayOf(Phone.DISPLAY_NAME, Phone.NUMBER),
                    null,
                    null,
                    null,
                )?.use { c ->
                    if (!c.moveToFirst()) {
                        null
                    } else {
                        mapOf("name" to (c.getString(0) ?: ""), "phone" to (c.getString(1) ?: ""))
                    }
                }
            }.getOrNull()
            if (picked == null) result.error("failed", null, null) else result.success(picked)
        }

    fun attach(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "chatdogaroto/contacts")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pick" -> {
                        pending?.success(null)
                        pending = result
                        try {
                            pick.launch(Intent(Intent.ACTION_PICK, Phone.CONTENT_URI))
                        } catch (e: ActivityNotFoundException) {
                            pending = null
                            result.error("unavailable", null, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
