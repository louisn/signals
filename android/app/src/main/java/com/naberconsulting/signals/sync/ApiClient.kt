package com.naberconsulting.signals.sync

import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.IOException
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

class UnauthorizedException : IOException("unauthorized")
class ServerException(val status: Int) : IOException("server_status_$status")

data class BatchUploadResponse(
    val batchId: String,
    val accepted: List<String>,
    val rejectedIds: List<String>,
)

/**
 * Thin client for `POST /v1/signals/batches`. Batching, retry/backoff, and
 * queue-state transitions live in [SyncEngine]; this treats each call as a
 * stateless request/response. The API key is swappable at runtime (via
 * re-provisioning) without rebuilding the engine.
 */
class ApiClient(
    baseUrl: String,
    apiKey: String,
    private val client: OkHttpClient = defaultClient(),
) {
    private val apiKeyRef = AtomicReference(apiKey)
    private val baseUrlRef = AtomicReference(baseUrl)

    fun updateApiKey(newKey: String) = apiKeyRef.set(newKey)
    fun updateBaseUrl(newBase: String) = baseUrlRef.set(newBase)

    fun uploadBatch(body: JSONObject): BatchUploadResponse {
        val request = Request.Builder()
            .url("${baseUrlRef.get().trimEnd('/')}/v1/signals/batches")
            .header("Content-Type", "application/json")
            .header("Authorization", "Bearer ${apiKeyRef.get()}")
            .post(body.toString().toRequestBody(JSON))
            .build()

        client.newCall(request).execute().use { response ->
            if (response.code == 401 || response.code == 403) throw UnauthorizedException()
            if (!response.isSuccessful) throw ServerException(response.code)

            val json = JSONObject(response.body?.string().orEmpty())
            val accepted = json.optJSONArray("accepted").toStringList()
            val rejected = mutableListOf<String>()
            json.optJSONArray("rejected")?.let { arr ->
                for (i in 0 until arr.length()) {
                    rejected.add(arr.getJSONObject(i).getString("id"))
                }
            }
            return BatchUploadResponse(
                batchId = json.optString("batch_id"),
                accepted = accepted,
                rejectedIds = rejected,
            )
        }
    }

    companion object {
        private val JSON = "application/json; charset=utf-8".toMediaType()

        private fun defaultClient() = OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .build()

        private fun org.json.JSONArray?.toStringList(): List<String> {
            if (this == null) return emptyList()
            return (0 until length()).map { getString(it) }
        }
    }
}
