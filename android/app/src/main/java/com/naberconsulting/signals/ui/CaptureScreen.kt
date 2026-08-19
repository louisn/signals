package com.naberconsulting.signals.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.naberconsulting.signals.BuildConfig
import com.naberconsulting.signals.capture.CaptureController
import kotlinx.coroutines.launch

@Composable
fun CaptureScreen(
    controller: CaptureController,
    onToggleCapture: (Boolean) -> Unit,
    onSyncNow: () -> Unit,
) {
    val isCapturing by controller.isCapturing.collectAsState()
    val pending by controller.pendingCount.collectAsState()
    val tagSightings by controller.tagSightings.collectAsState()
    val hasApiKey by controller.hasApiKey.collectAsState()
    var showProvisioning by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier.fillMaxSize().padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        if (!hasApiKey) {
            Text("No device key — captured records queue locally but won't upload.")
        }

        Text(if (isCapturing) "● Capturing" else "○ Paused")
        Text("$pending records queued for upload")
        if (tagSightings > 0) {
            Text("$tagSightings tracker tag sightings this session")
        }

        Button(onClick = { onToggleCapture(!isCapturing) }) {
            Text(if (isCapturing) "Pause capture" else "Start capture")
        }
        OutlinedButton(onClick = onSyncNow) { Text("Sync now") }
        OutlinedButton(onClick = { showProvisioning = true }) { Text("Device connection") }
    }

    if (showProvisioning) {
        ProvisioningDialog(controller = controller, onDismiss = { showProvisioning = false })
    }
}

@Composable
private fun ProvisioningDialog(controller: CaptureController, onDismiss: () -> Unit) {
    var apiKey by remember { mutableStateOf("") }
    var adminKey by remember { mutableStateOf("") }
    var status by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(onClick = {
                if (apiKey.isNotBlank()) {
                    controller.saveApiKey(apiKey.trim())
                    onDismiss()
                }
            }) { Text("Save key") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Close") } },
        title = { Text("Device connection") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Device ID: ${controller.deviceId}")
                OutlinedTextField(
                    value = apiKey, onValueChange = { apiKey = it },
                    label = { Text("Paste API key") },
                )
                if (BuildConfig.DEBUG) {
                    OutlinedTextField(
                        value = adminKey, onValueChange = { adminKey = it },
                        label = { Text("Admin key (debug provision)") },
                    )
                    TextButton(onClick = {
                        scope.launch {
                            status = try {
                                controller.provisionViaAdminKey(adminKey.trim(), "android-device")
                                "Provisioned."
                            } catch (e: Exception) {
                                "Failed: ${e.message}"
                            }
                        }
                    }) { Text("Provision via admin key") }
                }
                status?.let { Text(it) }
            }
        },
    )
}
