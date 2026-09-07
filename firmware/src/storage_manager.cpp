#include "storage_manager.h"

static const char CSV_HEADER[] = 
    "timestamp_ms,lean_angle_deg,pitch_deg,accel_x_g,accel_y_g,accel_z_g,"
    "gyro_x_dps,gyro_y_dps,gyro_z_dps,v_bat,engine_rpm,vehicle_speed_kmh,"
    "throttle_pos_pct,coolant_temp_c,gear\n";

StorageManager::StorageManager()
    : spi_sd_(FSPI),
      is_mounted_(false),
      is_file_open_(false),
      records_written_(0),
      bytes_written_(0),
      last_flush_ms_(0),
      buffer_head_(0) {
    memset(current_filename_, 0, sizeof(current_filename_));
}

bool StorageManager::begin() {
    // 1. Initialize custom SPI bus for ESP32-S3 MicroSD interface
    spi_sd_.begin(PIN_SD_SCK, PIN_SD_MISO, PIN_SD_MOSI, PIN_SD_CS);

    // 2. Mount SD card with high-speed clock
    if (!SD.begin(PIN_SD_CS, spi_sd_, SD_SPI_SPEED_MHZ * 1000000)) {
        return false;
    }
    is_mounted_ = true;

    // 3. Open next sequential session file (LOG_0001.CSV)
    if (!openNextSessionFile()) {
        return false;
    }

    return true;
}

bool StorageManager::openNextSessionFile() {
    for (uint32_t i = 1; i <= 9999; i++) {
        snprintf(current_filename_, sizeof(current_filename_), "/LOG_%04u.CSV", i);
        if (!SD.exists(current_filename_)) {
            break;
        }
    }

    log_file_ = SD.open(current_filename_, FILE_WRITE);
    if (!log_file_) {
        return false;
    }

    // Write CSV header
    size_t header_len = strlen(CSV_HEADER);
    log_file_.write(reinterpret_cast<const uint8_t*>(CSV_HEADER), header_len);
    log_file_.flush();

    is_file_open_ = true;
    last_flush_ms_ = millis();
    return true;
}

void StorageManager::commitBufferToFile() {
    if (!is_file_open_ || buffer_head_ == 0) return;

    size_t written = log_file_.write(reinterpret_cast<const uint8_t*>(write_buffer_), buffer_head_);
    bytes_written_ += written;
    buffer_head_ = 0;
}

bool StorageManager::logTelemetry(const TelemetryRecord& r) {
    if (!is_file_open_) return false;

    char line[160];
    int len = snprintf(line, sizeof(line),
        "%lu,%.2f,%.2f,%.3f,%.3f,%.3f,%.2f,%.2f,%.2f,%.2f,%u,%u,%.1f,%d,%d\n",
        r.timestamp_ms,
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

    if (len <= 0) return false;

    // Check if line fits in the RAM batch buffer
    if (buffer_head_ + len >= sizeof(write_buffer_)) {
        commitBufferToFile();
    }

    memcpy(&write_buffer_[buffer_head_], line, len);
    buffer_head_ += len;
    records_written_++;

    return true;
}

bool StorageManager::logRawCan(const CanFrame& frame) {
    if (!is_file_open_) return false;

    char line[128];
    int len = snprintf(line, sizeof(line),
        "#CAN,%llu,0x%03X,%d,%02X,%02X,%02X,%02X,%02X,%02X,%02X,%02X\n",
        frame.timestamp_us,
        frame.id,
        frame.dlc,
        frame.data[0], frame.data[1], frame.data[2], frame.data[3],
        frame.data[4], frame.data[5], frame.data[6], frame.data[7]
    );

    if (len <= 0) return false;

    if (buffer_head_ + len >= sizeof(write_buffer_)) {
        commitBufferToFile();
    }

    memcpy(&write_buffer_[buffer_head_], line, len);
    buffer_head_ += len;

    return true;
}

void StorageManager::update() {
    uint32_t now = millis();
    // Flush buffer to disk every 1000 ms to ensure continuous safety
    if (now - last_flush_ms_ >= 1000) {
        last_flush_ms_ = now;
        flush();
    }
}

void StorageManager::flush() {
    if (!is_file_open_) return;
    commitBufferToFile();
    log_file_.flush();
}

void StorageManager::close() {
    if (is_file_open_) {
        flush();
        log_file_.close();
        is_file_open_ = false;
    }
}
