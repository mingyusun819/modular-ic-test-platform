#include "platform_protocol.h"

#include <errno.h>
#include <math.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* This backend deliberately produces SIMULATED values. No DUT output GPIO,
 * ADC, DAC, supply, or clock-generator peripheral is configured here. */

static bool emit(PlatformProtocol *p, const char *format, ...)
{
    char output[PLATFORM_LINE_CAPACITY];
    va_list arguments;
    va_start(arguments, format);
    int length = vsnprintf(output, sizeof(output) - 1u, format, arguments);
    va_end(arguments);
    if (length < 0 || (size_t)length >= sizeof(output) - 1u) {
        p->streaming = false;
        p->configured = false;
        p->tx_errors++;
        return false;
    }
    output[length++] = '\n';
    if (!p->write(p->write_context, output, (size_t)length)) {
        p->streaming = false;
        p->configured = false;
        p->tx_errors++;
        return false;
    }
    return true;
}

static bool source_status(PlatformProtocol *p)
{
    return emit(p, "STATUS,SOURCE,SIMULATED");
}

static void error_reply(PlatformProtocol *p, uint32_t id, const char *code)
{
    (void)emit(p, "ERR,%lu,%s", (unsigned long)id, code);
}

static bool unsigned_integer(const char *text, uint32_t minimum,
                             uint32_t maximum, uint32_t *value)
{
    uint64_t result = 0;
    if (*text == '\0') return false;
    for (; *text != '\0'; ++text) {
        if (*text < '0' || *text > '9') return false;
        result = result * 10u + (uint32_t)(*text - '0');
        if (result > maximum) return false;
    }
    if (result < minimum) return false;
    *value = (uint32_t)result;
    return true;
}

static bool scaled_decimal(const char *text, double minimum, double maximum,
                           double scale, uint32_t *value)
{
    char *end = NULL;
    errno = 0;
    double parsed = strtod(text, &end);
    if (end == text || *end != '\0' || errno == ERANGE || !isfinite(parsed) ||
        parsed < minimum || parsed > maximum) return false;
    *value = (uint32_t)(parsed * scale + 0.5);
    return true;
}

static void handle_line(PlatformProtocol *p, uint32_t now_ms)
{
    char *fields[10];
    size_t count = 1;
    bool too_many = false;
    fields[0] = p->line;
    for (char *cursor = p->line; *cursor != '\0'; ++cursor) {
        if (*cursor == ',') {
            *cursor = '\0';
            if (count == 10u) {
                too_many = true;
                break;
            }
            fields[count++] = cursor + 1;
        }
    }
    uint32_t id = 0;
    if (count < 2u || !unsigned_integer(fields[1], 1u, UINT32_MAX, &id)) {
        (void)emit(p, "STATUS,ERROR,INVALID_COMMAND_ID");
        return;
    }
    if (too_many) {
        error_reply(p, id, "FORMAT");
        return;
    }
    if (strcmp(fields[0], "STOP") == 0) {
        if (count != 2u) {
            error_reply(p, id, "FORMAT");
            return;
        }
        p->streaming = false;
        if (source_status(p)) (void)emit(p, "ACK,%lu", (unsigned long)id);
        return;
    }
    if (strcmp(fields[0], "START") == 0) {
        if (count != 2u) {
            error_reply(p, id, "FORMAT");
        } else if (!p->configured) {
            error_reply(p, id, "NOT_CONFIGURED");
        } else if (p->streaming) {
            error_reply(p, id, "BUSY");
        } else if (source_status(p) && emit(p, "ACK,%lu", (unsigned long)id)) {
            /* No DATA can be sent before the successful START ACK. */
            p->start_ms = now_ms;
            p->next_ms = now_ms;
            p->samples = 0;
            p->streaming = true;
        }
        return;
    }
    if (strcmp(fields[0], "CFG") != 0) {
        error_reply(p, id, "UNKNOWN_COMMAND");
        return;
    }
    if (count != 10u) {
        error_reply(p, id, "FORMAT");
        return;
    }
    if (p->streaming) {
        error_reply(p, id, "BUSY");
        return;
    }
    PlatformConfig candidate = {0};
    uint32_t enable1 = 0, enable2 = 0;
    if (!scaled_decimal(fields[2], 0.8, 3.3, 1000, &candidate.rail1_mv) ||
        !scaled_decimal(fields[3], 0.8, 3.3, 1000, &candidate.rail2_mv) ||
        !scaled_decimal(fields[4], 0.2, 3.0, 1000, &candidate.vref_mv) ||
        !scaled_decimal(fields[5], 0.1, 1.0, 1000, &candidate.iref_ua) ||
        !unsigned_integer(fields[6], 1000000, 200000000, &candidate.clock_hz) ||
        !unsigned_integer(fields[7], 10, 200, &candidate.monitor_hz) ||
        !unsigned_integer(fields[8], 0, 1, &enable1) ||
        !unsigned_integer(fields[9], 0, 1, &enable2)) {
        error_reply(p, id, "RANGE_OR_NUMBER");
        return;
    }
    if ((uint64_t)candidate.monitor_hz * 96u * 10u * 10u > (uint64_t)p->baud * 7u) {
        error_reply(p, id, "MONITOR_RATE_EXCEEDS_UART_BUDGET");
        return;
    }
    candidate.enable1 = enable1 != 0;
    candidate.enable2 = enable2 != 0;
    /* Validate everything before committing any configuration. */
    p->config = candidate;
    p->configured = true;
    if (source_status(p)) (void)emit(p, "ACK,%lu", (unsigned long)id);
}

void platform_init(PlatformProtocol *p, PlatformWrite write, void *context, uint32_t baud)
{
    memset(p, 0, sizeof(*p));
    p->write = write;
    p->write_context = context;
    p->baud = baud;
    (void)source_status(p);
    (void)emit(p, "STATUS,READY,COMMUNICATION_TEST_ONLY");
}

void platform_rx_lost(PlatformProtocol *p)
{
    p->used = 0;
    p->discard_line = true;
    /* Stop monitoring on RX loss rather than accepting a truncated command. */
    p->streaming = false;
    (void)emit(p, "STATUS,ERROR,RX_LOSS_DISCARD_UNTIL_LF");
}

void platform_feed(PlatformProtocol *p, uint8_t byte, uint32_t now_ms)
{
    if (byte == '\n') {
        if (p->discard_line) {
            (void)emit(p, "STATUS,ERROR,INVALID_OR_OVERSIZE_LINE");
        } else if (p->used > 0u) {
            if (p->line[p->used - 1u] == '\r') p->used--;
            p->line[p->used] = '\0';
            if (p->used > 0u) handle_line(p, now_ms);
        }
        p->used = 0;
        p->discard_line = false;
        return;
    }
    if (p->discard_line) return;
    if (byte == 0 || (byte < 32u && byte != '\r') || byte > 126u ||
        p->used >= sizeof(p->line) - 1u) {
        p->used = 0;
        p->discard_line = true;
        return;
    }
    p->line[p->used++] = (char)byte;
}

static int32_t triangle(uint32_t milliseconds, uint32_t period, int32_t amplitude)
{
    int32_t phase = (int32_t)(milliseconds % period);
    int32_t half = (int32_t)(period / 2u);
    if (phase < half) return -amplitude + 2 * amplitude * phase / half;
    return amplitude - 2 * amplitude * (phase - half) / ((int32_t)period - half);
}

static void format_milli(char *destination, size_t capacity, int32_t value)
{
    uint32_t magnitude = (uint32_t)(value < 0 ? -(int64_t)value : value);
    (void)snprintf(destination, capacity, "%s%lu.%03lu", value < 0 ? "-" : "",
                   (unsigned long)(magnitude / 1000u), (unsigned long)(magnitude % 1000u));
}

void platform_poll(PlatformProtocol *p, uint32_t now_ms)
{
    if (!p->streaming) return;
    uint32_t elapsed = now_ms - p->start_ms; /* Wrap-safe for runs shorter than 2^32 ms. */
    if (elapsed >= PLATFORM_MAX_RUN_MS || p->samples >= PLATFORM_MAX_SAMPLES) {
        p->streaming = false;
        (void)emit(p, "STATUS,STOPPED,CAPTURE_LIMIT");
        return;
    }
    if ((int32_t)(now_ms - p->next_ms) < 0) return;
    const PlatformConfig *c = &p->config;
    int32_t rail1 = c->enable1 ? (int32_t)c->rail1_mv + triangle(elapsed, 1400, 4) : 0;
    int32_t rail2 = c->enable2 ? (int32_t)c->rail2_mv + triangle(elapsed, 1800, 5) : 0;
    int32_t current = (c->enable1 || c->enable2) ?
        (int32_t)c->iref_ua + triangle(elapsed, 1250, (int32_t)c->iref_ua / 12) : 0;
    int32_t input = (int32_t)c->vref_mv + triangle(elapsed, 500, 120) + triangle(elapsed, 333, 25);
    char v1[24], v2[24], current_ma[24], signal[24];
    format_milli(v1, sizeof(v1), rail1);
    format_milli(v2, sizeof(v2), rail2);
    format_milli(current_ma, sizeof(current_ma), current);
    format_milli(signal, sizeof(signal), input);
    if (!emit(p, "DATA,%lu,%s,%s,%s,%s", (unsigned long)elapsed, v1, v2, current_ma, signal)) return;
    p->samples++;
    /* Keep the requested average cadence; skip missed slots, never burst old samples. */
    uint64_t next_slot = ((uint64_t)elapsed * c->monitor_hz) / 1000u + 1u;
    p->next_ms = p->start_ms + (uint32_t)((next_slot * 1000u + c->monitor_hz - 1u) / c->monitor_hz);
}
