# DSH Safe Restart

**English** · [中文](README.md)

> A guarded restarter for **DeepSeek Harness Desktop** (DSH).
> It pre-checks every plugin before restarting, runs a health check afterwards, and rolls back automatically if DSH fails to come up.

**The one-liner**: when a DSH restart fails, it *silently downgrades your plugin config to factory state* (27 plugins → 2, a 197-line `cordis.patch.yml` → 22 lines). This script makes that impossible.

| | |
|---|---|
| **Who needs it** | Anyone running a pile of third-party plugins who restarts DSH often |
| **What it does** | Pre-check → snapshot → restart → health check → auto-rollback |
| **What it costs** | 5–10 extra seconds (the pre-check), in exchange for "a bad restart can heal itself" |
| **Requirements** | Windows + PowerShell 7 + the Node that ships with DSH. **No network, nothing to install** |

---

## The problem

DSH keeps plugin configuration in your profile directory:

```
%USERPROFILE%\.dsh\profiles\<profile>\package.json      # dsh.profile.bundles list
%USERPROFILE%\.dsh\profiles\<profile>\cordis.patch.yml  # plugin load order & config
```

If **any single** plugin fails to load after a restart, DSH's web boot fails, and then it does something nasty:

**It silently degrades the config to factory state.**

Concretely:

| | Normal | After degradation |
| --- | --- | --- |
| `dsh.profile.bundles` | dozens of entries | **2 entries** (only dsh-base / dsh-web-app) |
| `cordis.patch.yml` | hundreds of lines | **661 bytes** (22 lines, three UI overrides) |

No error dialog. No automatic backup. No "restore?" prompt. You open DSH and your plugins are simply gone.

This script adds a guard on both sides of the restart, making that outcome impossible.

---

## Three real incidents

These three actually happened, and they are why this script exists.

### 1. One plugin crashed, thirty others went with it

`@ebony-vinyl/dsh-our-free-model` 2.8.3 was installed. Its client bundle registered itself twice on startup and threw `duplicate factory registration`. Web boot failed, and DSH degraded the config: `bundles` went from 27 entries to 2, `cordis.patch.yml` from 197 lines to 661 bytes.

Recovery took over an hour — plugins had to be added back one at a time, with a restart after each to confirm.

**With this script**: the pre-restart dry-run checks whether every bundle can be `import`ed. The bad one gets caught, the script exits `3`, and not a single byte of config is touched.

### 2. Installing a plugin emptied another one

While running `pnpm add` to upgrade plugins, DSH was still open and holding file locks:

```
ERR_PNPM_EPERM: rename 'node_modules/ds-harness-remote_tmp_15340_11' -> 'ds-harness-remote'
```

pnpm failed and exited — but it had **already deleted the previous package contents**. `ds-harness-remote/dist/` became an empty directory (92 KB instead of 8.1 MB), and `dist/index.js` was simply gone.

On the next restart, the dry-run reported:

```
NO-ENTRY ds-harness-remote 0.6.5
ABORT: dry-run found bundles that cannot be imported; nothing was restarted
```

**This script blocked that hit.** Without it, DSH would have degraded the config.

### 3. Version incompatibility only shows up after a restart

A plugin author ships a new version whose `engines.dsh` range or subpath exports don't match your DSH version. It installs fine, `pnpm` reports no error, and **it only explodes on the next restart**.

The dry-run checks whether a real `import()` succeeds, so this class of problem surfaces *before* the restart.

---

## Usage

### Install

Requires Windows + PowerShell (7 recommended; 5.1 works too).

```powershell
# 1. Put the repo anywhere
git clone https://github.com/<you>/dsh-safe-restart.git

# 2. Enter the directory and create a desktop shortcut
pwsh -File install.ps1
```

A **"重启DSH（安全）"** shortcut appears on your desktop. Double-click to use.

Remove the shortcut:

```powershell
pwsh -File install.ps1 -Uninstall
```

### Day to day

Double-click the desktop shortcut → confirm the dialog → wait 40–70 seconds → a result dialog appears.

Sessions and conversation history live on disk; a restart does not lose them.

### Command line

```powershell
# Normal restart (pre-check + snapshot + restart + health check + rollback)
pwsh -File dsh-safe-restart.ps1

# Check only, no restart: show the pre-check, take a snapshot, exit
pwsh -File dsh-safe-restart.ps1 -DryRun

# Pick a profile (defaults to desktop)
pwsh -File dsh-safe-restart.ps1 -ProfileName work

# Wait longer for the health check (default 60s; raise it on plugin-heavy setups)
pwsh -File dsh-safe-restart.ps1 -WaitSec 120

# Skip the pre-check (not recommended; only if the pre-check itself is broken)
pwsh -File dsh-safe-restart.ps1 -SkipSimulate
```

### Exit codes

| Code | Meaning | Was config touched? |
| --- | --- | --- |
| `0` | Restarted successfully | No |
| `2` | Didn't come up the first time; auto-rolled back and recovered | Restored from snapshot |
| `3` | Pre-check blocked it; **nothing was restarted** | Untouched |
| `4` | Still down after rollback; needs manual intervention | Rolled back |

`3` is the most common *good* outcome — it means the guard did its job.

---

## How it works

Four stages:

```
1. Pre-check (dry-run)
   └─ import every bundle entry declared in the profile
      └─ any failure → exit 3, do nothing

2. Snapshot
   └─ copy package.json / cordis.patch.yml / cordis.yml
      └─ into %LOCALAPPDATA%\dsh-safe-restart\snapshots\<timestamp>\

3. Restart
   └─ kill all DeepSeek Harness processes → start it again

4. Health check
   ├─ process count ≥ 2
   ├─ no new crash-*.log
   └─ the DSH process is listening on a port itself
      └─ unhealthy → restore snapshot → start again → exit 2 / 4
```

### Nothing is hard-coded

The script does not assume where anything is installed. All of this is auto-detected:

- **DSH executable**: running process → uninstall registry key → common install paths
- **Profile directory**: `%USERPROFILE%\.dsh\profiles\desktop`, otherwise the most recently modified one
- **Node**: the `dsh-runtimes/*/dependencies/node/bin/node.exe` that ships with DSH → `node` on PATH
- **Log directory**: `%APPDATA%\@deepseek-ai\dsh-desktop\logs`

So it works across machines, usernames and drive letters.

### Logs

```
%LOCALAPPDATA%\dsh-safe-restart\safe-restart.log   main script log
%LOCALAPPDATA%\dsh-safe-restart\ui.log             UI entry log
%LOCALAPPDATA%\dsh-safe-restart\snapshots\         snapshots
```

---

## FAQ

**Q: It says `exit 3` but all my plugins look fine?**

The dry-run checks "can this be imported *right now*", not "did it work last time". Usually it's one of:

- a plugin was just upgraded and its `dist/` is incomplete (re-run `pnpm add`)
- DSH is still running and holding file locks (close it and run the dry-run again)

Look for the `NO-ENTRY` / `IMPORT-FAIL` lines in the log — they name the exact package.

**Q: Do snapshots take a lot of space?**

Three files per snapshot, usually tens of KB. The script does not clean up automatically; delete old directories under `snapshots` yourself.

**Q: Does it work with the Web version of DSH?**

No. This script restarts the **desktop process**. For web (`dsh web`), use pm2 / systemd or similar.

**Q: Why not a scheduled task?**

Tried it. `schtasks /Create` returns `4294967295` with no output on some machines, and `Register-ScheduledTask` says "access denied". A standalone process with a confirmation dialog is both more reliable and more transparent — you can see what it's doing.

---

## Repository layout

```
dsh-safe-restart.ps1       main script (pre-check / snapshot / restart / health check / rollback)
dsh-safe-restart-ui.ps1    graphical entry (confirmation dialog + result dialog)
dsh-simulate.mjs           the dry-run: imports every bundle entry with Node
install.ps1                create / remove the desktop shortcut
README.md                  Chinese
README.en.md               English (this file)
LICENSE
```

---

## Copyright & License

**Copyright (C) 2026 TNT460. Licensed under the GNU General Public License v3.0.**

The full license text is in [`LICENSE`](LICENSE) — the official GNU text, 674 lines, verifiable.

### You can

- Use it for free, **including commercially** (the GPL never forbids making money)
- Modify anything
- Distribute the original or modified versions, even for a fee

### You must

- **Provide the complete source** when you distribute (including your changes)
- **License derivative works under the GPL v3 as well** — that is copyleft: once open, it stays open
- Keep the copyright notice and license text
- Mark files you changed as modified

### You must not

- Merge this code into a **closed-source** product or service and redistribute it
- Add extra restrictions (e.g. requiring payment to use your modified version)

### No warranty

Provided "as is", without any warranty. The author is not liable for data loss, system failure or any other damage from using it.

What it does (killing processes, editing config files, rolling back) carries real risk — verify the snapshot mechanism works before relying on it.

### What the author keeps

- Copyright always stays with the author
- The author may license the same code under other terms as well (dual licensing, e.g. a future commercial edition)

### What this means in practice

| Scenario | Allowed? |
| --- | --- |
| Using it internally (personal or company) to restart your own DSH | ✅ Go ahead; no distribution means no source obligation |
| Tweaking a few lines for yourself | ✅ Same as above |
| Bundling it into your own open-source project | ✅ But your project must be GPL v3 too |
| Bundling it into your company's closed-source tool and selling it | ❌ Not allowed |
| Distributing it on a paid plugin marketplace | ⚠️ You may charge, but you must ship source, and buyers may redistribute |

> In one sentence: **personal, internal and open-source use are fine; closed-source commercial products are not.**

### Why GPL v3 instead of MIT

MIT lets anyone take the code, close it, and sell it — the author gets nothing. GPL guarantees "whoever modifies must open up", so community improvements flow back here.

The trade-off, stated plainly: some companies ban GPL code by internal policy, so it reaches a narrower audience than MIT.

> The above is a plain-language explanation, not legal advice. For commercial use or if in doubt, consult a lawyer.
