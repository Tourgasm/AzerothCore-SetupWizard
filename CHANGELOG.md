# Changelog

## 0.9.3 - 2026-10-01 (pre-release)

Found by a test run on a clean PC (Windows Sandbox, no WAMP):

- Confirmed working on a clean PC: all of Step 1 (winget auto-install, Git, CMake, Visual C++ runtime, OpenSSL 3, HeidiSQL, MySQL from the ZIP archive, Boost).
- Fixed: an interrupted Visual Studio install was accepted as working. The wizard now checks that the Windows SDK (headers, libraries and tools) is present and offers to let the Visual Studio Installer finish where it stopped.
- Fixed: MySQL could not be installed on Windows without VBScript (Windows Sandbox, and future Windows versions as VBScript is removed). MySQL's installer needs VBScript and failed with error 2738. The wizard now installs MySQL from the official ZIP archive in that case, or whenever the installer fails: it unpacks MySQL, creates the databases, registers the `MySQL84` Windows service and asks you for a root password. No MySQL Configurator step is needed on that path.
- Fixed: on PCs with little memory for their processor count (for example 8 GB with 6 cores), the compile failed with "C1060: compiler is out of heap space". The wizard now limits how many compiler processes run at once on such PCs and says so. PCs with 2.5 GB or more per logical processor compile at full speed as before.
- If the compiler still runs out of memory, the wizard now continues automatically with fewer compiler processes (down to one at a time) instead of stopping. Files that already compiled are kept.
- MySQL's port is now detected from the running server instead of only being read from `my.ini`, so a non-standard port is picked up without the user having to know it. If no MySQL answers at all in Step 4, the wizard explains how to start it and lets you retry or enter a port.
- Compiler output is now also saved to `build-log.txt`, line by line, so it survives a crash or a closed window (the main log is written in batches and could lose it). When the compile fails, the first compiler errors are shown.
- When a winget install fails, the wizard now prints the reason from the installer's own log and explains Windows Installer errors 1603 and 1618 (another installation was interrupted or is still running: restart Windows and run Step 1 again).

## 0.9.2 - 2026-10-01 (pre-release)

- TrinityCore has now been tested end to end (with WAMP MySQL 8.4 and Boost 1.84): compile, client data extraction, TDB import, first start and the server folder.
- Fixed: the wizard offered to install HeidiSQL on every run even when it was already installed.

## 0.9.1 - 2026-10-01 (pre-release)

- Installs winget itself if it's missing (Windows Sandbox, older Windows 10), instead of stopping.

## 0.9.0 - 2026-10-01 (pre-release)

First public pre-release.

### Features
- Choice of **AzerothCore** (stock or Playerbots fork, plus optional modules) or **TrinityCore** 3.3.5.
- Six steps following each project's official Windows install guides: requirements, core installation, server setup, database setup, networking, and a separate `server` folder.
- Run the full setup or any single step from a menu. Every step can be re-run safely.
- Uses an existing WAMP MySQL 8.x, or installs MySQL 8.4 LTS.
- Creates a MySQL account with your own username and password.
- Installs OpenSSL 3.x (not 4) from slproweb's current installer list, verified by checksum.
- Installs Boost automatically: 1.78 for AzerothCore; the latest stable (or 1.84) for TrinityCore.
- Downloads AzerothCore's pre-extracted client data, or runs the extractors on your own WoW client.
- Downloads and unpacks TrinityCore's TDB world database.
- Sets the realm address and opens Windows Firewall ports for LAN or internet play.
- Copies the finished server into `<install folder>\server` and keeps it updated after rebuilds, without overwriting your `.conf` settings.
- Downloads resume after dropped connections, and Boost falls back to a second download site.
- Writes a log to `setup-log.txt`, including the wizard version.

### Known limitations
- Tested end to end with AzerothCore + WAMP only (TrinityCore followed in 0.9.2). Setups without WAMP (standalone MySQL) have not yet been tested end to end.
- MariaDB is not supported.
- Router port forwarding has to be set up by hand.
- AzerothCore and TrinityCore can be installed side by side, but only one can run at a time (they use the same ports).
