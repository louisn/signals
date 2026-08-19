package com.naberconsulting.signals.provisioning

import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.IOException
import java.util.concurrent.TimeUnit

class InvalidAdminKeyException : IOException("invalid_admin_key")

data class ProvisioningResponse(val deviceId: String, val apiKey: String)

/**
 * Talks to the admin-key-protected `POST /v1/devices`. A dev/ops convenience:
 * the admin key is always user-typed, never embedded. Re-provisioning an
 * existing device id is safe and rotates its key rather than failing.
 */
class ProvisioningClient(
    private val baseUrl: String,
    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build(),
) {
    fun provisionDevice(deviceId: String, label: String, adminKey: String): ProvisioningResponse {
        val body = JSONObject().apply {
            put("device_id", deviceId)
            put("label", label)
        }
        val request = Request.Builder()
            .url("${baseUrl.trimEnd('/')}/v1/devices")
            .header("Content-Type", "application/json")
            .header("X-Admin-Key", adminKey)
            .post(body.toString().toRequestBody(JSON))
            .build()

        client.newCall(request).execute().use { response ->
            if (response.code == 401) throw InvalidAdminKeyException()
            if (!response.isSuccessful) throw IOException("provision_status_${response.code}")
            val json = JSONObject(response.body?.string().orEmpty())
            return ProvisioningResponse(
                deviceId = json.getString("device_id"),
                apiKey = json.getString("api_key"),
            )
        }
    }

    companion object {
        private val JSON = "application/json; charset=utf-8".toMediaType()
    }
}
