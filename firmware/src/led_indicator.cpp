#include "led_indicator.h"

LedIndicator::LedIndicator()
    : yellow_pattern_(Pattern::OFF),
      blue_pattern_(Pattern::OFF),
      yellow_last_toggle_ms_(0),
      blue_last_toggle_ms_(0),
      yellow_state_(false),
      blue_state_(false),
      can_burst_end_ms_(0) {}

void LedIndicator::begin() {
    pinMode(PIN_LED_BLUE, OUTPUT);
    pinMode(PIN_LED_YELLOW, OUTPUT);
    digitalWrite(PIN_LED_BLUE, LOW);
    digitalWrite(PIN_LED_YELLOW, LOW);
}

void LedIndicator::setYellowPattern(Pattern pattern) {
    yellow_pattern_ = pattern;
}

void LedIndicator::setBluePattern(Pattern pattern) {
    blue_pattern_ = pattern;
}

void LedIndicator::triggerCanActivity() {
    can_burst_end_ms_ = millis() + 50; // 50 ms flash on CAN frame
}

void LedIndicator::applyPattern(gpio_num_t pin, Pattern pattern, uint32_t& last_toggle, bool& state) {
    uint32_t now = millis();
    uint32_t interval = 0;

    switch (pattern) {
        case Pattern::OFF:
            state = false;
            break;
        case Pattern::SOLID_ON:
            state = true;
            break;
        case Pattern::SLOW_BLINK:
            interval = 500; // 1 Hz (500 ms ON, 500 ms OFF)
            break;
        case Pattern::FAST_BLINK:
            interval = 100; // 5 Hz
            break;
        case Pattern::ERROR_BLINK:
            interval = 50;  // 10 Hz
            break;
        default:
            break;
    }

    if (interval > 0) {
        if (now - last_toggle >= interval) {
            last_toggle = now;
            state = !state;
        }
    }

    digitalWrite(pin, state ? HIGH : LOW);
}

void LedIndicator::update() {
    // Check if CAN activity burst overrides yellow LED
    if (millis() < can_burst_end_ms_) {
        digitalWrite(PIN_LED_YELLOW, HIGH);
    } else {
        applyPattern(PIN_LED_YELLOW, yellow_pattern_, yellow_last_toggle_ms_, yellow_state_);
    }

    applyPattern(PIN_LED_BLUE, blue_pattern_, blue_last_toggle_ms_, blue_state_);
}
