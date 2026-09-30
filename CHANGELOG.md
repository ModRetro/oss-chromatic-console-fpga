## v18.13

### Fixed
- Fixed a source of corrupted frames in OBS on macOS.

## v18.12

### Fixed
- Disable the charger watchdog so configured charging settings are not periodically reset.
- Correct temperature-based charge-current selection on hardware with a temperature sensor.
- Synchronize and latch hardware-revision detection before selecting the charging policy.
- Handle I2C NACKs and transaction timeouts, and retry failed charger writes.

## v18.11

### Added
- USB video streaming at 320x288 with 2x integer scaling, now the default. Native 160x144 streaming remains selectable in the capture application.

### Changed
- Reworked USB video capture, color conversion, and packetization to support both resolutions and recover from interrupted transfers.
- Identify USB game audio as a line input instead of a microphone.
- Reduced FPGA resource usage in the audio filters, USB serial FIFOs, and UART baud-rate calculation.
- Removed unused legacy modules, obsolete signal connections, and a stale clock constraint; cleaned up associated synthesis warnings and build references.

### Fixed
- Added hardware-revision-aware cartridge power and level-shifter sequencing to prevent leakage-driven cartridge signals while the updated hardware is switched off, including with USB connected.
- Hold the emulator in reset until cartridge startup sequencing completes.
- Corrected audio filter behavior when building with the updated Gowin tools.
- Improved menu-button synchronization and replaced a divided audio-system clock with a clock enable.

## v18.10

### Changed 
 - logic to support modified power switch network
 - modified USB charge functionality including temperature controlled charge current
 - add second version detect pin
 - add display id pin 
 - eliminate LCD ghosting
 - partial ESD mitigation
 - support for alternative PSRAM chip

## v18.9

### Changed 
 - added link-cable support for revised PCB
 - used `VERSION_DET` pin state for PCB-aware battery voltage thresholds
 - added bit to message payload sent to firmware for PCB-aware battery voltage estimate 
 - removed HDMI signals 
 - Additional `CART_RST` functionality.

### Fixed 
 - existing 3-wire interface for ST7785 LCD controller 

## v18.8

### Changed
- Enable audio until ESP32 can configure the FPGA

### Fixed
- IO0/En control sometimes fails to boot the ESP32
- The FPGA sometimes resets during play

## v18.7

### Fixed
- Custom sprite palettes distinguish betwen obj0 and obj1

## v18.6

### Added
- Support for streaming audio over USB.
- Support for custom palettes to override existing palette after boot.

### Changed
- Inverted audio polarity

## Fixed
- Reworked the design of frame blending

## v18.5

### Added
- Support for streaming on macOS and Discord.

### Changed
- The default palettes changed for `A + B + Right` and `A + B + Left`. All credit to **rayjt9**.
- Tuned settings for the Chromatic Power Core.

### Fixed
- LED indicator light now correct for AA, USB, and Chromatic Power Core use cases.
- Fixed an issue where the clock would skip in titles with an RTC (e.g. Pokemon Crystal).
- Fixed an issue where save data could be lost in some titles (e.g. Pokemon Crystal).
- Streaming no longer requires flipping the video in OBS.
- Miscellaneous compatibility fixes.

## v18.4

### Added
- Option to ignore diagonal inputs from the D-Pad
- Option to use the background palette 0 color (prevents screen transition flash)
- Option to set low battery icon display behavior

### Changed
- Tuned battery thresholds for 1.2V NiMH AA's

### Fixed
- Reduce backlight flashing when power source is nearly depleted
- Support for Kirby Tilt-n-Tumble
- Improved Chromatic firmware version detection
- Support streaming to Linux platforms

## v18.0

### Changed
- Improved button debouncing.

### Fixed
- Fully mute game audio when speaker wheel is turned to minimum.
- Silent mode mutes all device audio output.
- Suppress invalid DPAD inputs to correct character sprite glitch.
- Color decoding bug corrected (greyscale check).

## v17.0

### Note
The MCU must be updated to v0.12.X or newer as the underlying communication protocol changed.

### Changed
- Enable backlight switch on independent from MCU communication.
- Supports updated UART protocol.

## v16.0

### Note
The version of the IDE was switched to Gowin IDE v1.9.9.03. This resolves a synthensis bug which resulted in a palette flickering issue. Do not build with Gowin IDE v1.9.9.02 or older going forward.

### Added
- Reset the FPGA core when a cartridge is removed.
- Add hotkey for reset (Menu+A+B+Start+Select).
- Add hotkeys for brightness (Menu+Left/Right).

### Changed
- Only show icon overlays when the OSD is off.
- USB CDC descriptors for Linux & macOS.

### Fixed
- Improved AA/LiPo detection logic to resolve critical battery false positives.
- Fixes palette flickering issue seen on some games like Tetris.

## v13.1
This is the first production release.

## v13.0 and older
A preliminary engineering release.
