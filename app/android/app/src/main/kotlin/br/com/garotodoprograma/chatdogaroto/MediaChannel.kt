package br.com.garotodoprograma.chatdogaroto

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.media.MediaCodec
import android.media.MediaDataSource
import android.media.MediaExtractor
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.OpenableColumns
import android.view.Surface
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.util.UUID
import java.util.concurrent.Executors

/** Shares files under cache/open with the app the user picks. */
class OpenFileProvider : FileProvider()

/**
 * Media on Android, on the "chatdogaroto/media"
 * channel: audio and video played from memory (no file, no local server),
 * voice recording, video prepared for sending without location, and
 * documents picked, opened with another app or saved. Created as a field of
 * the activity, so the result launchers are registered in time.
 */
class MediaChannel(private val activity: FlutterFragmentActivity) {
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private lateinit var textures: TextureRegistry

    private var pending: MethodChannel.Result? = null
    private var saveBytes: ByteArray? = null

    private val openDocument =
        activity.registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
            val result = pending.also { pending = null } ?: return@registerForActivityResult
            if (uri == null) result.success(null) else readDocument(uri, result)
        }
    private val createDocument =
        activity.registerForActivityResult(ActivityResultContracts.CreateDocument("*/*")) { uri ->
            val result = pending.also { pending = null } ?: return@registerForActivityResult
            val bytes = saveBytes.also { saveBytes = null }
            if (uri == null || bytes == null) {
                result.success(false)
                return@registerForActivityResult
            }
            background(result) {
                activity.contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                    ?: throw IllegalStateException("no output")
                true
            }
        }
    private val micPermission =
        activity.registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            pending.also { pending = null }?.success(granted)
        }

    fun attach(engine: FlutterEngine) {
        textures = engine.renderer
        MethodChannel(engine.dartExecutor.binaryMessenger, "chatdogaroto/media")
            .setMethodCallHandler(::handle)
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "audioPlay" -> audioPlay(call.argument<ByteArray>("bytes")!!, result)
            "audioPause" -> ok(result) { audio?.pause() }
            "audioResume" -> ok(result) { audio?.start() }
            "audioSeek" -> ok(result) { audio?.seekTo(call.argument<Int>("ms")!!) }
            "audioStop" -> ok(result) { stopAudio() }
            "audioState" -> result.success(state(audio))
            "videoOpen" -> videoOpen(call.argument<ByteArray>("bytes")!!, result)
            "videoPlay" -> ok(result) { video?.start() }
            "videoPause" -> ok(result) { video?.pause() }
            "videoSeek" -> ok(result) { video?.seekTo(call.argument<Int>("ms")!!) }
            "videoState" -> result.success(state(video))
            "videoClose" -> ok(result) { closeVideo() }
            "canRecord" -> result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
            "micPermission" -> micPermission(result)
            "recordStart" -> recordStart(result)
            "recordStop" -> recordStop(result)
            "recordCancel" -> ok(result) { recordCancel() }
            "videoPrepare" -> videoPrepare(call.argument<String>("path")!!, result)
            "pickDocument" -> {
                pending = result
                openDocument.launch(arrayOf("*/*"))
            }
            "openWith" -> openWith(
                call.argument<ByteArray>("bytes")!!,
                call.argument<String>("name")!!,
                call.argument<String>("mime")!!,
                result,
            )
            "saveAs" -> {
                pending = result
                saveBytes = call.argument<ByteArray>("bytes")!!
                createDocument.launch(safeName(call.argument<String>("name")!!))
            }
            else -> result.notImplemented()
        }
    }

    // --- Playing from memory ---------------------------------------------

    /** A media held in memory, read by the Android player. */
    private class Bytes(private val data: ByteArray) : MediaDataSource() {
        override fun readAt(position: Long, buffer: ByteArray, offset: Int, size: Int): Int {
            if (position >= data.size) return -1
            val n = minOf(size.toLong(), data.size - position).toInt()
            System.arraycopy(data, position.toInt(), buffer, offset, n)
            return n
        }

        override fun getSize(): Long = data.size.toLong()

        override fun close() {}
    }

    private var audio: MediaPlayer? = null
    private var video: MediaPlayer? = null
    private var videoTexture: TextureRegistry.SurfaceTextureEntry? = null
    private var videoSurface: Surface? = null

    private fun state(player: MediaPlayer?): Map<String, Any> {
        if (player == null) return mapOf("playing" to false, "position" to 0, "duration" to 0)
        return mapOf(
            "playing" to player.isPlaying,
            "position" to player.currentPosition,
            "duration" to player.duration,
        )
    }

    private fun audioPlay(bytes: ByteArray, result: MethodChannel.Result) {
        stopAudio()
        try {
            val player = MediaPlayer()
            player.setDataSource(Bytes(bytes))
            player.prepare()
            player.start()
            audio = player
            result.success(player.duration)
        } catch (e: Exception) {
            stopAudio()
            result.error("unplayable", null, null)
        }
    }

    private fun stopAudio() {
        audio?.release()
        audio = null
    }

    private fun videoOpen(bytes: ByteArray, result: MethodChannel.Result) {
        closeVideo()
        try {
            val entry = textures.createSurfaceTexture()
            val surface = Surface(entry.surfaceTexture())
            val player = MediaPlayer()
            player.setDataSource(Bytes(bytes))
            player.setSurface(surface)
            player.prepare()
            entry.surfaceTexture().setDefaultBufferSize(player.videoWidth, player.videoHeight)
            video = player
            videoTexture = entry
            videoSurface = surface
            result.success(
                mapOf(
                    "texture" to entry.id(),
                    "duration" to player.duration,
                    "width" to player.videoWidth,
                    "height" to player.videoHeight,
                ),
            )
        } catch (e: Exception) {
            closeVideo()
            result.error("unplayable", null, null)
        }
    }

    private fun closeVideo() {
        video?.release()
        video = null
        videoSurface?.release()
        videoSurface = null
        videoTexture?.release()
        videoTexture = null
    }

    // --- Voice messages ----------------------------------------------------

    private var recorder: MediaRecorder? = null
    private var recordFile: File? = null
    private var recordSince = 0L

    private fun micPermission(result: MethodChannel.Result) {
        if (activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        pending = result
        micPermission.launch(Manifest.permission.RECORD_AUDIO)
    }

    /** OGG/Opus, 16 kHz mono, as WhatsApp voice messages (Android 10+). */
    private fun recordStart(result: MethodChannel.Result) {
        recordCancel()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.error("unsupported", null, null)
            return
        }
        try {
            val file = File(activity.cacheDir, "rec_${UUID.randomUUID()}.ogg")
            val r = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                MediaRecorder(activity)
            } else {
                @Suppress("DEPRECATION")
                MediaRecorder()
            }
            r.setAudioSource(MediaRecorder.AudioSource.MIC)
            r.setOutputFormat(MediaRecorder.OutputFormat.OGG)
            r.setAudioEncoder(MediaRecorder.AudioEncoder.OPUS)
            r.setAudioSamplingRate(16000)
            r.setAudioChannels(1)
            r.setAudioEncodingBitRate(24000)
            r.setOutputFile(file.absolutePath)
            r.prepare()
            r.start()
            recorder = r
            recordFile = file
            recordSince = SystemClock.elapsedRealtime()
            result.success(null)
        } catch (e: Exception) {
            recordCancel()
            result.error("record_failed", null, null)
        }
    }

    /** The recording and its length; the file is deleted at once. */
    private fun recordStop(result: MethodChannel.Result) {
        val r = recorder ?: return result.success(null)
        val file = recordFile
        val ms = SystemClock.elapsedRealtime() - recordSince
        recorder = null
        recordFile = null
        val stopped = try {
            r.stop()
            true
        } catch (e: RuntimeException) {
            false // nothing was recorded
        } finally {
            r.release()
        }
        if (!stopped || file == null) {
            file?.delete()
            result.success(null)
            return
        }
        background(result) {
            try {
                mapOf("bytes" to file.readBytes(), "ms" to ms)
            } finally {
                file.delete()
            }
        }
    }

    private fun recordCancel() {
        recorder?.let {
            try {
                it.stop()
            } catch (e: RuntimeException) {
                // nothing was recorded
            }
            it.release()
        }
        recorder = null
        recordFile?.delete()
        recordFile = null
    }

    // --- Videos to send ----------------------------------------------------

    /**
     * A picked video ready to send: copied track by track into a new MP4
     * without the camera's metadata (location), with a thumbnail and its
     * length. "stripped" is false when the copy failed and the original is
     * returned; the user then decides.
     */
    private fun videoPrepare(path: String, result: MethodChannel.Result) {
        val src = File(path)
        if (src.length() > MAX_VIDEO) {
            result.error("too_big", null, null)
            return
        }
        background(result) {
            val out = File(activity.cacheDir, "vid_${UUID.randomUUID()}.mp4")
            try {
                val stripped = try {
                    remux(src, out)
                    true
                } catch (e: Exception) {
                    false
                }
                val chosen = if (stripped) out else src
                val retriever = MediaMetadataRetriever()
                try {
                    retriever.setDataSource(chosen.path)
                    val ms = retriever.extractMetadata(
                        MediaMetadataRetriever.METADATA_KEY_DURATION,
                    )?.toLongOrNull() ?: 0L
                    val thumb = retriever.getFrameAtTime(0)?.let { jpegThumb(it) }
                    mapOf(
                        "bytes" to chosen.readBytes(),
                        "ms" to ms,
                        "thumb" to thumb,
                        "stripped" to stripped,
                    )
                } finally {
                    retriever.release()
                }
            } finally {
                out.delete()
            }
        }
    }

    private fun remux(src: File, out: File) {
        val extractor = MediaExtractor()
        val muxer = MediaMuxer(out.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        try {
            extractor.setDataSource(src.path)
            val retriever = MediaMetadataRetriever()
            try {
                retriever.setDataSource(src.path)
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                    ?.toIntOrNull()?.let { muxer.setOrientationHint(it) }
            } finally {
                retriever.release()
            }
            val tracks = IntArray(extractor.trackCount) { i ->
                extractor.selectTrack(i)
                muxer.addTrack(extractor.getTrackFormat(i))
            }
            muxer.start()
            val buffer = ByteBuffer.allocate(2 * 1024 * 1024)
            val info = MediaCodec.BufferInfo()
            while (true) {
                info.size = extractor.readSampleData(buffer, 0)
                if (info.size < 0) break
                info.offset = 0
                info.presentationTimeUs = extractor.sampleTime
                info.flags = if (extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0) {
                    MediaCodec.BUFFER_FLAG_KEY_FRAME
                } else {
                    0
                }
                muxer.writeSampleData(tracks[extractor.sampleTrackIndex], buffer, info)
                extractor.advance()
            }
            muxer.stop()
        } finally {
            extractor.release()
            muxer.release()
        }
    }

    private fun jpegThumb(frame: Bitmap): ByteArray {
        val scale = 320f / maxOf(frame.width, frame.height)
        val small = if (scale < 1f) {
            Bitmap.createScaledBitmap(
                frame,
                (frame.width * scale).toInt().coerceAtLeast(1),
                (frame.height * scale).toInt().coerceAtLeast(1),
                true,
            )
        } else {
            frame
        }
        return ByteArrayOutputStream().use {
            small.compress(Bitmap.CompressFormat.JPEG, 60, it)
            it.toByteArray()
        }
    }

    // --- Documents -----------------------------------------------------------

    /** Read straight into memory through the system picker (no permission). */
    private fun readDocument(uri: Uri, result: MethodChannel.Result) {
        background(result) {
            var name = "documento"
            var size = -1L
            activity.contentResolver.query(uri, null, null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    c.getColumnIndex(OpenableColumns.DISPLAY_NAME).takeIf { it >= 0 }
                        ?.let { name = c.getString(it) ?: name }
                    c.getColumnIndex(OpenableColumns.SIZE).takeIf { it >= 0 && !c.isNull(it) }
                        ?.let { size = c.getLong(it) }
                }
            }
            if (size > MAX_DOCUMENT) throw TooBig()
            val bytes = activity.contentResolver.openInputStream(uri)?.use { input ->
                val out = ByteArrayOutputStream()
                val chunk = ByteArray(64 * 1024)
                while (true) {
                    val n = input.read(chunk)
                    if (n < 0) break
                    out.write(chunk, 0, n)
                    if (out.size() > MAX_DOCUMENT) throw TooBig()
                }
                out.toByteArray()
            } ?: throw IllegalStateException("unreadable")
            mapOf(
                "name" to name,
                "mime" to (activity.contentResolver.getType(uri) ?: "application/octet-stream"),
                "bytes" to bytes,
            )
        }
    }

    /**
     * A decrypted copy under cache/open for the app the user picks; deleted
     * when the user comes back.
     */
    private fun openWith(bytes: ByteArray, name: String, mime: String, result: MethodChannel.Result) {
        background(result, after = { uri ->
            val intent = Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri as Uri, mime)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            try {
                activity.startActivity(Intent.createChooser(intent, null))
                true
            } catch (e: ActivityNotFoundException) {
                cleanOpened()
                false
            }
        }) {
            val dir = File(File(activity.cacheDir, "open"), UUID.randomUUID().toString())
            dir.mkdirs()
            val file = File(dir, safeName(name))
            file.writeBytes(bytes)
            FileProvider.getUriForFile(activity, "${activity.packageName}.open", file)
        }
    }

    /** The "abrir com" copies; called when the app shows again. */
    fun cleanOpened() {
        File(activity.cacheDir, "open").deleteRecursively()
    }

    /** Leftovers of a closed app: recordings, videos and opened copies. */
    fun cleanLeftovers() {
        cleanOpened()
        activity.cacheDir.listFiles()?.forEach {
            if (it.name.startsWith("rec_") || it.name.startsWith("vid_")) it.delete()
        }
    }

    // --- Helpers -------------------------------------------------------------

    private class TooBig : Exception()

    private fun safeName(name: String): String =
        name.replace(Regex("[/\\\\:*?\"<>|\\u0000-\\u001f]"), "_").take(120).ifBlank { "documento" }

    private inline fun ok(result: MethodChannel.Result, action: () -> Unit) {
        try {
            action()
            result.success(null)
        } catch (e: Exception) {
            result.error("failed", null, null)
        }
    }

    /** Runs [work] off the main thread and replies on it. */
    private fun background(
        result: MethodChannel.Result,
        after: ((Any?) -> Any?)? = null,
        work: () -> Any?,
    ) {
        worker.execute {
            val outcome = runCatching(work)
            main.post {
                outcome.fold(
                    onSuccess = { value ->
                        result.success(if (after != null) after(value) else value)
                    },
                    onFailure = {
                        result.error(if (it is TooBig) "too_big" else "failed", null, null)
                    },
                )
            }
        }
    }

    companion object {
        const val MAX_VIDEO = 64L * 1024 * 1024
        const val MAX_DOCUMENT = 100L * 1024 * 1024
    }
}
