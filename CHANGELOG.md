# Changelog

## 0.9.3 - 2026-10-01 (pre-release)

Found by a test run on a clean PC (Windows Sandbox, no WAMP):

- Confirmed working on a clean PC: winget auto-install, Git, CMake, Visual C++ runtime, OpenSSL 3 and HeidiSQL.
- Fixed: an interrupted Visual Studio install was accepted as working. The wizard now checks that the Windows SDK is present and offers to let the Visual Studio Installer finish where it stopped.
- When a winget install fails (for example MySQL), the wizard now prints the reason from the installer's own log and explains Windows Installer errors 1603 and 1618 (another installation was interrupted or is still running: restart Windows and run Step 1 again).

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
