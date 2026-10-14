package br.com.garotodoprograma.chatdogaroto

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import android.util.Base64
import android.util.Log
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec

/**
 * Biometric unlock of the app.db key: a Keystore
 * AES-256-GCM key that needs strong biometrics on every use and dies when a
 * new fingerprint is enrolled. The app.db key, wrapped by it, is kept by
 * the Dart side. Never log keys.
 */
object BiometricKey {
    private const val TAG = "ChatDoGaroto"
    private const val ALIAS = "app_bio"
    private const val KEYSTORE = "AndroidKeyStore"
    private const val TRANSFORMATION = "AES/GCM/NoPadding"
    private const val IV_BYTES = 12

    /** Errors reported to Dart, as BiometricException codes. */
    class Failure(val code: String) : Exception(code)

    fun available(context: Context): Boolean =
        BiometricManager.from(context).canAuthenticate(BIOMETRIC_STRONG) ==
            BiometricManager.BIOMETRIC_SUCCESS

    /** Wraps [secretHex] after a prompt; calls back with a base64 blob. */
    fun enroll(activity: FragmentActivity, secretHex: String, done: (Result<String>) -> Unit) {
        val cipher = try {
            delete()
            Cipher.getInstance(TRANSFORMATION).apply { init(Cipher.ENCRYPT_MODE, createKey()) }
        } catch (e: Exception) {
            Log.w(TAG, "enroll: ${e.javaClass.simpleName}") // the type only
            return done(Result.failure(Failure("unavailable")))
        }
        prompt(activity, cipher, done) { c ->
            val secret = secretHex.hexToBytes()
            try {
                Base64.encodeToString(c.iv + c.doFinal(secret), Base64.NO_WRAP)
            } finally {
                secret.fill(0)
            }
        }
    }

    /** Unwraps [blob] after a prompt; calls back with the secret in hex. */
    fun unlock(activity: FragmentActivity, blob: String, done: (Result<String>) -> Unit) {
        val raw = try {
            Base64.decode(blob, Base64.NO_WRAP)
        } catch (e: IllegalArgumentException) {
            return done(Result.failure(Failure("failed")))
        }
        val key = loadKey() ?: return done(Result.failure(Failure("invalidated")))
        val cipher = try {
            Cipher.getInstance(TRANSFORMATION).apply {
                init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, raw, 0, IV_BYTES))
            }
        } catch (e: KeyPermanentlyInvalidatedException) {
            delete()
            return done(Result.failure(Failure("invalidated")))
        } catch (e: Exception) {
            Log.w(TAG, "unlock: ${e.javaClass.simpleName}")
            return done(Result.failure(Failure("failed")))
        }
        prompt(activity, cipher, done) { c ->
            val secret = c.doFinal(raw, IV_BYTES, raw.size - IV_BYTES)
            try {
                secret.joinToString("") { "%02x".format(it) }
            } finally {
                secret.fill(0)
            }
        }
    }

    fun delete() {
        val store = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        if (store.containsAlias(ALIAS)) store.deleteEntry(ALIAS)
    }

    /** Where each of our Keystore keys lives. */
    fun keyInfo(): Map<String, String> {
        val store = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        return listOf("wa_db_wrap", ALIAS).filter(store::containsAlias).associateWith { alias ->
            val key = store.getKey(alias, null) as SecretKey
            val info = SecretKeyFactory.getInstance(key.algorithm, KEYSTORE)
                .getKeySpec(key, KeyInfo::class.java) as KeyInfo
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                when (info.securityLevel) {
                    KeyProperties.SECURITY_LEVEL_STRONGBOX -> "strongbox"
                    KeyProperties.SECURITY_LEVEL_TRUSTED_ENVIRONMENT -> "tee"
                    KeyProperties.SECURITY_LEVEL_SOFTWARE -> "software"
                    else -> "unknown"
                }
            } else {
                @Suppress("DEPRECATION")
                if (info.isInsideSecureHardware) "tee" else "software"
            }
        }
    }

    private fun prompt(
        activity: FragmentActivity,
        cipher: Cipher,
        done: (Result<String>) -> Unit,
        use: (Cipher) -> String,
    ) {
        val callback = object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                val c = result.cryptoObject?.cipher ?: return done(Result.failure(Failure("failed")))
                done(
                    runCatching { use(c) }.recoverCatching {
                        Log.w(TAG, "after prompt: ${it.javaClass.simpleName}")
                        throw Failure("failed")
                    },
                )
            }

            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                Log.i(TAG, "prompt error $errorCode")
                val cancelled = errorCode == BiometricPrompt.ERROR_NEGATIVE_BUTTON ||
                    errorCode == BiometricPrompt.ERROR_USER_CANCELED ||
                    errorCode == BiometricPrompt.ERROR_CANCELED
                done(Result.failure(Failure(if (cancelled) "cancelled" else "failed")))
            }
            // onAuthenticationFailed (finger not recognized): the prompt stays.
        }
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle("Desbloquear o Chat do Garoto")
            .setNegativeButtonText("Usar PIN")
            .setAllowedAuthenticators(BIOMETRIC_STRONG)
            .build()
        BiometricPrompt(activity, ContextCompat.getMainExecutor(activity), callback)
            .authenticate(info, BiometricPrompt.CryptoObject(cipher))
    }

    private fun loadKey(): SecretKey? {
        val store = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        return store.getKey(ALIAS, null) as? SecretKey
    }

    private fun createKey(): SecretKey {
        fun spec(strongBox: Boolean) = KeyGenParameterSpec.Builder(
            ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setUserAuthenticationRequired(true)
            .setInvalidatedByBiometricEnrollment(true)
            .apply {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)
                }
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

    private fun String.hexToBytes(): ByteArray =
        ByteArray(length / 2) { i -> substring(2 * i, 2 * i + 2).toInt(16).toByte() }
}
