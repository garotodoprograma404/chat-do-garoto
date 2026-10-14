package br.com.garotodoprograma.chatdogaroto

import android.net.Uri
import android.provider.DocumentsContract
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The backup file on Android, on the
 * "chatdogaroto/backup" channel: the system picker creates or opens the
 * file, and its descriptor goes to the core, which writes or reads it as a
 * stream and closes it. Nothing is copied here. Created as a field of the
 * activity, so the result launchers are registered in time.
 */
class BackupChannel(private val activity: FlutterFragmentActivity) {
    private var pending: MethodChannel.Result? = null

    private val create =
        activity.registerForActivityResult(
            ActivityResultContracts.CreateDocument("application/octet-stream"),
        ) { uri ->
            val result = pending.also { pending = null } ?: return@registerForActivityResult
            if (uri == null) {
                result.success(null)
                return@registerForActivityResult
            }
            val fd = runCatching {
                activity.contentResolver.openFileDescriptor(uri, "rwt")?.detachFd()
            }.getOrNull()
            if (fd == null) {
                delete(uri)
                result.error("failed", null, null)
            } else {
                result.success(mapOf("fd" to fd, "uri" to uri.toString()))
            }
        }

    private val open =
        activity.registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
            val result = pending.also { pending = null } ?: return@registerForActivityResult
            if (uri == null) {
                result.success(null)
                return@registerForActivityResult
            }
            val fd = runCatching {
                activity.contentResolver.openFileDescriptor(uri, "r")?.detachFd()
            }.getOrNull()
            if (fd == null) result.error("failed", null, null) else result.success(fd)
        }

    fun attach(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "chatdogaroto/backup")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "create" -> {
                        pending = result
                        create.launch(call.argument<String>("name")!!)
                    }
                    "open" -> {
                        pending = result
                        open.launch(arrayOf("*/*"))
                    }
                    // A cancelled or failed backup leaves no half file.
                    "delete" -> result.success(delete(Uri.parse(call.argument<String>("uri")!!)))
                    else -> result.notImplemented()
                }
            }
    }

    private fun delete(uri: Uri): Boolean =
        runCatching { DocumentsContract.deleteDocument(activity.contentResolver, uri) }
            .getOrDefault(false)
}
