package br.com.garotodoprograma.chatdogaroto

import android.content.Context
import org.json.JSONObject
import java.io.File

/**
 * The Go core called from Kotlin, for connecting without the app on screen
 *. It loads the same libchatcore the Flutter side uses,
 * so there is still a single Go runtime in the process.
 */
object CoreNative {
    init {
        System.loadLibrary("chatcore")
    }

    /** Calls cc_wa_resume; returns the JSON envelope. */
    @JvmStatic
    private external fun resume(path: String, source: String, key: String): String?

    /** Same file as the Dart side: getApplicationSupportDirectory()/wa/wa.db. */
    private fun sessionPath(context: Context) =
        File(File(context.filesDir, "wa"), "wa.db").path

    /**
     * Connects if an account is paired. [source] is "system" or "boot".
     * Returns false when there is no account (nothing is left running).
     */
    fun resumePaired(context: Context, source: String): Boolean {
        val envelope = resume(sessionPath(context), source, WaKey.get(context)) ?: return false
        return try {
            val json = JSONObject(envelope)
            json.optBoolean("ok") && json.optJSONObject("data")?.optBoolean("paired") == true
        } catch (e: org.json.JSONException) {
            false
        }
    }
}
