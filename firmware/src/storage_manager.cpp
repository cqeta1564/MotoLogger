#include "storage_manager.h"
#include <Preferences.h>
#include <stdlib.h>

static const char CSV_HEADER[] = 
    "timestamp_ms,lean_angle_deg,pitch_deg,accel_x_g,accel_y_g,accel_z_g,"
    "gyro_x_dps,gyro_y_dps,gyro_z_dps,v_bat,engine_rpm,vehicle_speed_kmh,"
    "throttle_pos_pct,coolant_temp_c,gear\n";

StorageManager::StorageManager()
    : spi_sd_(FSPI),
      spi_initialized_(false),
      is_mounted_(false),
      is_file_open_(false),
      current_session_idx_(0),
      records_written_(0),
      bytes_written_(0),
      last_flush_ms_(0),
      last_reconnect_ms_(0),
      write_errors_(0),
      buffer_head_(0),
      can_buffer_head_(0) {
    memset(current_filename_, 0, sizeof(current_filename_));
    memset(can_filename_, 0, sizeof(can_filename_));
}

bool StorageManager::begin() {
    last_reconnect_ms_ = millis();

    // 1. Initialize custom SPI bus once for ESP32-S3 MicroSD interface
    if (!spi_initialized_) {
        spi_sd_.begin(PIN_SD_SCK, PIN_SD_MISO, PIN_SD_MOSI, PIN_SD_CS);
        spi_initialized_ = true;
    }

    // 2. Mount SD card with high-speed clock
    if (!SD.begin(PIN_SD_CS, spi_sd_, SD_SPI_SPEED_MHZ * 1000000UL)) {
        is_mounted_.store(false, std::memory_order_release);
        is_file_open_.store(false, std::memory_order_release);
        return false;
    }
    is_mounted_.store(true, std::memory_order_release);

    // 3. Open next sequential session file (LOG_0001.CSV and CAN_0001.LOG)
    if (!openNextSessionFile()) {
        is_file_open_.store(false, std::memory_order_release);
        return false;
    }

    return true;
}

bool StorageManager::tryReconnect() {
    last_reconnect_ms_ = millis();

    // Cleanly close any stale file handles and unmount VFS before re-probing SD card
    if (log_file_) {
        log_file_.close();
    }
    if (can_file_) {
        can_file_.close();
    }
    SD.end();

    if (!spi_initialized_) {
        spi_sd_.begin(PIN_SD_SCK, PIN_SD_MISO, PIN_SD_MOSI, PIN_SD_CS);
        spi_initialized_ = true;
    }

    if (!SD.begin(PIN_SD_CS, spi_sd_, SD_SPI_SPEED_MHZ * 1000000UL)) {
        is_mounted_.store(false, std::memory_order_release);
        is_file_open_.store(false, std::memory_order_release);
        return false;
    }
    is_mounted_.store(true, std::memory_order_release);

    if (!openNextSessionFile()) {
        is_file_open_.store(false, std::memory_order_release);
        return false;
    }

    Serial.printf("\n[SD] MicroSD hot-plug mount successful! New session: %s\n", current_filename_);
    return true;
}

bool StorageManager::openNextSessionFile() {
    // Fast stepped / binary search for next unused session file (LOG_XXXX.CSV)
    // Minimizes blocking FAT32 SD.exists calls from thousands to < 12 lookups
    uint32_t low = 1;
    uint32_t high = 1;
    char test_name[32];

    snprintf(test_name, sizeof(test_name), "/LOG_%04lu.CSV", 1UL);
    if (!SD.exists(test_name)) {
        low = 1;
        high = 1;
    } else {
        uint32_t step = 10;
        high = 1;
        while (high < 9999) {
            high += step;
            if (high > 9999) high = 9999;
            snprintf(test_name, sizeof(test_name), "/LOG_%04lu.CSV", static_cast<unsigned long>(high));
            if (!SD.exists(test_name)) {
                break;
            }
            low = high;
            step *= 2;
        }

        while (low < high) {
            uint32_t mid = low + (high - low) / 2;
            snprintf(test_name, sizeof(test_name), "/LOG_%04lu.CSV", static_cast<unsigned long>(mid));
            if (SD.exists(test_name)) {
                low = mid + 1;
            } else {
                high = mid;
            }
        }
    }

    uint32_t session_idx = low;
    current_session_idx_.store(session_idx, std::memory_order_release);
    snprintf(current_filename_, sizeof(current_filename_), "/LOG_%04lu.CSV", static_cast<unsigned long>(session_idx));
    snprintf(can_filename_, sizeof(can_filename_), "/CAN_%04lu.LOG", static_cast<unsigned long>(session_idx));

    log_file_ = SD.open(current_filename_, FILE_WRITE);
    if (!log_file_) {
        return false;
    }

    // Write CSV header for MoTeC i2 / standard telemetry compatibility
    size_t header_len = strlen(CSV_HEADER);
    if (log_file_.write(reinterpret_cast<const uint8_t*>(CSV_HEADER), header_len) != header_len) {
        log_file_.close();
        return false;
    }
    log_file_.flush();

    // Open companion raw CAN log file
    can_file_ = SD.open(can_filename_, FILE_WRITE);

    buffer_head_ = 0;
    can_buffer_head_ = 0;
    last_flush_ms_ = millis();
    is_file_open_.store(true, std::memory_order_release);
    return true;
}

void StorageManager::commitBufferToFile() {
    if (!is_file_open_.load(std::memory_order_acquire) || buffer_head_ == 0) return;

    size_t written = log_file_.write(reinterpret_cast<const uint8_t*>(write_buffer_), buffer_head_);
    if (written == buffer_head_) {
        bytes_written_.fetch_add(static_cast<uint32_t>(written), std::memory_order_relaxed);
        buffer_head_ = 0;
    } else {
        write_errors_.fetch_add(1, std::memory_order_relaxed);
        Serial.printf("[SD] CSV write error: expected %u bytes, wrote %u\n",
                      static_cast<unsigned int>(buffer_head_), static_cast<unsigned int>(written));
        if (written == 0) {
            is_file_open_.store(false, std::memory_order_release);
            is_mounted_.store(false, std::memory_order_release);
        } else {
            bytes_written_.fetch_add(static_cast<uint32_t>(written), std::memory_order_relaxed);
            buffer_head_ = 0;
        }
    }
}

void StorageManager::commitCanBufferToFile() {
    if (!is_file_open_.load(std::memory_order_acquire) || !can_file_ || can_buffer_head_ == 0) return;

    size_t written = can_file_.write(reinterpret_cast<const uint8_t*>(can_write_buffer_), can_buffer_head_);
    if (written == can_buffer_head_) {
        can_buffer_head_ = 0;
    } else {
        write_errors_.fetch_add(1, std::memory_order_relaxed);
        Serial.printf("[SD] CAN write error: expected %u bytes, wrote %u\n",
                      static_cast<unsigned int>(can_buffer_head_), static_cast<unsigned int>(written));
        if (written == 0) {
            is_file_open_.store(false, std::memory_order_release);
            is_mounted_.store(false, std::memory_order_release);
        } else {
            can_buffer_head_ = 0;
        }
    }
}

bool StorageManager::logTelemetry(const TelemetryRecord& r) {
    if (!is_file_open_.load(std::memory_order_acquire)) return false;

    char line[160];
    int len = snprintf(line, sizeof(line),
        "%lu,%.2f,%.2f,%.3f,%.3f,%.3f,%.2f,%.2f,%.2f,%.2f,%u,%u,%.1f,%d,%d\n",
        static_cast<unsigned long>(r.timestamp_ms),
        r.lean_angle_deg,
        r.pitch_deg,
        r.accel_x_g,
        r.accel_y_g,
        r.accel_z_g,
        r.gyro_x_dps,
        r.gyro_y_dps,
        r.gyro_z_dps,
        r.battery_voltage,
        r.engine_rpm,
        r.vehicle_speed_kmh,
        r.throttle_pos_pct,
        r.coolant_temp_c,
        r.gear
    );

    if (len <= 0 || static_cast<size_t>(len) >= sizeof(line)) return false;

    // Commit current RAM batch if this line would overflow the 32 KB buffer
    if (buffer_head_ + static_cast<size_t>(len) >= sizeof(write_buffer_)) {
        commitBufferToFile();
    }

    if (buffer_head_ + static_cast<size_t>(len) < sizeof(write_buffer_)) {
        memcpy(&write_buffer_[buffer_head_], line, static_cast<size_t>(len));
        buffer_head_ += static_cast<size_t>(len);
        records_written_.fetch_add(1, std::memory_order_relaxed);
        return true;
    }

    return false;
}

bool StorageManager::logRawCan(const CanFrame& frame) {
    if (!is_file_open_.load(std::memory_order_acquire) || !can_file_) return false;

    char line[128];
    uint8_t dlc = (frame.dlc > 8) ? 8 : frame.dlc;
    int len = snprintf(line, sizeof(line), "#CAN,%llu,0x%03lX,%u",
                       static_cast<unsigned long long>(frame.timestamp_us),
                       static_cast<unsigned long>(frame.id),
                       static_cast<unsigned int>(dlc));

    if (len <= 0 || static_cast<size_t>(len) >= sizeof(line)) return false;

    for (uint8_t i = 0; i < dlc && len < static_cast<int>(sizeof(line)) - 5; i++) {
        len += snprintf(line + len, sizeof(line) - static_cast<size_t>(len), ",%02X", frame.data[i]);
    }
    if (len < static_cast<int>(sizeof(line)) - 2) {
        line[len++] = '\n';
        line[len] = '\0';
    } else {
        return false;
    }

    // Commit current CAN RAM batch if this line would overflow the 16 KB buffer
    if (can_buffer_head_ + static_cast<size_t>(len) >= sizeof(can_write_buffer_)) {
        commitCanBufferToFile();
    }

    if (can_buffer_head_ + static_cast<size_t>(len) < sizeof(can_write_buffer_)) {
        memcpy(&can_write_buffer_[can_buffer_head_], line, static_cast<size_t>(len));
        can_buffer_head_ += static_cast<size_t>(len);
        return true;
    }

    return false;
}

void StorageManager::update() {
    uint32_t now = millis();

    // If SD card is offline, attempt auto-reconnect every 3000 ms
    if (!is_file_open_.load(std::memory_order_acquire)) {
        if (now - last_reconnect_ms_ >= 3000) {
            last_reconnect_ms_ = now;
            tryReconnect();
        }
        return;
    }

    // Periodically flush RAM buffers to physical flash every 1000 ms
    if (now - last_flush_ms_ >= 1000) {
        last_flush_ms_ = now;
        flush();
    }
}

void StorageManager::flush() {
    if (!is_file_open_.load(std::memory_order_acquire)) return;
    commitBufferToFile();
    commitCanBufferToFile();
    if (is_file_open_.load(std::memory_order_acquire)) {
        log_file_.flush();
        if (can_file_) {
            can_file_.flush();
        }
    }
}

void StorageManager::close() {
    if (is_file_open_.load(std::memory_order_acquire)) {
        flush();
        log_file_.close();
        if (can_file_) {
            can_file_.close();
        }
        is_file_open_.store(false, std::memory_order_release);
    }
    if (is_mounted_.load(std::memory_order_acquire)) {
        SD.end();
        is_mounted_.store(false, std::memory_order_release);
    }
}

uint32_t StorageManager::getLastSyncedSessionIndex() const {
    uint32_t last_idx = 0;
    Preferences prefs;
    if (prefs.begin("motologger", true)) {
        last_idx = prefs.getUInt("last_sync", 0);
        prefs.end();
    }
    return last_idx;
}

void StorageManager::acknowledgeSessionSynced(const char* log_name) {
    uint32_t synced_idx = current_session_idx_.load(std::memory_order_relaxed);
    if (log_name) {
        // Parse index from e.g. "LOG_0005.CSV" or "/LOG_0005.CSV"
        const char* p = log_name;
        while (*p && (*p < '0' || *p > '9')) p++;
        if (*p) {
            uint32_t parsed = static_cast<uint32_t>(strtoul(p, nullptr, 10));
            if (parsed > 0) synced_idx = parsed;
        }
    }

    Preferences prefs;
    if (prefs.begin("motologger", false)) {
        uint32_t prev = prefs.getUInt("last_sync", 0);
        if (synced_idx > prev) {
            prefs.putUInt("last_sync", synced_idx);
        }
        prefs.end();
    }
}

