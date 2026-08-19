package com.naberconsulting.signals

import android.app.Application
import com.naberconsulting.signals.capture.CaptureController

/**
 * Holds the single [CaptureController] so the capture service and the UI
 * share one pipeline instance (and one offline queue).
 */
class SignalsApp : Application() {
    val controller: CaptureController by lazy { CaptureController(this) }

    companion object {
        fun controllerOf(app: Application): CaptureController = (app as SignalsApp).controller
    }
}
