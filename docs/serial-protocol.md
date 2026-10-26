# GUI–STM32 serial protocol

This interface is implemented by the MATLAB GUI and the [NUCLEO-G474RE firmware](../firmware/README.md). The initial MCU backend generates **simulated measurements** over a real UART connection. Physical measurement and output drivers are not implemented yet.

## Transport

- USB virtual serial port bridging to the MCU UART; both ends must use the same baud rate.
- Initial setting: 115200 baud, 8 data bits, no parity, 1 stop bit, no flow control.
- ASCII, comma-separated fields, decimal point `.`; terminate every message with LF (`\n`). The parser also tolerates CR before LF.
- One command outstanding at a time. Command IDs are positive integers from 1 to 4,294,967,295 and increase during the app session. Reopen the app before exhausting the ID range.
- The MCU accepts at most 191 bytes before LF (including optional CR), using a 192-byte command buffer. Invalid or oversized lines are discarded through LF.
- Reply within 3 seconds. An unacknowledged command closes the GUI connection, with a best-effort STOP request. This is not a hardware shutdown guarantee.
- Never send incomplete lines. Keep telemetry within the GUI's conservative 96-byte-per-sample bandwidth budget; the decoder rejects complete lines longer than 512 characters.

## Commands

| Command | Meaning |
| --- | --- |
| `CFG,id,rail1_V,rail2_V,vref_V,iref_mA,clock_Hz,monitor_Hz,enable1,enable2` | Validate and store a complete configuration while idle; enable flags are 0 or 1. Current firmware applies settings to its simulator only |
| `START,id` | Begin timestamped monitoring with the acknowledged configuration |
| `STOP,id` | Stop monitoring; does not disable supplies |

Example:

```text
CFG,1,1.8,3.3,1.25,0.5,100000000,50,0,0
STATUS,SOURCE,SIMULATED
ACK,1
START,2
STATUS,SOURCE,SIMULATED
ACK,2
DATA,0,0.000,0.000,0.000,1.105
DATA,20,0.000,0.000,0.000,1.130
STOP,3
STATUS,SOURCE,SIMULATED
ACK,3
```

The example keeps both rails disabled. The current-reference field is **mA** on the wire; the GUI displays **uA** and converts it. Clock frequency is **Hz** on the wire and **MHz** in the GUI. The example clock setting is not a claim about implemented clock-generator capability.

## Replies and telemetry

| Message | Meaning |
| --- | --- |
| `ACK,id` | The matching command completed successfully |
| `ERR,id,code[,description]` | The command was rejected; description is optional and extra comma-separated detail is allowed |
| `DATA,timestamp_ms,rail1_V,rail2_V,dut_current_mA,analog_input_V` | One sample with exactly five finite numeric fields |
| `STATUS,text` | Status information; not a command acknowledgement |

Send the START acknowledgement **before** its first DATA line. Send STOP acknowledgement only after sampling/transmission has stopped. The GUI does not clear the previous capture until START succeeds.

Timestamp measurements at the MCU, not at PC receipt. Timestamps must be nonnegative and strictly increasing within a capture. They can reset for a new capture: the GUI subtracts the first timestamp and converts milliseconds to seconds. Duplicate, decreasing, malformed, complex, and non-finite values are rejected. No timestamp-wrap recovery or packet-retransmission mechanism is implemented.

Validate every CFG value against the actual module's supported ranges and operating conditions. Return ERR without applying a partial configuration if any field is invalid. A CFG acknowledgement means the command was applied, not that the requested analog accuracy has been independently verified.

For this simulator, rail setpoints are 0.8–3.3 V, voltage reference 0.2–3 V, current reference 0.1–1 mA, clock 1,000,000–200,000,000 integer Hz, and monitor rate 10–200 integer Hz. The link budget also requires `monitor_Hz * 96 * 10 <= baud * 0.7`, limiting the prebuilt 115200-baud image to 84 Hz. Voltage and current settings are stored with 1 mV / 1 uA resolution. The clock is a stored setpoint with no physical output. Future hardware drivers must enforce their actual limits.

## Source and lifecycle status

- `STATUS,SOURCE,SIMULATED`: all telemetry is synthetic. The MCU sends this at boot and before successful CFG, START, and STOP acknowledgements so a GUI that missed boot still learns the source. The GUI labels the header, capture, and CSV accordingly.
- `STATUS,SOURCE,HARDWARE`: reserved for a fully implemented measurement backend. The GUI labels it as hardware-reported, not calibrated or independently verified.
- A board that does not identify its source is labeled `STM32 serial (unverified source)`.
- `STATUS,READY,COMMUNICATION_TEST_ONLY`: boot message for this firmware.
- `STATUS,STOPPED,CAPTURE_LIMIT`: the MCU stopped at 50,000 samples or one hour; the GUI ends its capture when it receives this status.
- `STATUS,ERROR,...`: malformed command IDs, oversized lines, or RX loss, without a trustworthy request ID. A valid-ID command error uses ERR instead.

The GUI sends an idempotent STOP when connecting, then waits for its ACK before allowing configuration. START requires a prior valid CFG. CFG and duplicate START are rejected as BUSY while streaming. STOP can be repeated and preserves the last configuration. UART RX loss stops streaming and resynchronizes at the next LF. A TX failure stops streaming and clears the configured flag. Lost/damaged commands are not retransmitted automatically.

Only one capture is retained, capped at 50,000 samples. The GUI requests STOP at its host-side duration limit, buffer limit, or after five seconds without valid samples. The MCU independently stops after 50,000 samples or one hour. Desktop timing is not deterministic. The UART bridge does not reliably signal a host disconnect to the MCU, so streaming can continue until its limit if STOP is not delivered.

## Bring-up checks

1. Verify UART and LF framing in a serial terminal, then close that terminal so MATLAB can open the port.
2. Validate disabled-output CFG, matching ACK IDs, and ERR responses for unsupported settings.
3. Verify START ordering, units, timestamp monotonicity, and the simulated source label. Validate actual measured values separately when a hardware backend is added.
4. Verify STOP acknowledgement and confirm that stopping acquisition leaves output state unchanged.
5. Exercise missing ACK, malformed input, MCU reset, unplug/reconnect, and packet-loss behaviour.
6. Check link throughput at the intended monitoring rate. This text protocol is for low-rate monitoring, not 100 Mb/s DUT data streaming.
