# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A fork of PtokaX 0.5.3.0 — a Direct Connect (NMDC protocol) hub server in C++ with a Lua
scripting interface. Upstream is a Windows-first codebase ported to POSIX; this fork
(`0.5.3.1-hotel-fork`) reworked the build system and is progressively replacing Windows-port
idioms with native POSIX ones. Diverging from upstream is usually the point, not a hazard —
don't preserve upstream shape for its own sake.

## Build

`./configure` writes `config.mk`; `make` reads it. There is no autotools/CMake.

```sh
./configure && make -j8          # default: Lua auto-detect, no database, bundled tinyxml + Skein
make check                       # smoke test — runs ./PtokaX -v, creates no files, opens no sockets
make V=1                         # full compiler command lines
make help                        # target list + current configuration summary
make config                      # re-run configure with the exact options it was last given
make DESTDIR=/tmp/stage install  # staged install of the binary to $(bindir)
make distclean                   # also removes config.mk and config.log
```

Out-of-tree builds work and are the clean way to test build changes without dirtying the repo:

```sh
mkdir -p /tmp/pxbuild && cd /tmp/pxbuild && /path/to/PtokaX/configure && make -j8
```

Key `./configure` options (`--help` for all):

- `--with-lua=auto|5.1|5.2|5.3|5.4|5.5|<pkg-config module>` — 5.5 is supported.
- `--with-database=none|sqlite|postgres|mysql` — **changes the on-disk setting ID layout**;
  switching backends is not a drop-in swap for an existing `cfg/Settings.pxt`.
- `--with-system-tinyxml` — off by default on purpose: `TIXML_USE_STL` changes `TiXmlNode`'s
  layout, and only the bundled copy guarantees both sides agree. Don't flip this default.
- `--without-skein` — drops hashed-password support; only for platforms where Skein won't build
  (Haiku, Solaris).
- `--enable-debug` — `-O0 -g3`.

Configure emits `FEATURE_DEFINES` (`-D_WITH_SQLITE` / `_WITH_POSTGRES` / `_WITH_MYSQL`),
`ICONV_DEFINES` (`-DICONV_CONST=const` where iconv takes `const char **`), `TINYXML_DEFINES`,
and picks exactly one `DB_SRC`. The Makefile excludes `PtokaX-win.cpp`, `ExceptionHandling.cpp`,
`UpdateCheckThread.cpp` and the two unselected `DB-*.cpp` from the source list — those files are
still in `core/` but are never compiled here.

There are no tests. `make check` is a version-print smoke test.

**Build recipes never perform privileged actions** — no `setcap`, `sysctl`, or `sudo` in any
target. Port-binding advice belongs in `README`, not in the Makefile.

## Running

```sh
./PtokaX -c /path/to/configdir    # config dir holds cfg/ logs/ scripts/ texts/
./PtokaX -m                       # interactive configuration menu
./PtokaX -d -p /run/ptokax.pid    # daemon
```

With no `-c`: console mode uses the current directory, daemon mode uses `$HOME/.PtokaX`.
Seed a config dir from `cfg.example/`. `language/` holds translation XML.

## Architecture

Single-process, mostly single-threaded. `main()` in `core/PtokaX-nix.cpp` sets up signals,
calls `ServerManager::Initialize()` / `Start()`, then spins a 100ms loop calling
`ServiceLoop::Looper()` until terminated or signalled.

Nearly every subsystem is a class with a `static <Class> * m_Ptr` singleton pointer, constructed
in `ServerManager::Initialize()` and torn down in `FinalStop()`. Intrusive doubly-linked lists
(`m_pPrev` / `m_pNext` members on the element structs themselves) are the pervasive container
idiom; copy ctor and `operator=` are declared private and left undefined to make them non-copyable.

Data flow for a connected user:

1. **`ServerThread`** (`ServerThread.cpp`) — one real pthread per listening socket
   (IPv4/IPv6 × port). Accepts, applies per-IP anti-connection-flood, hands the socket to
   `ServiceLoop::AcceptSocket()` under a mutex. This is the only significant threading;
   `RegThread` (hublist registration) and `UDPThread` are the others.
2. **`ServiceLoop`** (`serviceLoop.cpp`) — the real main loop. Drains the accept queue,
   `ReceiveLoop()` / `SendLoop()` over all users, runs per-second and per-minute timers.
3. **`User`** (`User.cpp`) — per-connection state plus its own recv/send buffers; splits the
   stream into `|`-terminated NMDC commands.
4. **`DcCommands`** (`DcCommands.cpp`) — dispatches protocol commands (`$MyINFO`, `$Search`,
   `$To:`, chat, …). Chat lines beginning with the hub's command prefix go to **`HubCommands`**,
   which is split across `HubCommands.cpp` and `HubCommands-AE/-FH/-IQ/-RZ.cpp` purely by
   first letter of the command name — the split is alphabetical, not functional.
5. **`GlobalDataQueue`** (`GlobalDataQueue.cpp`) — batches outbound broadcasts (to all / ops /
   IP-list recipients), builds the zlib-compressed variant once, and flushes them per loop.
   `Users` (`colUsers.cpp`) caches the nick list, op list and MyINFO blobs in both plain and
   zlib forms; `HashManager` (`hashUsrManager.cpp`) provides 64K-bucket nick and IP hash tables.

**`EventQueue`** (`eventqueue.cpp`) carries cross-thread and deferred requests (restart, script
reload, shutdown, messages from `RegThread` / `ServerThread` / UDP) into the main loop, which
drains them via `ProcessEvents()`. Anything a worker thread needs the main loop to do goes here.

**Scripting** — `ScriptManager` (`LuaScriptManager.cpp`) owns a table of `Script`s, each with its
own `lua_State`, bot list and timer list. Protocol events reach scripts through
`ScriptManager::Arrival()` keyed by the `LuaArrivals` enum. The hub's Lua API is split into
`Lua*Lib.cpp` modules (Core, BanMan, RegMan, ProfMan, SetMan, ScriptMan, TmrMan, IP2Country,
UDPDbg), each exposing a `Reg<Name>(lua_State *)`. Every one of those has two definitions guarded
by `#if LUA_VERSION_NUM > 501` (module return value vs. `void`), and `#if LUA_VERSION_NUM < 503`
guards the integer/number API split — **any new Lua-facing function needs both arms**.
`scripting.docs/scripting-interface.txt` documents the script-visible API.

**Persistence** — settings, bans, registered users and reserved nicks are stored in a custom
tagged binary format read/written by `PXBReader` (`.pxt` files); `RegisteredUsers.xml` and
`BanList.xml` use tinyxml. Setting identifiers live in `SettingIds.h` as enums whose membership is
`#ifdef`-gated on the database backend — this is why swapping `--with-database` shifts the on-disk
layout.

## Gotchas

- The version string has one source: `PACKAGE_VERSION` in `configure`, which reaches the
  binary as `-DPACKAGE_VERSION` (`VERSION_DEFINES` in `config.mk`). `core/stdinc.h`
  derives `PtokaXVersionString` from it and holds a fallback literal for builds that
  bypass configure — keep that in step. See `DEVNOTES`.
- `core/stdinc.h` is the umbrella header — platform includes, `TIXML_USE_STL`, endian shims for
  Mach/Haiku/Solaris/BSD, and the global title constant. New platform conditionals belong there.
- `skein/src/` is the only Skein directory that matters; the sibling directories
  (`Reference_Implementation`, `Additional_Implementations`, `KAT_MCT`) are upstream ballast.
- Logging currently goes through `AppendLog` / `AppendDebugLog` / `AppendDebugLogFormat` in
  `core/utility.cpp` writing to files under the config dir. `init_hitlist` sketches the planned
  rework to a single priority-tagged sink usable by journald — read it before touching logging.

## Comments

Comment only non-obvious facts — constraints, invariants, why a value is what it is. Never write
a comment that justifies a choice to the reader; if the code needs defending, change the code.
