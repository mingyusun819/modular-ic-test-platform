# Modular IC Test Platform

University of Toronto ECE496 capstone project: a reusable, configurable platform for testing analog and mixed-signal integrated circuits.

The platform combines a common core with DUT-specific modules. Planned functions include adjustable power supplies, voltage and current references, clock generation, digital communication, and measurement.

## Development setup

- **Firmware:** STM32, with the NUCLEO-G474RE / STM32G474RE as the initial development target.
- **PC interface:** MATLAB App Designer for test configuration, measurement display, plotting, and data export.
- **PC–MCU communication:** USB serial as the initial approach; the command protocol remains to be defined.

The MATLAB application will send settings and test commands. STM32 firmware will configure the hardware, acquire measurements, and return results and status. Precise sampling and signal timing belong in the embedded hardware.

## Repository layout

| Directory | Purpose |
| --- | --- |
| `firmware/` | STM32 project, peripheral drivers, command handling, and acquisition code |
| `matlab/` | MATLAB GUI, communication code, and analysis utilities |
| `hardware/` | Schematics, PCB designs, module interfaces, and bills of materials |
| `docs/` | Architecture, pin assignments, communication protocol, and test procedures |

## Status

This repository contains the initial project structure and planning notes. Firmware, the MATLAB GUI, and hardware designs have not been added yet.

## First development milestone

1. Create the STM32 project and verify the PC–MCU serial connection.
2. Agree on command framing, units, responses, and error handling.
3. Build a MATLAB interface with Connect, one setting input, Apply, and one measurement display.
4. Demonstrate a complete command-and-response path before adding the remaining subsystems.

See the README in each directory for what belongs there.
