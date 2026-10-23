# Draft GUI–STM32 serial protocol

This is a proposed interface implemented by the MATLAB GUI. It is not a description of existing STM32 firmware. The firmware team must implement and validate it before using hardware mode.

## Transport

- USB virtual serial port bridging to the MCU UART; both ends must use the same baud rate.
- Initial setting: 115200 baud, 8 data bits, no parity, 1 stop bit, no flow control.
- ASCII, comma-separated fields, decimal point `.`; terminate every message with LF (`\n`). The parser also tolerates CR before LF.
- One command outstanding at a time. Command IDs are positive integers and increase during the app session.
- Reply within 3 seconds. An unacknowledged command closes the GUI connection, with a best-effort STOP request. This is not a hardware shutdown guarantee.
- Never send incomplete lines. Keep telemetry within the GUI's conservative 96-byte-per-sample bandwidth budget; the decoder rejects complete lines longer than 512 characters.

## Commands

| Command | Meaning |
| --- | --- |
| `CFG,id,rail1_V,rail2_V,vref_V,iref_mA,clock_Hz,monitor_Hz,enable1,enable2` | Validate and apply a complete configuration while idle; enable flags are 0 or 1 |
| `START,id` | Begin timestamped monitoring with the acknowledged configuration |
| `STOP,id` | Stop monitoring; does not disable supplies |

Example:

```text
CFG,1,1.8,3.3,1.25,0.5,100000000,50,0,0
ACK,1
START,2
ACK,2
DATA,0,0.001,0.002,0.000,1.254
DATA,20,0.001,0.002,0.000,1.281
STOP,3
ACK,3
```

The example keeps both rails disabled. The current-reference field is **mA** on the wire; the GUI displays **uA** and converts it. Clock frequency is **Hz** on the wire and **MHz** in the GUI. The example clock setting is not a claim about implemented clock-generator capability.

## Replies and telemetry

| Message | Meaning |
| --- | --- |
| `ACK,id` | The matching command completed successfully |
| `ERR,id,code,description` | The command was rejected; extra comma-separated detail is allowed |
| `DATA,timestamp_ms,rail1_V,rail2_V,dut_current_mA,analog_input_V` | One sample with exactly five finite numeric fields |
| `STATUS,text` | Informational text for the event log; not a command acknowledgement |

Send the START acknowledgement **before** its first DATA line. Send STOP acknowledgement only after sampling/transmission has stopped. The GUI does not clear the previous capture until START succeeds.

Timestamp measurements at the MCU, not at PC receipt. Timestamps must be nonnegative and strictly increasing within a capture. They can reset for a new capture: the GUI subtracts the first timestamp and converts milliseconds to seconds. Duplicate, decreasing, malformed, complex, and non-finite values are rejected. No timestamp-wrap recovery or packet-retransmission mechanism is implemented.

Validate every CFG value against the actual module's supported ranges and operating conditions. Return ERR without applying a partial configuration if any field is invalid. A CFG acknowledgement means the command was applied, not that the requested analog accuracy has been independently verified.

Only one capture is retained, capped at 50,000 samples. The GUI requests STOP at its host-side duration limit, buffer limit, or after five seconds without valid samples. Desktop timing is not deterministic; firmware should enforce independent acquisition and fault limits.

## Bring-up checks

1. Verify UART and LF framing in a serial terminal, then close that terminal so MATLAB can open the port.
2. Validate disabled-output CFG, matching ACK IDs, and ERR responses for unsupported settings.
3. Verify START ordering, units, timestamp monotonicity, and actual measured values.
4. Verify STOP acknowledgement and confirm that stopping acquisition leaves output state unchanged.
5. Exercise missing ACK, malformed input, MCU reset, unplug/reconnect, and packet-loss behaviour.
6. Check link throughput at the intended monitoring rate. This text protocol is for low-rate monitoring, not 100 Mb/s DUT data streaming.
