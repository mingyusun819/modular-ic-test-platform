# Prebuilt communication-test firmware

Target: **NUCLEO-G474RE / STM32G474RET6**. Built 2026-10-26 from the source files in this repository version. Telemetry is **SIMULATED**. See [flashing instructions](../README.md) and [third-party notices](../THIRD_PARTY_NOTICES.md).

| Item | Value |
| --- | --- |
| Build system | PlatformIO Core, version 6.2.0 |
| Platform | ststm32 20.0.0 |
| Framework | STM32CubeG4 1.6.3 (HAL 1.2.7; CMSIS device 1.2.6) |
| Compiler | GNU Arm Embedded GCC 7.2.1; PlatformIO package 1.70201.0 |
| Linker scripts | tool-ldscripts-ststm32 0.3.0 |
| CPU clock | HSI 16 MHz |
| UART | LPUART1 PA2/PA3, 115200 8N1 |
| Flash start | 0x08000000 |
| Binary bytes | 24892 |
| Initial stack pointer | 0x20020000 |
| Reset vector (Thumb bit set) | 0x08005A99 |

Rebuild from `firmware/` with `pio run`. The binary is `.pio/build/nucleo_g474re/firmware.bin`. Generate Intel HEX with `arm-none-eabi-objcopy -O ihex .pio/build/nucleo_g474re/firmware.elf nucleo_g474re_gui.hex` using the installed compiler tools. [SHA256SUMS.txt](SHA256SUMS.txt) records both images and their application source inputs; check its paths from the `firmware/` directory.

Validation completed:

- STM32G474RE compile and link succeeded; no application compiler warnings were emitted.
- Native C tests passed with AddressSanitizer and UndefinedBehaviorSanitizer. Leak scanning was disabled because this container blocks its process inspection. Tests cover the GUI command exchange, atomic configuration rejection, framing/recovery, ACK ordering, STOP, fractional rates, timestamp rollover, sample/time limits, TX/RX faults, and 100,000 pseudorandom input bytes.
- Intel HEX round-trip exactly matches the binary; reset and initial stack vectors were checked.
- Three MATLAB files passed MISS_HIT static syntax/lint checks targeting R2021a.

Not yet validated: flashing or running a physical board, UART electrical/timing behavior, MATLAB runtime behavior, and the MATLAB-to-board integration test. There are no physical analog measurements or DUT output drivers in this image.
