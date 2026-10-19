package com.motologger.app.car

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

    var currentTelemetry = CarTelemetry()
        private set

    private val listeners = mutableListOf<() -> Unit>()
    var onTareZeroRequested: (() -> Unit)? = null

    fun update(telemetry: CarTelemetry) {
        currentTelemetry = telemetry
        listeners.forEach { it.invoke() }
    }

    fun addListener(listener: () -> Unit) {
        listeners.add(listener)
    }

    fun removeListener(listener: () -> Unit) {
        listeners.remove(listener)
    }

    fun requestTareZero() {
        onTareZeroRequested?.invoke()
    }
}
