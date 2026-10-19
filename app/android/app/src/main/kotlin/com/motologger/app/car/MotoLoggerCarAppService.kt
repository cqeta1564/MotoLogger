package com.motologger.app.car

import androidx.car.app.CarAppService
import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.car.app.model.*
import androidx.car.app.validation.HostValidator
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import android.content.Intent

/**
 * MotoLoggerCarAppService
 * Provides Android Auto motorcycle telemetry projection for motorcycle head units.
 */
class MotoLoggerCarAppService : CarAppService() {
    override fun createHostValidator(): HostValidator {
        return HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
    }

    override fun onCreateSession(): Session {
        return MotoLoggerCarSession()
    }
}

class MotoLoggerCarSession : Session() {
    override fun onCreateScreen(intent: Intent): Screen {
        return MotoLoggerDashboardScreen(carContext)
    }
}

class MotoLoggerDashboardScreen(carContext: androidx.car.app.CarContext) : Screen(carContext) {

    private val listener: () -> Unit = {
        invalidate()
    }

    init {
        CarTelemetryRepository.addListener(listener)
        lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onDestroy(owner: LifecycleOwner) {
                CarTelemetryRepository.removeListener(listener)
            }
        })
    }

    private fun formatLapTime(ms: Long): String {
        if (ms <= 0) return "0:00.0"
        val totalSec = ms / 1000
        val min = totalSec / 60
        val sec = totalSec % 60
        val tenths = (ms % 1000) / 100
        return String.format("%d:%02d.%d", min, sec, tenths)
    }

    override fun onGetTemplate(): Template {
        val t = CarTelemetryRepository.currentTelemetry
        val paneBuilder = Pane.Builder()

        // 1. Lean Angle row
        val leanCurrent = if (t.isConnected && t.leanAngleDeg != null) {
            String.format("%.1f°", t.leanAngleDeg)
        } else {
            "—"
        }
        val peakLeft = if (t.maxLeanLeft != null && t.maxLeanLeft < 0.0) {
            String.format("%.1f°", t.maxLeanLeft)
        } else {
            "—"
        }
        val peakRight = if (t.maxLeanRight != null && t.maxLeanRight > 0.0) {
            String.format("+%.1f°", t.maxLeanRight)
        } else {
            "—"
        }

        paneBuilder.addRow(
            Row.Builder()
                .setTitle("NÁKLON (LEAN ANGLE)")
                .addText("Aktuální: $leanCurrent | Max vlevo: $peakLeft | Max vpravo: $peakRight")
                .build()
        )

        // 2. Powertrain & Gear row
        val gearStr = if (t.isConnected && t.gear != null) {
            if (t.gear == 0) "N" else t.gear.toString()
        } else {
            "—"
        }
        val speedStr = if (t.speedKmh != null && (t.isConnected || t.speedKmh > 0)) {
            "${t.speedKmh} km/h"
        } else {
            "—"
        }
        val rpmStr = if (t.isConnected && t.engineRpm != null && t.engineRpm > 0) {
            String.format("%,d ot/min", t.engineRpm)
        } else {
            "—"
        }

        paneBuilder.addRow(
            Row.Builder()
                .setTitle("RYCHLOST & POHON")
                .addText("Rychlost: $speedStr | Převod: $gearStr | Otáčky: $rpmStr")
                .build()
        )

        // 3. Status & Lap timer row
        val statusText = if (t.isRecording) {
            val lapTimeStr = formatLapTime(t.lapElapsedMs)
            val deltaStr = if (t.deltaSeconds != null) {
                val d = t.deltaSeconds
                val sign = if (d > 0) "+" else ""
                String.format(" | Delta: %s%.2fs", sign, d)
            } else {
                ""
            }
            "Záznam běží · Kolo ${t.currentLap} ($lapTimeStr$deltaStr)"
        } else {
            val connStr = if (t.isConnected) "Jednotka připojena" else "Jednotka odpojena"
            val tempStr = if (t.isConnected && t.coolantTempC != null && t.coolantTempC > 0) {
                " | Teplota vody: ${t.coolantTempC}°C"
            } else {
                ""
            }
            "$connStr$tempStr"
        }

        paneBuilder.addRow(
            Row.Builder()
                .setTitle("STAV JÍZDY")
                .addText(statusText)
                .build()
        )

        paneBuilder.addAction(
            Action.Builder()
                .setTitle("VYNULOVAT NÁKLON (TARE)")
                .setOnClickListener {
                    CarTelemetryRepository.requestTareZero()
                }
                .build()
        )

        return PaneTemplate.Builder(paneBuilder.build())
            .setHeaderAction(Action.APP_ICON)
            .setTitle("MotoLogger Telemetrie")
            .build()
    }
}
