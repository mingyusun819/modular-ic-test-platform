# MATLAB GUI

`ModularICTestApp.m` is a self-contained native MATLAB desktop app with graphs and user inputs. It starts in **offline demo mode**, so you can try it without an STM32 board.

## Run it

Download this repository, open MATLAB, and set the Current Folder to `matlab/`. Run:

```matlab
app = ModularICTestApp;
```

Alternatively, download only `ModularICTestApp.m`, put it in your Current Folder, and run the same command. The app has no other source-file dependencies.

1. Leave **Mode** set to **Demo (offline)** and click **Connect**.
2. Enter the desired setpoints, then click **Apply settings**.
3. Click **Start new capture**. The plots and numeric displays update while the capture runs.
4. Click **Stop capture**, or let the duration expire.
5. Use **Export CSV** to save the capture. Starting another capture replaces the retained data.

Scroll the settings column to reach all controls; Start, Stop, Export, and Clear stay visible. Closing the window releases the serial connection and removes its timer.

## Graphs and controls

| Area | Included |
| --- | --- |
| Graphs | Rail 1 and Rail 2 voltages, DUT current, analog-input waveform, analog-input AC spectrum |
| Live readouts | Latest values with V and mA units |
| Power | Two supply setpoints and individual output-enable checkboxes |
| Stimulus | Voltage reference, current reference, and clock-frequency setpoints |
| Capture | Monitor rate, duration, and visible time window |
| Connection | Demo/serial mode, available serial ports, baud rate, refresh, connect/disconnect |
| Data | Start/stop, CSV export, clear plots, source labels, and event log |

The input ranges are initial GUI limits, not verified hardware capabilities. The clock field accepts 1–200 MHz as a provisional configuration range. The chosen clock generator and firmware must enforce the actual supported range.

## Demo behaviour

Demo data is explicitly labeled in the window, CSV filename, and CSV `Source` column. Rail setpoints and output enables affect simulated rail readings. Current-reference and voltage-reference inputs affect the simulated current and waveform baseline. The waveform contains 2 Hz and 3 Hz tones plus noise. The clock value is stored as a setpoint; demo mode does **not** simulate a 100 MHz signal or a physical DUT.

The spectrum removes DC, resamples the displayed time segment onto a uniform grid, applies a Hann window, and calculates a one-sided peak-amplitude spectrum using base MATLAB `fft`. It uses at most 2,048 samples and needs at least 16. This is a monitoring display, not a calibrated spectrum analyzer. Irregular timestamps and missing packets can distort its result.

## Connecting the STM32

The repository includes matching [NUCLEO-G474RE firmware and flashing instructions](../firmware/README.md). It implements the [communication protocol](../docs/serial-protocol.md) over ST-LINK's virtual COM port. This initial firmware sends **MCU-generated simulated measurements** to test the real serial connection; physical ADC and output drivers are not implemented yet. The GUI header and CSV identify `STM32 serial (simulated)` captures. A device without a source declaration is labeled `unverified source`.

1. Flash `firmware/prebuilt/nucleo_g474re_gui.bin` at `0x08000000` using STM32CubeProgrammer, then reset the board.
2. Stop and disconnect demo mode, select **STM32 serial**, refresh ports, and select the board's port and matching baud rate.
3. Use **115200 baud** and **50 Hz** for the prebuilt image. Connect and wait for the initial STOP acknowledgement. Supply-enable checkboxes start unchecked when switching to serial mode; check them to see nonzero simulated rails.
4. Configure values and click **Apply settings**. The app enables Start only after the MCU acknowledges the settings.
5. Start a capture; MCU-generated data populates the graphs after the START acknowledgement.

Settings are locked while acquiring or waiting for a reply. Replies are matched to request IDs; command timeouts close the connection. Invalid/non-finite packets and non-increasing timestamps are discarded and logged. Five seconds without valid data triggers a stop request. Connection errors do not prove the hardware has stopped or that supplies are off.

**Stop capture stops acquisition, not power outputs.** To request disabled supplies while connected, stop acquisition, uncheck both outputs, apply, and wait for the acknowledgement. Firmware must enforce its own electrical limits and fault handling.

The monitor rate is 10–200 Hz, separate from ADC conversion rate and high-speed DUT interfaces. At 115,200 baud, the GUI permits up to 84 Hz using a conservative 96-byte packet budget and 70% link utilization. Higher rates require rebuilding the firmware with a matching faster UART setting; changing the GUI baud alone does not reconfigure the MCU. Use embedded acquisition/buffering for high-speed signals.

Each capture retains up to 50,000 samples and stops when that limit or the requested duration is reached. Export is available when acquisition is stopped. The CSV columns are `Time_s`, `Rail1_V`, `Rail2_V`, `DUTCurrent_mA`, `AnalogInput_V`, and `Source`. In serial mode, time is relative to the first accepted device timestamp.

## Editing and requirements

- Designed for MATLAB R2021a or later with desktop graphics support.
- No add-on toolboxes, Simulink, or STM32 support package are used by the GUI.
- This is an editable **programmatic `.m` app**, not an App Designer `.mlapp` drag-and-drop document. Edit `buildUI` to change its layout. It uses the same native UI components, including `uifigure`, `uigridlayout`, and `uiaxes`.
- `app.getData()` returns a table copy of the retained capture for further MATLAB analysis.

## Validation

MATLAB is not installed in the development environment used to create this app. The source was checked with the MISS_HIT MATLAB parser/linter targeting R2021a; the GUI has **not** been run or visually verified in MATLAB, and physical serial communication has **not** been tested.

Run the included parser, spectrum, and demo-lifecycle tests in MATLAB:

```matlab
results = runtests('tests');
assertSuccess(results);
```

The demo test opens a hidden UI, connects, applies settings, collects simulated data, stops, checks data retention, and verifies timer cleanup. The spectrum tests check frequency and amplitude against known signals. The firmware has passed ARM compilation and native host protocol tests. Serial integration still needs board testing, including rejected settings, missing ACKs, malformed packets, unplug/reconnect, and MCU resets.

With the GUI and other serial programs closed, test the flashed board directly using its actual port:

```matlab
report = testSTM32Link("COM5");
```

This optional hardware test checks command acknowledgements, rejected settings, telemetry, simulated source disclosure, increasing timestamps, and STOP ordering. It is separate from `runtests('tests')` and has not been run on a board here.

## API references

- [Programmatic grid layouts](https://www.mathworks.com/help/matlab/ref/uigridlayout.html)
- [Serial port connections](https://www.mathworks.com/help/matlab/ref/serialport.html)
- [Serial callbacks](https://www.mathworks.com/help/matlab/ref/serialport.configurecallback.html)
- [MATLAB timers](https://www.mathworks.com/help/matlab/ref/timer.html)
