#ifndef PLATFORM_PROTOCOL_H
#define PLATFORM_PROTOCOL_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define PLATFORM_LINE_CAPACITY 192u
#define PLATFORM_MAX_SAMPLES 50000u
#define PLATFORM_MAX_RUN_MS 3600000u

typedef struct {
    uint32_t rail1_mv;
    uint32_t rail2_mv;
    uint32_t vref_mv;
    uint32_t iref_ua;
    uint32_t clock_hz;
    uint32_t monitor_hz;
    bool enable1;
    bool enable2;
} PlatformConfig;

/* Callback must transmit the whole line in order, or return false. */
typedef bool (*PlatformWrite)(void *context, const char *data, size_t length);

typedef struct {
    PlatformConfig config;
    PlatformWrite write;
    void *write_context;
    uint32_t baud;
    uint32_t start_ms;
    uint32_t next_ms;
    uint32_t samples;
    uint32_t tx_errors;
    bool configured;
    bool streaming;
    bool discard_line;
    size_t used;
    char line[PLATFORM_LINE_CAPACITY];
} PlatformProtocol;

void platform_init(PlatformProtocol *p, PlatformWrite write, void *context, uint32_t baud);
void platform_feed(PlatformProtocol *p, uint8_t byte, uint32_t now_ms);
void platform_poll(PlatformProtocol *p, uint32_t now_ms);
/* Use after a UART overrun/ring overflow. Resynchronize at the next LF. */
void platform_rx_lost(PlatformProtocol *p);

#endif
