# AzerothCore Setup Wizard for Windows

An interactive wizard that sets up your own [AzerothCore](https://www.azerothcore.org/) (World of Warcraft 3.3.5a) server on Windows. It handles installs, downloads, the build, the database and networking.

It follows the official AzerothCore wiki guides step by step, so you don't have to click through them by hand:

| Step | What the wizard does | Official guide |
|------|----------------------|----------------|
| 1. Requirements | Installs Git, CMake, OpenSSL 3, Visual Studio 2022 (C++), MySQL 8.4 and HeidiSQL, and helps you set up Boost | [Windows Requirements](https://www.azerothcore.org/wiki/windows-requirements) |
| 2. Core installation | Downloads AzerothCore and the modules you pick, runs CMake and compiles the server | [Core Installation](https://www.azerothcore.org/wiki/windows-core-installation) |
| 3. Server setup | Creates the `.conf` files and downloads or extracts the client data (maps, dbc, vmaps, mmaps) | [Server Setup](https://www.azerothcore.org/wiki/windows-server-setup) |
| 4. Database setup | Creates a MySQL account and the databases for AzerothCore, then fills in the configs | [Database Installation](https://www.azerothcore.org/wiki/database-installation) |
| 5. Networking | Sets the realm address and opens the Windows Firewall ports | [Networking](https://www.azerothcore.org/wiki/networking) |

> This is a community tool and is not affiliated with the AzerothCore project.
> If something doesn't work, open an issue here instead of asking the AzerothCore team.

## Features

- **Menu driven.** Run the full setup, or re-run any single step.
- **Safe to re-run.** Every step checks what's already done and skips it.
- **No reboot needed.** New PATH settings are loaded straight away.
- **Works with WAMP.** If you already use WampServer, the wizard finds its MySQL, checks the version and port, and uses it. Otherwise it installs MySQL 8.4 LTS.
- **Your own database account.** Choose your own username and password instead of the default `acore`/`acore`.
- **Playerbots support.** Pick the [Playerbots](https://github.com/mod-playerbots/mod-playerbots) fork or stock AzerothCore, plus optional modules:
  - mod-playerbots (AI player bots)
  - mod-autobalance (scales dungeons/raids to your group size)
  - mod-solo-lfg (queue for dungeons solo)
  - mod-transmog (transmogrification)
  - mod-ah-bot (fills the auction house)
- **Networking made simple.** Choose "just me", "my home network" or "the internet", and the wizard sets the realm address and firewall rules for you.
- **Logged.** Everything is saved to `setup-log.txt` so you can get help when something breaks.

## Requirements

- Windows 10 or 11 (64-bit)
- Administrator rights
- [winget](https://learn.microsoft.com/windows/package-manager/winget/) (App Installer). It comes with Windows 11 and recent Windows 10.
- About **60 GB** free disk space (Visual Studio, source, build and client data)
- A WoW **3.3.5a (12340)** client to play with
- Time: the first full run takes **1-2 hours**, mostly the Visual Studio install and compiling

## How to use

1. Download this repository (**Code → Download ZIP**) and extract it somewhere, for example your Desktop.
2. Double-click **`Start-Setup.bat`**.
3. Click **Yes** when Windows asks for administrator rights.
4. Choose **1 (Full setup)** and answer the questions.

If Windows shows *"Windows protected your PC"*, click **More info → Run anyway**. This happens with any script downloaded from the internet.

### Menu

```
1) Full setup: run every step in order (recommended the first time)
2) Step 1: Requirements (Git, CMake, OpenSSL, Visual Studio, MySQL, Boost)
3) Step 2: Core installation (download source + modules, CMake, compile)
4) Step 3: Server setup (config files, client data)
5) Step 4: Database setup (MySQL account, first start)
6) Step 5: Networking (realmlist, firewall)
7) Exit
```

Use the single steps to update and recompile the server later (Step 2), change your network setup (Step 5), and so on.

## Things you'll be asked

**MySQL / WAMP.** If you use WAMP, answer **yes**. WAMP must be running (green tray icon) during Step 4, and its MySQL version must be 8.x. WAMP's default root password is empty, so just press Enter. MariaDB is not supported by AzerothCore.

**Boost.** Boost can't be installed automatically. The wizard opens the download page and tells you which file to get (`boost_1_XX_0-msvc-14.3-64.exe`, version 1.78 or newer). Install it, then select its folder in the window that appears.

**Client data.** You can either:
- **Download** the ready-made data (easiest, English/enUS clients only, about 1.2 GB), or
- **Extract** it from your own WoW client (needed for non-English clients, can take several hours).

**Database account.** The server uses this account to talk to MySQL. Pick a username and password, or press Enter for the defaults `acore`/`acore`. The MySQL root account is only used to create this account and is never stored.

**Networking.**
- *Only me, on this computer*: nothing to open.
- *My home network*: the wizard finds your LAN IP and opens TCP ports **3724** and **8085** in Windows Firewall.
- *The internet*: same as above, plus you must set up **port forwarding** for 3724 and 8085 on your router. The wizard can't do that part; see [portforward.com](https://portforward.com) for your router.

## After setup

1. Start `authserver.exe`, then `worldserver.exe`. They're in `C:\AzerothCore\build\bin\RelWithDebInfo`.
   The first worldserver start takes a few minutes while it builds the world database.
2. In the worldserver window, create your game account:
   ```
   account create <name> <password>
   account set gmlevel <name> 3 -1
   ```
   (The second line is optional. It makes the account a GM.)
3. Set `realmlist.wtf` in your WoW client to `set realmlist 127.0.0.1` (or the server's address) and log in.

## Where things go

| What | Default location |
|------|------------------|
| Source code | `C:\AzerothCore\azerothcore-wotlk` |
| Build files | `C:\AzerothCore\build` |
| Server + configs | `C:\AzerothCore\build\bin\RelWithDebInfo` |
| Client data | `C:\AzerothCore\build\bin\RelWithDebInfo\Data` |
| Your answers | `wizard-settings.json` (next to the script, no passwords) |
| Log | `setup-log.txt` (next to the script) |

## Troubleshooting

- **Something failed.** The error is shown in red and you go back to the menu. Fix the problem and re-run that step. Steps that are already done are skipped.
- **Getting help.** Open an issue and attach `setup-log.txt`.
- **CMake can't find Boost.** Re-run Step 1 and pick your Boost folder again. It must contain a `boost` folder and a `lib64-msvc-14.x` folder.
- **worldserver closes right away.** Usually the client data is missing (re-run Step 3) or MySQL isn't running.
- **Friends can't connect.** Check the realm address in Step 5, your router's port forwarding, and that both servers are running.
- **Starting over.** Delete `wizard-settings.json` and the wizard asks everything again.

More help: [AzerothCore FAQ](https://www.azerothcore.org/wiki/faq) · [Common errors](https://www.azerothcore.org/wiki/common-errors)

## Credits

- [AzerothCore](https://github.com/azerothcore/azerothcore-wotlk) and its community for the server and the wiki guides this wizard follows
- [mod-playerbots](https://github.com/mod-playerbots/mod-playerbots) for the Playerbots fork
- [wowgaming/client-data](https://github.com/wowgaming/client-data) for the pre-extracted client data
