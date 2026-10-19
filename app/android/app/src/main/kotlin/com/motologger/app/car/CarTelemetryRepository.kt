package com.motologger.app.car

import android.os.Handler
import android.os.Looper
import java.util.concurrent.CopyOnWriteArrayList

object CarTelemetryRepository {
    data class CarTelemetry(
        val leanAngleDeg: Double? = null,
        val speedKmh: Int? = null,
        val engineRpm: Int? = null,
        val gear: Int? = null,
        val coolantTempC: Int? = null,
        val accelXG: Double? = null,
        val accelYG: Double? = null,
        val maxLeanLeft: Double? = null,
        val maxLeanRight: Double? = null,
        val isConnected: Boolean = false,
        val isRecording: Boolean = false,
        val currentLap: Int = 1,
        val lapElapsedMs: Long = 0L,
        val deltaSeconds: Double? = null
    )

    @Volatile
    var currentTelemetry = CarTelemetry()
        private set

    private val mainHandler = Handler(Looper.getMainLooper())
    private val listeners = CopyOnWriteArrayList<() -> Unit>()
    var onTareZeroRequested: (() -> Unit)? = null

    fun update(telemetry: CarTelemetry) {
        currentTelemetry = telemetry
        if (Looper.myLooper() == Looper.getMainLooper()) {
            listeners.forEach { it.invoke() }
        } else {
            mainHandler.post {
                listeners.forEach { it.invoke() }
            }
        }
    }

    fun addListener(listener: () -> Unit) {
        if (!listeners.contains(listener)) {
            listeners.add(listener)
        }
    }

    fun removeListener(listener: () -> Unit) {
        listeners.remove(listener)
    }

    fun requestTareZero() {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            onTareZeroRequested?.invoke()
        } else {
            mainHandler.post {
                onTareZeroRequested?.invoke()
            }
        }
    }
}

