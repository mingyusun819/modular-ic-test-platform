# Modular IC Test Platform

University of Toronto ECE496 capstone project: a reusable, configurable platform for testing analog and mixed-signal integrated circuits.

The planned platform combines a common core with DUT-specific modules and provides adjustable supplies, analog references, clock generation, digital communication, and measurement.

## Try the MATLAB GUI

Download the repository and set MATLAB's Current Folder to `matlab/`, then run:

```matlab
app = ModularICTestApp;
```

Select **Demo (offline)**, click **Connect**, **Apply settings**, then **Start new capture**. No board is required for the demo. The app includes four graphs, numeric readouts, power/stimulus inputs, capture controls, and CSV export. See the [GUI instructions](matlab/README.md).

## Development setup

- **Firmware:** STM32, initially targeting NUCLEO-G474RE / STM32G474RE.
- **PC interface:** A native, programmatic MATLAB GUI (`.m` source) using MATLAB UI components.
- **Communication:** USB serial with a [documented command protocol](docs/serial-protocol.md).

The MATLAB app sends settings and test commands. The first firmware implements command handling and returns simulated data over the board's ST-LINK virtual COM port. Physical measurement/output drivers are the next integration step. Precise acquisition and signal timing belong in embedded hardware.

## Repository layout

| Directory | Purpose |
| --- | --- |
| `firmware/` | STM32 project, drivers, command handling, and acquisition code |
| `matlab/` | GUI source, usage instructions, and MATLAB tests |
| `hardware/` | Schematics, PCB designs, module interfaces, and bills of materials |
| `docs/` | Architecture, interfaces, communication protocol, and test procedures |

## Current status

The MATLAB GUI and matching NUCLEO-G474RE communication firmware are implemented. A compiled `.bin`/`.hex`, STM32Cube HAL source project, and [flashing/connection guide](firmware/README.md) are included. The MCU sends explicitly labeled simulated measurements; ADC, supplies, references, and clock output still need hardware drivers.

Validation completed: ARM firmware compile/link, native protocol tests with address/undefined-behavior sanitizers, and MATLAB static syntax/lint checks. The board has not been flashed here and MATLAB/physical serial operation has not been tested. Runnable MATLAB tests and a board-link test are included.

## Next integration milestone

Flash the board, verify the existing serial link with the GUI, then replace one simulated channel with an actual ADC measurement. Extend to the remaining subsystems after that measured command-and-response path works.
