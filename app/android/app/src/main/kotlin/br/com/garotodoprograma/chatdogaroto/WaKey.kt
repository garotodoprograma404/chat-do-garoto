package br.com.garotodoprograma.chatdogaroto

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.os.Build
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import java.io.File
import java.security.GeneralSecurityException
import java.security.KeyStore
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * The key of wa.db, the Go session database.
 *
 * A random 256-bit key, stored in files/wa/wa.key wrapped by an AES-256-GCM
 * key of the Android Keystore that never leaves it. No user authentication
 * is required, so the connection service can open the database without the
 * app on screen. Never log the key.
 */
object WaKey {
    private const val ALIAS = "wa_db_wrap"
    private const val KEYSTORE = "AndroidKeyStore"
    private const val TRANSFORMATION = "AES/GCM/NoPadding"
    private const val IV_BYTES = 12
    private const val TAG_BITS = 128

    /** The key in lowercase hex, created on first use. */
    @Synchronized
    fun get(context: Context): String {
        val file = File(File(context.filesDir, "wa"), "wa.key")
        if (file.exists()) {
            try {
                return unwrap(file.readBytes()).toHex()
            } catch (e: GeneralSecurityException) {
                // The Keystore lost its key: the database cannot be opened
                // anymore. A new key makes the core answer "unreadable", and
                // the app pairs again.
                file.delete()
            }
        }
        val key = ByteArray(32).also { SecureRandom().nextBytes(it) }
        try {
            file.parentFile?.mkdirs()
            val tmp = File(file.path + ".tmp")
            tmp.writeBytes(wrap(key))
            if (!tmp.renameTo(file)) throw IllegalStateException("cannot store the session key")
            return key.toHex()
        } finally {
            key.fill(0)
        }
    }

    private fun wrappingKey(): SecretKey {
        val store = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (store.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        fun spec(strongBox: Boolean) = KeyGenParameterSpec.Builder(
            ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .apply {
                // The dedicated security chip when the phone has one.
                if (strongBox && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    setIsStrongBoxBacked(true)
                }
            }
            .build()
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        return try {
            generator.init(spec(strongBox = true))
            generator.generateKey()
        } catch (e: StrongBoxUnavailableException) {
            generator.init(spec(strongBox = false)) // no StrongBox: the TEE
            generator.generateKey()
        }
    }

    /** IV (12 bytes) followed by the ciphertext and tag. */
    private fun wrap(key: ByteArray): ByteArray {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, wrappingKey()) // the Keystore picks a random IV
        return cipher.iv + cipher.doFinal(key)
    }

    private fun unwrap(blob: ByteArray): ByteArray {
        if (blob.size <= IV_BYTES) throw GeneralSecurityException("short key file")
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(
            Cipher.DECRYPT_MODE,
            wrappingKey(),
            GCMParameterSpec(TAG_BITS, blob, 0, IV_BYTES),
        )
        return cipher.doFinal(blob, IV_BYTES, blob.size - IV_BYTES)
    }

    private fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it) }
}
