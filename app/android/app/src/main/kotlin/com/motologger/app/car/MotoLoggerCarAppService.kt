package com.motologger.app.car

import androidx.car.app.CarAppService
import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.car.app.model.*
import androidx.car.app.validation.HostValidator
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
    override fun onGetTemplate(): Template {
        // High-contrast motorcycle telemetry layout for Android Auto displays
        val paneBuilder = Pane.Builder()

        paneBuilder.addRow(
            Row.Builder()
                .setTitle("LEAN ANGLE")
                .addText("Current: 0.0° | Peak Left: -44.2° | Peak Right: +46.8°")
                .build()
        )

        paneBuilder.addRow(
            Row.Builder()
                .setTitle("POWERTRAIN & GEAR")
                .addText("Gear: 4 | Speed: 92 km/h | RPM: 8,450")
                .build()
        )

        paneBuilder.addRow(
            Row.Builder()
                .setTitle("BATTERY & SENSORS")
                .addText("14.2V (Alternator Active) | IMU 100Hz Active")
                .build()
        )

        paneBuilder.addAction(
            Action.Builder()
                .setTitle("TARE ZERO")
                .setOnClickListener {
                    // Send Tare command
                }
                .build()
        )

        return PaneTemplate.Builder(paneBuilder.build())
            .setHeaderAction(Action.APP_ICON)
            .setTitle("MotoLogger Telemetry")
            .build()
    }
}
