# claude-ping

Installs a cron job that runs `claude -p "ping"` on a schedule you choose, logs the result, and removes cleanly. Works on macOS and Linux, uses the `claude` already installed, and does not manage credentials.

## Quick start

```bash
chmod +x claude_ping.bash

./claude_ping.bash install     # asks: Time to ping (HH:MM, 24h) [07:00]:
./claude_ping.bash test        # run one ping now
./claude_ping.bash status      # confirm it is installed
```

Re-running `install` updates the existing entry instead of duplicating it.

## Choosing a time

Run `install` and answer the prompt:

```
$ ./claude_ping.bash install
Time to ping (HH:MM, 24h) [07:00]: 09:30
```

Or pass flags:

```bash
./claude_ping.bash install --time 09:30                # weekdays at 09:30
./claude_ping.bash install --time 18:00 --days '*'     # every day
./claude_ping.bash install --time 08:00 --days 1,3,5   # Mon/Wed/Fri
```

| Option | Meaning | Default |
|---|---|---|
| `--time HH:MM` | Time of day, 24-hour clock | prompt, then `07:00` |
| `--days DAYS` | `1-5`, `0-6`, `1,3,5`, `*` (0/7 = Sunday) | `1-5` |
| `--model MODEL` | Model alias or full name | `haiku` |
| `--prompt TEXT` | Prompt to send | `ping` |
| `--log PATH` | Log file | macOS: `~/Library/Logs/claude-ping.log`; Linux: `~/.local/state/claude-ping.log` |

Non-interactive runs (no terminal) use the default time instead of prompting.

## Commands

| Command | What it does |
|---|---|
| `install` | Add or update the cron job |
| `remove` | Delete the job, leaving other crontab entries alone |
| `status` | Show whether it is installed and when it runs |
| `test` | Run one ping now and print the output |
| `logs` | Show the last 40 lines of the log |
| `help` | Usage and options |

## Logs

Each run appends a start line, the output, and an exit code:

```
=== 2026-11-25 12:17:01 ping (model=haiku)
pong
=== exit 0
```

No entry means cron never ran it; a non-zero exit means it ran and failed. Read it with `./claude_ping.bash logs`.

## Platform notes

**Linux**

- `cron` is not installed on minimal images: `sudo apt install cron`.
- Run `install` as the user who owns the Claude setup, not with `sudo`, so the crontab, `HOME`, and log path are correct.

**macOS**

- If no log ever appears, grant `/usr/sbin/cron` Full Disk Access in System Settings → Privacy & Security.
- A sleeping Mac does not run cron jobs. Use `launchd` if the job must run at a specific time regardless of sleep.

**Both**

- The cron entry includes the directory of your `claude` in `PATH`, since cron does not read your shell profile.
- If `claude` is missing when the job runs, the log records `claude CLI not found on PATH` and the job exits 127.

## Uninstall

```bash
./claude_ping.bash remove
rm -f ~/Library/Logs/claude-ping.log ~/.local/state/claude-ping.log
```
