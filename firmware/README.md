# STM32 Firmware

Place the STM32CubeIDE project here. The initial development target is the NUCLEO-G474RE with an STM32G474RE MCU.

## Planned responsibilities

- Receive and validate commands from the MATLAB application.
- Configure the platform's power, reference, clock, and digital-interface hardware.
- Acquire and buffer measurements.
- Return measurements, acknowledgements, status, and errors.

Start by verifying serial communication with the PC. Peripheral assignments, pin mappings, and the command protocol should be documented in `../docs/` as they are agreed.

Commit source files, headers, the CubeMX `.ioc` configuration, linker scripts, and project/build configuration needed by teammates. Generated build output and local IDE workspace state are excluded by the root `.gitignore`.

No firmware implementation has been added yet.
