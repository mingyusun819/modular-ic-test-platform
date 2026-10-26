# NUCLEO-G474RE firmware for the MATLAB GUI

This firmware runs on the **NUCLEO-G474RE (STM32G474RET6)** and communicates with `matlab/ModularICTestApp.m` through the board's onboard ST-LINK virtual COM port. It implements the GUI's `CFG`, `START`, `STOP`, `ACK`, `ERR`, and timestamped `DATA` messages.

**This first version tests real USB/UART communication using simulated measurements generated on the MCU.** The GUI labels these captures `STM32 serial (simulated)`. Setpoints affect the synthetic data; there are no ADC measurements, programmable power outputs, analog-reference outputs, or DUT clock output yet. The 1–200 MHz clock field is stored only. No external DUT hardware is needed for this test.

## Flash the included image

You do not need PlatformIO to use the prebuilt image.

1. Download the repository ZIP (GitHub **Code > Download ZIP**) and extract it. Use the updated MATLAB files from this version too.
2. Connect the NUCLEO-G474RE's **ST-LINK USB connector** to your PC with a data-capable USB cable. Keep the board's factory jumper/solder-bridge configuration.
3. Install/open [STM32CubeProgrammer](https://www.st.com/en/development-tools/stm32cubeprog.html). Select **ST-LINK**, use **SWD**, and click **Connect**.
4. Open [`prebuilt/nucleo_g474re_gui.bin`](prebuilt/nucleo_g474re_gui.bin). Set the start address to **`0x08000000`**. Program the image and verify it. This replaces the board's existing application.
5. Disconnect the programmer and press the board's **RESET** button, or use the programmer's run/reset control. Keep USB attached. The green user LED is off while idle and on while streaming.

The `.hex` file in the same folder is an alternative with the flash address embedded. Both files contain the same application. Build versions, sizes, checksums, and validation limits are in [`prebuilt/BUILD_INFO.md`](prebuilt/BUILD_INFO.md).

## Connect the GUI

In MATLAB R2021a or later, set the Current Folder to the repository's `matlab/` folder and run:

```matlab
app = ModularICTestApp;
```

1. Select **STM32 serial** and click **Refresh ports**. Select the ST-LINK virtual COM port (`COM...` on Windows; typically `/dev/ttyACM...` on Linux or `/dev/cu.usbmodem...` on macOS).
2. Select **115200** baud and click **Connect**. The GUI first sends STOP to recover a board left streaming by an earlier connection. Wait for its acknowledgement.
3. Use a **50 Hz** monitor rate. Choose setpoints, and check the two rail-enable boxes if you want nonzero simulated rail readings. Click **Apply settings** and wait for `ACK`.
4. Click **Start new capture**. All four plots receive MCU-generated data. Change setpoints by stopping, editing, applying, and starting another capture.
5. Click **Stop capture** and **Export CSV** when finished. The header and CSV source identify the measurements as simulated.

At the default baud rate, supported monitor rates are **10–84 Hz**. The GUI allows higher rates at faster baud settings, but **this prebuilt image always uses 115200**. To change it, rebuild with a different `PLATFORM_UART_BAUD` and set MATLAB to match.

## UART and MCU configuration

| Item | Setting |
| --- | --- |
| MCU | STM32G474RET6, Cortex-M4F |
| CPU clock | Internal HSI, 16 MHz; PLL unused |
| Serial peripheral | **LPUART1** |
| MCU TX / RX | **PA2 / PA3**, alternate function **AF12** |
| Host bridge | Onboard STLINK-V3E virtual COM port |
| UART framing | 115200 baud, 8 data bits, no parity, 1 stop bit, no flow control |
| Factory VCP bridges | SB17 and SB23 ON; SB18, SB22, SB12, SB20 OFF |
| User LED | PA5 / LD2, on during streaming |
| Timebase | 1 ms SysTick; elapsed timestamps reset per capture |

These VCP pins use **LPUART1** on this board. Do not copy USART2 initialization from a different Nucleo model. The MCU itself is not implementing USB CDC; ST-LINK supplies the USB bridge. See [ST UM2505, virtual COM port configuration](https://www.st.com/resource/en/user_manual/um2505-stm32g4-nucleo64-boards-mb1367-stmicroelectronics.pdf).

## Build from source

The project uses **STM32Cube HAL C**, built with PlatformIO. PlatformIO downloads the pinned STM32CubeG4 framework, ARM compiler, startup file, and linker script; no Arduino runtime is used.

Install PlatformIO Core or the PlatformIO extension for VS Code. Open `firmware/` as the project, or run from that directory:

```sh
pio run
pio run --target upload
```

The upload command programs a connected board through ST-LINK. The result of a build is `.pio/build/nucleo_g474re/firmware.bin` and `firmware.elf`. Close serial terminals before opening the GUI.

| Source | Responsibility |
| --- | --- |
| `src/main.c` | Clock, LED, LPUART1, IRQ handlers, RX ring, main loop |
| `src/platform_protocol.c` | CSV parsing, validation, command state, synthetic telemetry |
| `include/platform_protocol.h` | Configuration structure and HAL-independent API |
| `platformio.ini` | Board, framework, toolchain, baud rate, upload settings |
| `tests/test_protocol.c` | Native host tests for protocol and failure paths |

For a CubeIDE workflow, create a **STM32G474RET6 C project** using STM32CubeG4, copy the two `.c` files into `Core/Src` and the header into `Core/Inc`, and enable the HAL UART/RCC/GPIO/PWR modules. This `main.c` supplies its own initialization, `HAL_UART_MspInit`, `SysTick_Handler`, and `LPUART1_IRQHandler`; remove/exclude duplicate generated definitions before building. Keep the generated startup, system file, and correct STM32G474RE linker script. This repository contains a verified PlatformIO build; a CubeIDE project and `.ioc` have not been generated or validated.

## Communication and limits

The [serial protocol](../docs/serial-protocol.md) defines field units and response ordering. Commands are line-buffered and parsed in the main loop; interrupts only collect RX bytes. Invalid configurations are rejected without partially changing setpoints. START is acknowledged before DATA; STOP is acknowledged after streaming stops. Configuration changes are rejected while streaming.

The MCU stops each run after **50,000 samples or one hour**, whichever comes first. The GUI can stop earlier using its requested duration. UART receive loss stops streaming and discards the damaged command through the next newline. Transmit failures stop streaming and require a new configuration. A host disconnect is not always detectable through this UART bridge, so the MCU can continue until its capture limit if no STOP reaches it. There are no physical power outputs to shut down in this image.

## Test the link

With the GUI and other serial programs closed, run this in the `matlab/` folder, substituting your actual port:

```matlab
report = testSTM32Link("COM5");
```

This exercises the actual board's STOP, invalid/valid CFG, START, source label, telemetry, increasing timestamps, disabled simulated rails, and STOP ordering. It has been provided for your board test; it has not been run against physical hardware here.

Host protocol tests require a C compiler with AddressSanitizer and UndefinedBehaviorSanitizer:

```sh
sh tests/run_host_tests.sh
```

In a restricted container that blocks LeakSanitizer's process inspection, run `ASAN_OPTIONS=detect_leaks=0 sh tests/run_host_tests.sh`. Address and undefined-behavior checks remain enabled. The protocol module does not allocate memory directly.

Validation performed: ARM compile/link, native protocol tests, and MATLAB static syntax/lint checks. Not yet performed: flashing a board, measuring UART timing, running MATLAB, or testing physical serial communication.

## Troubleshooting

- **No COM port:** use a data cable and the ST-LINK USB connector; check the OS device list and ST-LINK driver/firmware. In MATLAB, run `serialportlist("available")` after closing other serial apps.
- **STOP/CFG acknowledgement timeout:** reset the board, confirm 115200 baud, verify the firmware is running rather than halted in a debugger, and check LPUART1/bridge configuration.
- **Rails show zero:** their enable checkboxes are initially unchecked in serial mode. Enable them, apply settings, and start a new simulated capture.
- **Rate rejected:** use 50 Hz for initial testing, or at most 84 Hz with the prebuilt image.
- **RX loss / malformed line:** close other serial clients, reset, and reconnect. The GUI requires a complete acknowledged command before proceeding.

The next hardware step is to replace the synthetic backend in `platform_poll` with ADC readings and implement the actual supply/reference/clock drivers during CFG. Keep the protocol units, acknowledgements, and timing contract. Change the source declaration to HARDWARE only when the reported channels are backed by actual measurements; mixed simulated/real channels need an explicit per-channel source extension.
