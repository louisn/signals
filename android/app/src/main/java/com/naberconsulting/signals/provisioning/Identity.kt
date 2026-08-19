package com.naberconsulting.signals.provisioning

import android.content.Context
import java.util.UUID

private const val PREFS = "signals_identity"

/**
 * A stable per-install device id, generated once and persisted. Every signal
 * batch is submitted under this id, and (re-)provisioning registers the SAME
 * id -- matching the iOS DeviceIdentity contract the backend expects.
 */
object DeviceIdentity {
    private const val KEY = "device_id"

    fun currentDeviceId(context: Context): String {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs.getString(KEY, null)?.let { return it }
        val id = UUID.randomUUID().toString()
        prefs.edit().putString(KEY, id).apply()
        return id
    }

    /**
     * Adopts a backend-minted device id (from QR/deep-link provisioning),
     * replacing the self-generated one. The batch device_id is read live at
     * upload time, so already-queued rows simply upload under the new identity.
     */
    fun setDeviceId(context: Context, id: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, id).apply()
    }
}

/** The backend base URL, overridable by a scanned credential; defaults handled by the caller. */
object BaseUrlStore {
    private const val KEY = "base_url"

    fun read(context: Context): String? =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null)

    fun save(context: Context, url: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, url).apply()
    }
}

/**
 * Stores the device bearer token. Plain SharedPreferences for now (the app's
 * private prefs file is sandboxed per-app); hardening to
 * EncryptedSharedPreferences is the Android parallel to the iOS Keychain and
 * is a deliberate follow-up, kept out here to avoid an alpha dependency.
 */
object ApiKeyStore {
    private const val KEY = "api_key"

    fun read(context: Context): String =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, "") ?: ""

    fun save(context: Context, key: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, key).apply()
    }
}
