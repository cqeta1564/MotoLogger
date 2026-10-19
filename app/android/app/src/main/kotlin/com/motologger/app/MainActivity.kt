package com.motologger.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.motologger.app.car.CarTelemetryRepository

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.motologger.app/car_projection"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "updateTelemetry" -> {
                    val map = call.arguments as? Map<*, *>
                    if (map != null) {
                        val isConnected = map["isConnected"] as? Boolean ?: false
                        val isRecording = map["isRecording"] as? Boolean ?: false
                        val lean = (map["leanAngleDeg"] as? Number)?.toDouble()
                        val speed = (map["speedKmh"] as? Number)?.toInt()
                        val rpm = (map["engineRpm"] as? Number)?.toInt()
                        val gear = (map["gear"] as? Number)?.toInt()
                        val coolant = (map["coolantTempC"] as? Number)?.toInt()
                        val accelX = (map["accelXG"] as? Number)?.toDouble()
                        val accelY = (map["accelYG"] as? Number)?.toDouble()
                        val maxLeft = (map["maxLeanLeft"] as? Number)?.toDouble()
                        val maxRight = (map["maxLeanRight"] as? Number)?.toDouble()
                        val lap = (map["currentLap"] as? Number)?.toInt() ?: 1
                        val lapElapsed = (map["lapElapsedMs"] as? Number)?.toLong() ?: 0L
                        val delta = (map["deltaSeconds"] as? Number)?.toDouble()

                        CarTelemetryRepository.update(
                            CarTelemetryRepository.CarTelemetry(
                                leanAngleDeg = lean,
                                speedKmh = speed,
                                engineRpm = rpm,
                                gear = gear,
                                coolantTempC = coolant,
                                accelXG = accelX,
                                accelYG = accelY,
                                maxLeanLeft = maxLeft,
                                maxLeanRight = maxRight,
                                isConnected = isConnected,
                                isRecording = isRecording,
                                currentLap = lap,
                                lapElapsedMs = lapElapsed,
                                deltaSeconds = delta
                            )
                        )
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGS", "Expected telemetry map", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        CarTelemetryRepository.onTareZeroRequested = {
            runOnUiThread {
                channel.invokeMethod("tareZero", null)
            }
        }
    }
}
