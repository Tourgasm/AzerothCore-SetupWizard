# WoW Emulator Setup

**Version 0.9.3 (pre-release)** · [Changelog](CHANGELOG.md) · [MIT License](LICENSE)

An interactive wizard that sets up your own World of Warcraft 3.3.5a (Wrath of the Lich King) private server on Windows. You choose between:

- **[AzerothCore](https://www.azerothcore.org/)** has Playerbots, a module system, and a ready-made client data download.
- **[TrinityCore](https://trinitycore.info/)** is the classic 3.3.5 branch. Client data is extracted from your own WoW client.

The wizard handles the installs, downloads, build, database and networking. It follows each project's official install guide step by step, so you don't have to click through them by hand:

| Step | What the wizard does | AzerothCore guide | TrinityCore guide |
|------|----------------------|-------------------|-------------------|
| 1. Requirements | Installs Git, CMake, OpenSSL 3, Visual Studio 2022 (C++), MySQL 8.4, Boost and HeidiSQL | [Requirements](https://www.azerothcore.org/wiki/windows-requirements) | [Requirements](https://trinitycore.info/en/install/requirements/windows) |
| 2. Core installation | Downloads the source (and AzerothCore modules), runs CMake and compiles the server | [Core Installation](https://www.azerothcore.org/wiki/windows-core-installation) | [Core Installation](https://trinitycore.info/en/install/Core-Installation/windows-core-installation) |
| 3. Server setup | Creates the `.conf` files and gets the client data (maps, dbc, vmaps, mmaps) | [Server Setup](https://www.azerothcore.org/wiki/windows-server-setup) | [Server Setup](https://trinitycore.info/en/install/Server-Setup/Windows-Server-Setup) |
| 4. Database setup | Creates a MySQL account and the databases, fills in the configs, and (TrinityCore) downloads the world database | [Database Installation](https://www.azerothcore.org/wiki/database-installation) | [Database Installation](https://trinitycore.info/en/install/Database-Installation) |
| 5. Networking | Sets the realm address and opens the Windows Firewall ports | [Networking](https://www.azerothcore.org/wiki/networking) | [Networking](https://trinitycore.info/install/Networking) |
| 6. Server folder | After the first test start, copies the finished server into its own `server` folder, apart from the build files | | |

> This is a community tool and is not affiliated with the AzerothCore or TrinityCore projects.
> If something doesn't work, open an issue here instead of asking their teams.

> **What has been tested:** all six steps have been run end to end with AzerothCore on a PC with WAMP and on a freshly installed Windows 11 without WAMP, and with TrinityCore on a PC with WAMP. TrinityCore on a PC without WAMP uses the same MySQL code but hasn't had its own complete run yet. If something goes wrong, please open an issue and attach `setup-log.txt`.

## Features

- **Two cores, one wizard.** Pick AzerothCore or TrinityCore at the start. You can switch from the menu, and each keeps its own settings and install folder.
- **Menu driven.** Run the full setup, or re-run any single step.
- **Safe to re-run.** Every step checks what's already done and skips it.
- **No reboot needed.** New PATH settings are loaded straight away.
- **Works with WAMP.** If you already use WampServer, the wizard finds its MySQL, checks the version and port, and uses it. Otherwise it installs MySQL 8.4 LTS.
- **Your own database account.** Choose your own username and password instead of the defaults (`acore`/`acore` or `trinity`/`trinity`).
- **Correct versions automatically.** It installs OpenSSL 3.x (not 4) and the right Boost for each core (1.78 for AzerothCore, the latest stable for TrinityCore).
- **AzerothCore extras.** Pick the [Playerbots](https://github.com/mod-playerbots/mod-playerbots) fork or stock AzerothCore, plus optional modules:
  - mod-playerbots (AI player bots)
  - mod-autobalance (scales dungeons/raids to your group size)
  - mod-solo-lfg (queue for dungeons solo)
  - mod-transmog (transmogrification)
  - mod-ah-bot (fills the auction house)
- **Networking made simple.** Choose "just me", "my home network" or "the internet", and the wizard sets the realm address and firewall rules for you.
- **Logged.** Everything is saved to `setup-log.txt`, and the compiler output also goes to `build-log.txt`, so you can get help when something breaks.

## Requirements

- Windows 10 or 11 (64-bit)
- Administrator rights
- [winget](https://learn.microsoft.com/windows/package-manager/winget/) (App Installer). It comes with Windows 11 and recent Windows 10. If it's missing (for example in Windows Sandbox), the wizard offers to install it.
- About **60 GB** free disk space (Visual Studio, Boost, source, build and client data)
- A WoW **3.3.5a (12340)** client to play with. TrinityCore also needs it to extract the client data.
- Time: the first full run takes **1-2 hours**, mostly the Visual Studio install and compiling. Extracting client data (always needed for TrinityCore) can add several hours.

## How to use

1. Download this repository (**Code → Download ZIP**) and extract it somewhere, for example your Desktop.
2. Double-click **`Start-Setup.bat`**.
3. Click **Yes** when Windows asks for administrator rights.
4. Pick **AzerothCore** or **TrinityCore**.
5. Choose **1 (Full setup)** and answer the questions.

If Windows shows *"Windows protected your PC"*, click **More info → Run anyway**. This happens with any script downloaded from the internet.

### Menu

```
1) Full setup: run every step in order (recommended the first time)
2) Step 1: Requirements (Git, CMake, OpenSSL, Visual Studio, MySQL, Boost)
3) Step 2: Core installation (download source, CMake, compile)
4) Step 3: Server setup (config files, client data)
5) Step 4: Database setup (MySQL account, first start)
6) Step 5: Networking (realmlist, firewall)
7) Step 6: Server folder (copy the finished server to C:\AzerothCore\server)
8) Switch to TrinityCore / AzerothCore
9) Exit
```

Use the single steps to update and recompile the server later (Step 2), change your network setup (Step 5), and so on.

### The server folder (Step 6)

Once the first test start works, Step 6 copies the finished server into **`C:\AzerothCore\server`** or **`C:\TrinityCore\server`**. Run your server from there from then on.

- It asks you to stop the servers first, because Windows locks running programs.
- It copies the programs, DLLs, `.pdb` crash-report files and config files. The client data (several GB) is moved instead of copied, so it doesn't take up the space twice.
- `DataDir` in `worldserver.conf` is updated to the new `Data` folder.
- **Updating later:** after a recompile in Step 2, the wizard offers to copy the new build into the server folder. Your `.conf` settings there are never overwritten, but new `.conf.dist` files are copied so you can see new options.
- Once the server folder exists, Steps 3–5 configure and start the server from there. You can also keep the server running while recompiling, because the build happens in a separate folder.

## Things you'll be asked

**MySQL / WAMP.** If you use WAMP, answer **yes**. WAMP must be running (green tray icon) during Step 4, and its MySQL version must be 8.x (TrinityCore needs 8.0.34 or newer). WAMP's default root password is empty, so just press Enter. MariaDB is not supported by this wizard.

Without WAMP, the wizard installs MySQL 8.4 LTS for you:
- Normally it uses MySQL's installer and then opens **MySQL Configurator**, where you set a root password and keep "Configure as Windows Service" ticked.
- If that installer can't run (it needs VBScript, which some Windows installs no longer have), the wizard sets MySQL up itself from the official ZIP archive and just asks you for a root password.

Either way, **write the root password down**. Step 4 asks for it.

You don't need to know which port your MySQL uses. The wizard reads it from the running MySQL server and writes it into the server's config files. If MySQL isn't running when Step 4 starts, the wizard tells you how to start it and waits.

**Boost.** The wizard can download and install the right Boost for you (about 200 MB, installed to `C:\local`):
- AzerothCore: [Boost 1.78](https://sourceforge.net/projects/boost/files/boost-binaries/1.78.0/boost_1_78_0-msvc-14.3-64.exe/download)
- TrinityCore: the **latest stable** Boost, as TrinityCore's guide recommends (1.80 is the minimum). The wizard looks up the newest version from [archives.boost.io](https://archives.boost.io/release/) when it runs. It also offers Boost 1.84, the version TrinityCore's own Windows build is tested with, in case the newest one causes build problems.

If you'd rather do it yourself, it opens the link in your browser. If you already have a suitable Boost, it finds it and uses it.

**Client data.**
- AzerothCore: **download** the ready-made data (easiest, English/enUS clients only, about 1.2 GB), or **extract** it from your own WoW client.
- TrinityCore: **extract** it from your own WoW client. The wizard copies the extractor tools into your WoW folder, runs them, then moves the results into the server's `Data` folder. Choose option 4 ("extract all") in the extractor window and don't close it early.

**Database account.** The server uses this account to talk to MySQL. Pick a username and password, or press Enter for the defaults. The MySQL root account is only used to create this account and is never stored.

**World database (TrinityCore).** The wizard downloads the latest TDB 335 release from TrinityCore's GitHub and unpacks it next to `worldserver.exe`. The worldserver imports it on its first start, which takes a few minutes.

**Networking.**
- *Only me, on this computer*: nothing to open.
- *My home network*: the wizard finds your LAN IP and opens TCP ports **3724** and **8085** in Windows Firewall.
- *The internet*: same as above, plus you must set up **port forwarding** for 3724 and 8085 on your router. The wizard can't do that part; see [portforward.com](https://portforward.com) for your router.

## After setup

1. Start `authserver.exe` and `worldserver.exe` from the `server` folder (see below).
   The first worldserver start takes a few minutes while it builds the world database. On TrinityCore's very first start, start the worldserver first, because it creates the databases. The wizard does this for you in Step 4.
2. In the worldserver window, create your game account:
   ```
   account create <name> <password>
   account set gmlevel <name> 3 -1
   ```
   (The second line is optional. It makes the account a GM.)
3. Set `realmlist.wtf` in your WoW client to `set realmlist 127.0.0.1` (or the server's address) and log in.
4. To stop the server, type `server shutdown 1` in the worldserver window instead of closing it.

## Where things go

| What | AzerothCore | TrinityCore |
|------|-------------|-------------|
| Source code | `C:\AzerothCore\azerothcore-wotlk` | `C:\TrinityCore\TrinityCore` |
| Build files | `C:\AzerothCore\build` | `C:\TrinityCore\build` |
| Build output | `C:\AzerothCore\build\bin\RelWithDebInfo` | `C:\TrinityCore\build\bin\RelWithDebInfo` |
| **Server (after Step 6)** | `C:\AzerothCore\server` | `C:\TrinityCore\server` |
| Config files | `server\configs` | `server` (next to the exes) |
| Client data | `server\Data` | `server\Data` |
| Databases | `acore_auth`, `acore_world`, `acore_characters` | `auth`, `world`, `characters` |
| Your answers | `wizard-settings.json` | `wizard-settings-trinitycore.json` |

The logs are `setup-log.txt` (everything the wizard did) and `build-log.txt` (the compiler output, written line by line so it survives a crash), both next to the script. The settings files never contain passwords.

## Troubleshooting

- **Something failed.** The error is shown in red and you go back to the menu. Fix the problem and re-run that step. Steps that are already done are skipped.
- **Getting help.** Open an issue and attach `setup-log.txt`. Its first lines show the wizard version you ran. If the compile failed or the wizard closed during it, attach `build-log.txt` too.
- **Running both cores.** AzerothCore and TrinityCore can be installed side by side, but they use the same ports, so only one can run at a time. If the other one is running, the wizard offers to stop it.
- **CMake can't find Boost.** Re-run Step 1 and pick your Boost folder again. It must contain a `boost` folder and a `lib64-msvc-14.x` folder.
- **Compile fails with "compiler is out of heap space" (C1060).** The PC ran out of memory. The wizard already limits the compile on PCs with little memory, but other open programs count too. Close them and run Step 2 again; it continues where it stopped.
- **worldserver closes right away.** Usually the client data is missing (re-run Step 3) or MySQL isn't running.
- **Friends can't connect.** Check the realm address in Step 5, your router's port forwarding, and that both servers are running.
- **Starting over.** Delete that core's `wizard-settings*.json` and the wizard asks everything again.

More help: [AzerothCore FAQ](https://www.azerothcore.org/wiki/faq) · [AzerothCore common errors](https://www.azerothcore.org/wiki/common-errors) · [TrinityCore docs](https://trinitycore.info/)

## Files

| File | Purpose |
|------|---------|
| `Start-Setup.bat` | Double-click this to start the wizard |
| `WoW-Emulator-Setup.ps1` | The wizard itself (PowerShell) |
| `CHANGELOG.md` | What changed in each version |
| `LICENSE` | MIT license |

## License

[MIT](LICENSE). AzerothCore and TrinityCore are separate projects with their own licenses (GPL-2.0). This wizard only downloads them; it doesn't include their code.

## Credits

- [AzerothCore](https://github.com/azerothcore/azerothcore-wotlk) and [TrinityCore](https://github.com/TrinityCore/TrinityCore) and their communities for the servers and the install guides this wizard follows
- [mod-playerbots](https://github.com/mod-playerbots/mod-playerbots) for the Playerbots fork
- [wowgaming/client-data](https://github.com/wowgaming/client-data) for AzerothCore's pre-extracted client data
