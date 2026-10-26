# Third-party components in the prebuilt image

The application is built against unmodified components distributed in PlatformIO's `framework-stm32cubeg4@1.6.3` and `toolchain-gccarmnoneeabi@1.70201.0`. The compiler and complete framework are downloaded at build time, not vendored in this repository.

- **STM32G4 HAL V1.2.7**, Copyright STMicroelectronics (individual source files include Copyright (c) 2019 STMicroelectronics). BSD 3-Clause terms: [`licenses/STM32-HAL-BSD-3-Clause.txt`](licenses/STM32-HAL-BSD-3-Clause.txt). [Upstream license](https://github.com/STMicroelectronics/stm32g4xx-hal-driver/blob/v1.2.7/LICENSE.md).
- **STM32G4 CMSIS device V1.2.6**, Copyright (c) 2019 STMicroelectronics. Apache 2.0 terms: [`licenses/STM32-CMSIS-Apache-2.0.txt`](licenses/STM32-CMSIS-Apache-2.0.txt). [Pinned upstream component](https://github.com/STMicroelectronics/cmsis-device-g4/tree/25664ddc3a7624ae9627ae8c4c672073dc5b2539).
- **Arm CMSIS Core**, Copyright (c) 2009–2019 Arm Limited. Apache 2.0 terms: [`licenses/Arm-CMSIS-Apache-2.0.txt`](licenses/Arm-CMSIS-Apache-2.0.txt), copied from the installed framework's `Drivers/CMSIS/LICENSE.txt`.
- **GNU Arm runtime / newlib / libgloss**, notices and license text reproduced from the installed toolchain: [`licenses/GCC-runtime.txt`](licenses/GCC-runtime.txt) and [`licenses/newlib-libgloss.txt`](licenses/newlib-libgloss.txt). The GCC runtime includes the GCC Runtime Library Exception. Other toolchain executables are not included in the application image.

Keep these notices and license files with redistributed prebuilt images. These notices describe third-party components; they do not assign a new license to the capstone's original application files.
