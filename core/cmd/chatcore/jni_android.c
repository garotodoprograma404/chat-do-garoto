// JNI entry point for the Android ConnectionService.
// Compiled for Android only (file suffix). It forwards to the C API, so the
// same rules apply: a JSON envelope comes back and no panic crosses.

#include <jni.h>
#include <stddef.h>

#include "_cgo_export.h"

JNIEXPORT jstring JNICALL
Java_br_com_garotodoprograma_chatdogaroto_CoreNative_resume(JNIEnv *env, jclass cls,
                                                  jstring path,
                                                  jstring source,
                                                  jstring key) {
  (void)cls;
  if (path == NULL || source == NULL || key == NULL) return NULL;
  const char *p = (*env)->GetStringUTFChars(env, path, NULL);
  const char *s = (*env)->GetStringUTFChars(env, source, NULL);
  const char *k = (*env)->GetStringUTFChars(env, key, NULL);
  jstring out = NULL;
  if (p != NULL && s != NULL && k != NULL) {
    char *result = cc_wa_resume((char *)p, (char *)s, (char *)k);
    out = (*env)->NewStringUTF(env, result);
    cc_free(result);
  }
  if (p != NULL) (*env)->ReleaseStringUTFChars(env, path, p);
  if (s != NULL) (*env)->ReleaseStringUTFChars(env, source, s);
  if (k != NULL) (*env)->ReleaseStringUTFChars(env, key, k);
  return out;
}
