#include "led_indicator.h"

LedIndicator::LedIndicator()
    : yellow_pattern_(Pattern::OFF),
      blue_pattern_(Pattern::OFF),
      yellow_last_toggle_ms_(0),
      blue_last_toggle_ms_(0),
      yellow_state_(false),
      blue_state_(false),
      can_burst_start_ms_(0),
      can_burst_active_(false) {}

void LedIndicator::begin() {
    pinMode(PIN_LED_BLUE, OUTPUT);
    pinMode(PIN_LED_YELLOW, OUTPUT);
    digitalWrite(PIN_LED_BLUE, LOW);
    digitalWrite(PIN_LED_YELLOW, LOW);
}

void LedIndicator::setYellowPattern(Pattern pattern) {
    yellow_pattern_.store(pattern, std::memory_order_relaxed);
}

void LedIndicator::setBluePattern(Pattern pattern) {
    blue_pattern_.store(pattern, std::memory_order_relaxed);
}

void LedIndicator::triggerCanActivity() {
    can_burst_start_ms_.store(millis(), std::memory_order_relaxed);
    can_burst_active_.store(true, std::memory_order_release);
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
            interval = 100; // 5 Hz (100 ms ON, 100 ms OFF)
            break;
        case Pattern::BURST_BLINK: {
            // Double-flash heartbeat within a 1000 ms period
            uint32_t phase = now % 1000;
            state = (phase < 80) || (phase >= 160 && phase < 240);
            break;
        }
        case Pattern::ERROR_BLINK:
            interval = 50;  // 10 Hz rapid strobe
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
    uint32_t now = millis();
    Pattern y_pat = yellow_pattern_.load(std::memory_order_relaxed);
    Pattern b_pat = blue_pattern_.load(std::memory_order_relaxed);

    if (can_burst_active_.load(std::memory_order_acquire)) {
        uint32_t elapsed = now - can_burst_start_ms_.load(std::memory_order_relaxed);
        if (elapsed < 50) {
            // Invert base state briefly so CAN RX bursts are visible even when SOLID_ON
            bool burst_level = (y_pat == Pattern::SOLID_ON) ? LOW : HIGH;
            digitalWrite(PIN_LED_YELLOW, burst_level);
        } else {
            can_burst_active_.store(false, std::memory_order_release);
            applyPattern(PIN_LED_YELLOW, y_pat, yellow_last_toggle_ms_, yellow_state_);
        }
    } else {
        applyPattern(PIN_LED_YELLOW, y_pat, yellow_last_toggle_ms_, yellow_state_);
    }

    applyPattern(PIN_LED_BLUE, b_pat, blue_last_toggle_ms_, blue_state_);
}

