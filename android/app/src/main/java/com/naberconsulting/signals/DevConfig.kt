package com.naberconsulting.signals

/**
 * Backend endpoint. Defaults to the hosted Fly dev backend, matching the iOS
 * DevConfig default. Point a debug build at a local backend by changing this
 * to the emulator loopback alias `http://10.0.2.2:8080` (the host machine's
 * localhost as seen from the Android emulator).
 */
object DevConfig {
    const val apiBaseUrl: String = "https://signals-api-dev.fly.dev"
}
