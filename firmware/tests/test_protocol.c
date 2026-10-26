#include "platform_protocol.h"

#include <assert.h>
#include <stdio.h>
#include <string.h>

typedef struct {
    char text[8192];
    size_t length;
    unsigned lines, data_lines;
    bool fail;
} Sink;

static bool capture(void *context, const char *data, size_t length)
{
    Sink *sink = context;
    if (sink->fail) return false;
    assert(length > 0 && data[length - 1] == '\n');
    assert(length < PLATFORM_LINE_CAPACITY);
    sink->lines++;
    if (strncmp(data, "DATA,", 5) == 0) sink->data_lines++;
    if (sink->length + length < sizeof(sink->text)) {
        memcpy(sink->text + sink->length, data, length);
        sink->length += length;
        sink->text[sink->length] = '\0';
    }
    return true;
}

static void clear(Sink *sink) { memset(sink, 0, sizeof(*sink)); }
static void command(PlatformProtocol *p, const char *text, uint32_t now)
{
    for (; *text; ++text) platform_feed(p, (uint8_t)*text, now);
}
static void setup(PlatformProtocol *p, Sink *sink)
{
    clear(sink);
    platform_init(p, capture, sink, 115200);
}
static void configure(PlatformProtocol *p)
{
    command(p, "CFG,1,1.8,3.3,1.25,0.5,100000000,50,1,1\n", 0);
    assert(p->configured);
}

static void test_gui_exchange(void)
{
    PlatformProtocol p;
    Sink sink;
    setup(&p, &sink);
    assert(strstr(sink.text, "STATUS,SOURCE,SIMULATED\n"));
    command(&p, "START,9\n", 0);
    assert(strstr(sink.text, "ERR,9,NOT_CONFIGURED\n"));
    configure(&p);
    assert(p.config.rail1_mv == 1800 && p.config.rail2_mv == 3300);
    assert(p.config.iref_ua == 500 && p.config.clock_hz == 100000000);
    clear(&sink);
    command(&p, "START,2\r\n", 1000);
    assert(p.streaming && sink.data_lines == 0);
    platform_poll(&p, 1000);
    assert(strcmp(sink.text, "STATUS,SOURCE,SIMULATED\nACK,2\n"
                            "DATA,0,1.796,3.295,0.459,1.105\n") == 0);
    platform_poll(&p, 1019);
    assert(sink.data_lines == 1);
    platform_poll(&p, 1020);
    assert(sink.data_lines == 2 && strstr(sink.text, "DATA,20,"));
    command(&p, "CFG,3,2,2,2,1,1000000,10,0,0\nSTART,4\n", 1030);
    assert(strstr(sink.text, "ERR,3,BUSY\n") && strstr(sink.text, "ERR,4,BUSY\n"));
    assert(p.config.rail1_mv == 1800 && p.streaming);
    command(&p, "STOP,5\nSTOP,6\n", 1040);
    assert(!p.streaming && strstr(sink.text, "ACK,5\n") && strstr(sink.text, "ACK,6\n"));
    clear(&sink);
    platform_poll(&p, 1060);
    assert(sink.length == 0);
}

static void test_rejections_are_atomic(void)
{
    const char *invalid[] = {
        "CFG,7,3.31,3.3,1.25,0.5,100000000,50,1,1\n",
        "CFG,7,0.79,3.3,1.25,0.5,100000000,50,1,1\n",
        "CFG,7,2,3.3,NaN,0.5,100000000,50,1,1\n",
        "CFG,7,2,3.3,1.25,Inf,100000000,50,1,1\n",
        "CFG,7,2,3.3,1.25,0.099,100000000,50,1,1\n",
        "CFG,7,2,3.3,1.25,0.5,200000001,50,1,1\n",
        "CFG,7,2,3.3,1.25,0.5,1e8,50,1,1\n",
        "CFG,7,2,3.3,1.25,0.5,100000000,50.5,1,1\n",
        "CFG,7,2,3.3,1.25,0.5,100000000,50,2,1\n",
        "CFG,7,2,3.3,1.25,0.5,100000000,50,1,\n",
        "CFG,7,2,3.3,1.25,0.5,100000000,50,1,1,extra\n",
        "CFG,7,2,3.3,1.25,0.5,100000000,50,1\n",
        "CFG,7,2,3.3,1.25,0.5,100000000,85,1,1\n",
        "CFG,7,2,3.3,1.25,0.5,100000000,9,1,1\n",
        "STOP,7,extra\n", "START,7,extra\n", "HELLO,7\n"
    };
    PlatformProtocol p;
    Sink sink;
    setup(&p, &sink);
    configure(&p);
    PlatformConfig saved = p.config;
    for (size_t i = 0; i < sizeof(invalid) / sizeof(invalid[0]); ++i) {
        clear(&sink);
        command(&p, invalid[i], 0);
        assert(strstr(sink.text, "ERR,7,"));
        assert(p.configured && !p.streaming);
        assert(memcmp(&saved, &p.config, sizeof(saved)) == 0);
    }
    command(&p, "CFG,8,8e-1,3.3,0.2,1,200000000,84,0,0\n", 0);
    assert(p.config.rail1_mv == 800 && p.config.monitor_hz == 84);
    clear(&sink);
    command(&p, "START,9\n", 0);
    platform_poll(&p, 0);
    assert(strstr(sink.text, "DATA,0,0.000,0.000,0.000,0.055\n"));
}

static void test_framing_and_rx_loss(void)
{
    PlatformProtocol p;
    Sink sink;
    setup(&p, &sink);
    clear(&sink);
    command(&p, "CFG,1,1.8,3.3,", 0);
    assert(!p.configured && sink.lines == 0);
    command(&p, "1.25,0.5,100000000,50,0,0\r\n", 0);
    assert(p.configured && strstr(sink.text, "ACK,1\n"));
    clear(&sink);
    const char *bad_ids[] = {"START,0\n", "STOP,4294967296\n", "STOP,1.5\n",
                             "STOP,-1\n", "STOP,\n", "START\n"};
    for (size_t i = 0; i < sizeof(bad_ids) / sizeof(bad_ids[0]); ++i)
        command(&p, bad_ids[i], 0);
    assert(!strstr(sink.text, "ACK,"));
    command(&p, "START,2", 0);
    platform_feed(&p, 0, 0);
    command(&p, "\n", 0);
    assert(!p.streaming);
    for (unsigned i = 0; i < 500; ++i) platform_feed(&p, 'X', 0);
    command(&p, "START,3\n", 0);
    assert(!p.streaming);
    command(&p, "START,4\n", 0);
    assert(p.streaming);
    command(&p, "ST", 0);
    platform_rx_lost(&p);
    command(&p, "OP,5\n", 0);
    assert(!p.streaming && !strstr(sink.text, "ACK,5\n"));
    command(&p, "STOP,4294967295\n", 0);
    assert(strstr(sink.text, "ACK,4294967295\n"));
}

static void test_cadence_wrap_and_limits(void)
{
    PlatformProtocol p;
    Sink sink;
    setup(&p, &sink);
    configure(&p);
    const uint32_t start = UINT32_MAX - 9u;
    command(&p, "START,2\n", start);
    clear(&sink);
    platform_poll(&p, start);
    platform_poll(&p, start + 20u);
    assert(sink.data_lines == 2 && strstr(sink.text, "DATA,20,"));
    platform_poll(&p, start + 1001u);
    platform_poll(&p, start + 1001u);
    assert(sink.data_lines == 3); /* No burst after a delayed main loop. */
    assert(p.next_ms == start + 1020u);
    platform_poll(&p, start + PLATFORM_MAX_RUN_MS);
    assert(!p.streaming && strstr(sink.text, "STOPPED,CAPTURE_LIMIT"));
    command(&p, "START,3\n", 0);
    clear(&sink);
    for (uint32_t t = 0; t <= PLATFORM_MAX_SAMPLES * 20u; t += 20u)
        platform_poll(&p, t);
    assert(!p.streaming && sink.data_lines == PLATFORM_MAX_SAMPLES);
    command(&p, "CFG,4,1.8,3.3,1.25,0.5,100000000,83,1,1\nSTART,5\n", 0);
    clear(&sink);
    for (uint32_t t = 0; t < 1000; ++t) platform_poll(&p, t);
    assert(sink.data_lines == 83); /* Fractional-ms rate doesn't drift to 12 ms. */
}

static void test_tx_failure_and_noise(void)
{
    PlatformProtocol p;
    Sink sink;
    setup(&p, &sink);
    configure(&p);
    sink.fail = true;
    command(&p, "START,2\n", 0);
    assert(!p.streaming && !p.configured && p.tx_errors == 1);
    clear(&sink);
    configure(&p);
    command(&p, "START,3\n", 0);
    sink.fail = true;
    platform_poll(&p, 0);
    assert(!p.streaming && !p.configured && p.samples == 0);
    clear(&sink);
    uint32_t state = 819;
    for (unsigned i = 0; i < 100000; ++i) {
        state ^= state << 13;
        state ^= state >> 17;
        state ^= state << 5;
        platform_feed(&p, (uint8_t)state, i);
        platform_poll(&p, i);
    }
    command(&p, "\nCFG,8,1.8,3.3,1.25,0.5,100000000,50,0,0\n", 100001);
    assert(p.configured && !p.streaming);
}

int main(void)
{
    test_gui_exchange();
    test_rejections_are_atomic();
    test_framing_and_rx_loss();
    test_cadence_wrap_and_limits();
    test_tx_failure_and_noise();
    puts("PASS: protocol, GUI exchange, atomic validation, framing, cadence, wrap, limits, TX/RX faults, noise");
    return 0;
}
