#pragma once

#include <Arduino.h>
#include "config.h"

/**
 * @file led_indicator.h
 * @brief Non-blocking LED pattern manager for Blue and Yellow diagnostic LEDs.
 */
class LedIndicator {
public:
    enum class Pattern : uint8_t {
        OFF,
        SOLID_ON,
        SLOW_BLINK,    // 1 Hz (Normal operation)
        FAST_BLINK,    // 5 Hz (Shutdown countdown / alert)
        BURST_BLINK,   // Double flash (CAN RX activity)
        ERROR_BLINK    // 10 Hz rapid strobe
    };

    LedIndicator();
    void begin();
    void setYellowPattern(Pattern pattern);
    void setBluePattern(Pattern pattern);
    void triggerCanActivity();
    void update();

private:
    Pattern yellow_pattern_;
    Pattern blue_pattern_;

    uint32_t yellow_last_toggle_ms_;
    uint32_t blue_last_toggle_ms_;
    bool yellow_state_;
    bool blue_state_;
    uint32_t can_burst_end_ms_;

    void applyPattern(gpio_num_t pin, Pattern pattern, uint32_t& last_toggle, bool& state);
};
