#pragma once

#include <Arduino.h>
#include <SPI.h>
#include <SD.h>
#include "config.h"
#include "types.h"
#include "ring_buffer.h"

/**
 * @file storage_manager.h
 * @brief High-speed MicroSD logging manager using buffered block writes
 *        to eliminate SD latency spikes and protect against frame loss.
 */
class StorageManager {
public:
    StorageManager();
    bool begin();
    void update();
    bool logTelemetry(const TelemetryRecord& record);
    bool logRawCan(const CanFrame& frame);
    void flush();
    void close();

    bool isReady() const { return is_mounted_ && is_file_open_; }
    uint32_t getRecordsWritten() const { return records_written_; }
    uint32_t getBytesWritten() const { return bytes_written_; }
    const char* getCurrentFileName() const { return current_filename_; }

private:
    SPIClass spi_sd_;
    File log_file_;
    bool is_mounted_;
    bool is_file_open_;
    char current_filename_[32];

    uint32_t records_written_;
    uint32_t bytes_written_;
    uint32_t last_flush_ms_;

    // 32 KB RAM buffer for batch writes
    char write_buffer_[SD_LOG_BUFFER_SIZE];
    size_t buffer_head_;

    bool openNextSessionFile();
    void commitBufferToFile();
};
