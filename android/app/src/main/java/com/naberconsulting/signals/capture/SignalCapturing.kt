package com.naberconsulting.signals.capture

import com.naberconsulting.signals.model.LocationTag
import com.naberconsulting.signals.model.SignalRecord

typealias LocationProvider = () -> LocationTag?
typealias SignalEmitter = (SignalRecord) -> Unit

interface SignalCapturing {
    fun start()
    fun stop()
}
