#pragma once

#include <stddef.h>
#include <stdint.h>
#include <atomic>
#include <type_traits>

/**
 * @file ring_buffer.h
 * @brief Lock-free, Single-Producer Single-Consumer (SPSC) Ring Buffer.
 *        Ideal for decoupling high-rate ISR / Producer tasks from block-writing consumers.
 */
template <typename T, size_t Capacity>
class RingBuffer {
    static_assert((Capacity & (Capacity - 1)) == 0, "Capacity must be a power of 2 for fast masking!");

public:
    RingBuffer() : head_(0), tail_(0), drop_count_(0) {}

    bool push(const T& item) {
        const size_t current_head = head_.load(std::memory_order_relaxed);
        const size_t current_tail = tail_.load(std::memory_order_acquire);

        if ((current_head - current_tail) >= Capacity) {
            drop_count_.fetch_add(1, std::memory_order_relaxed);
            return false; // Buffer full
        }

        buffer_[current_head & BufferMask] = item;
        head_.store(current_head + 1, std::memory_order_release);
        return true;
    }

    bool pop(T& item) {
        const size_t current_tail = tail_.load(std::memory_order_relaxed);
        const size_t current_head = head_.load(std::memory_order_acquire);

        if (current_tail == current_head) {
            return false; // Buffer empty
        }

        item = buffer_[current_tail & BufferMask];
        tail_.store(current_tail + 1, std::memory_order_release);
        return true;
    }

    bool isEmpty() const {
        return head_.load(std::memory_order_acquire) == tail_.load(std::memory_order_acquire);
    }

    size_t available() const {
        const size_t h = head_.load(std::memory_order_acquire);
        const size_t t = tail_.load(std::memory_order_acquire);
        return (h >= t) ? (h - t) : 0;
    }

    size_t getDropCount() const {
        return drop_count_.load(std::memory_order_relaxed);
    }

    void reset() {
        head_.store(0, std::memory_order_relaxed);
        tail_.store(0, std::memory_order_relaxed);
        drop_count_.store(0, std::memory_order_relaxed);
    }

private:
    static constexpr size_t BufferMask = Capacity - 1;
    T buffer_[Capacity];
    std::atomic<size_t> head_;
    std::atomic<size_t> tail_;
    std::atomic<size_t> drop_count_;
};
