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
- **Communication:** USB serial with a [draft command protocol](docs/serial-protocol.md).

The MATLAB app sends settings and test commands. Firmware will configure peripherals, acquire measurements, and return data and status. Precise acquisition and signal timing belong in embedded hardware.

## Repository layout

| Directory | Purpose |
| --- | --- |
| `firmware/` | STM32 project, drivers, command handling, and acquisition code |
| `matlab/` | GUI source, usage instructions, and MATLAB tests |
| `hardware/` | Schematics, PCB designs, module interfaces, and bills of materials |
| `docs/` | Architecture, interfaces, communication protocol, and test procedures |

## Current status

The first MATLAB GUI is implemented with simulated data and a serial transport for the draft protocol. It has passed static MATLAB syntax/lint checks, but has not been run in MATLAB or tested with a board. Runnable MATLAB tests are included. Matching STM32 firmware and hardware designs have not been added yet.

## Next integration milestone

Create the STM32 project, implement and validate the serial protocol, then demonstrate one measured command-and-response path from the GUI through the MCU to the hardware. Extend to the remaining subsystems after that path works.
