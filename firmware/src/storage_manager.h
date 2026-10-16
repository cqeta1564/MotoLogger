#pragma once

#include <Arduino.h>
#include <SPI.h>
#include <SD.h>
#include <atomic>
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
    bool tryReconnect();
    void update();
    bool logTelemetry(const TelemetryRecord& record);
    bool logRawCan(const CanFrame& frame);
    void flush();
    void close();

    bool isReady() const {
        return is_mounted_.load(std::memory_order_acquire) &&
               is_file_open_.load(std::memory_order_acquire);
    }
    uint32_t getRecordsWritten() const { return records_written_.load(std::memory_order_relaxed); }
    uint32_t getBytesWritten() const { return bytes_written_.load(std::memory_order_relaxed); }
    uint32_t getWriteErrors() const { return write_errors_.load(std::memory_order_relaxed); }
    uint32_t getCurrentSessionIndex() const { return current_session_idx_.load(std::memory_order_relaxed); }
    uint32_t getLastSyncedSessionIndex() const;
    void acknowledgeSessionSynced(const char* log_name);
    void markSessionSynced(const char* log_name);

    // MicroSD Offline Session Log BLE Synchronization
    size_t getUnsyncedSessionFiles(char* out_buffer, size_t max_len, uint8_t& out_count);
    bool openStreamingFile(const char* filename);
    bool readStreamingChunk(uint8_t* out_buffer, size_t max_len, size_t& bytes_read, bool& is_eof);
    void closeStreamingFile();
    bool isStreamingOpen() const { return is_streaming_open_; }

    const char* getCurrentFileName() const { return current_filename_; }
    const char* getCanFileName() const { return can_filename_; }

private:
    SPIClass spi_sd_;
    File log_file_;
    File can_file_;
    File streaming_file_;
    SemaphoreHandle_t sd_mutex_;
    bool spi_initialized_;
    bool is_streaming_open_;
    std::atomic<bool> is_mounted_;
    std::atomic<bool> is_file_open_;
    std::atomic<uint32_t> current_session_idx_;
    char current_filename_[32];
    char can_filename_[32];
    char streaming_filename_[32];

    std::atomic<uint32_t> records_written_;
    std::atomic<uint32_t> bytes_written_;
    uint32_t last_flush_ms_;
    uint32_t last_reconnect_ms_;
    std::atomic<uint32_t> write_errors_;

    // 32 KB RAM buffer for CSV batch writes
    char write_buffer_[SD_LOG_BUFFER_SIZE];
    size_t buffer_head_;

    // 16 KB RAM buffer for raw CAN batch writes
    static constexpr size_t CAN_LOG_BUFFER_SIZE = 16384;
    char can_write_buffer_[CAN_LOG_BUFFER_SIZE];
    size_t can_buffer_head_;

    bool openNextSessionFile();
    void commitBufferToFile();
    void commitCanBufferToFile();
};

