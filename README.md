# Airlift

Use a spare Mac as the compute host for Codex and Claude Code while keeping one clean browser cockpit on your main Mac.

Airlift is a small bootstrap and lifecycle wrapper around [Yep Anywhere](https://github.com/kzahel/yepanywhere), the open-source web UI for the real Codex and Claude Code CLIs. It does not proxy prompts through a new AI provider.

The browser runs on Dylan's MacBook Pro. The agents, repositories, shell commands, tests, credentials, and compute run on the MacBook Air.

## Send this to Dylan

First, on the **MacBook Air**, turn on:

**System Settings → General → Sharing → Remote Login**

Then run this on the **MacBook Pro**:

```bash
git clone https://github.com/ojaskandy/airlift.git
cd airlift
./airlift setup <air-username>@Dylans-MacBook-Air.local
./airlift open
```

Replace `<air-username>` with the login username shown on the MacBook Air. The setup command handles the remaining Air-side installation and opens the one-time Codex and Claude Code sign-ins.

## What Dylan gets

- One UI for both Codex and Claude Code.
- Provider and model switching when starting sessions.
- Reasoning/effort, service-tier, thinking, and permission-mode controls when supported by the selected agent.
- Streamed output, tool calls, diffs, approvals, questions, and session history.
- Back-and-forth follow-up messages.
- Work that continues on the Air if the browser disconnects.
- No public command server: the cockpit binds to the Air's loopback interface and reaches the Pro through SSH.

## Two-minute setup

On the **MacBook Air**:

1. Open **System Settings → General → Sharing**.
2. Turn on **Remote Login**.
3. Allow access only for the user that should run engineering tasks.
4. Keep the Air plugged in while using it as the worker.

On **Dylan's MacBook Pro**:

```bash
git clone https://github.com/ojaskandy/airlift.git
cd airlift
./airlift setup dylan@Dylans-MacBook-Air.local
./airlift open
```

Setup creates a dedicated SSH key, installs the cockpit plus Codex and Claude Code on the Air, walks through each one-time login, and keeps the Air awake while it is connected to power.

If the Air's username is not `dylan`, replace the username in the setup command.

## Put a repository on the Air

Clone it directly on the worker:

```bash
./airlift clone git@github.com:your-org/your-repo.git
./airlift open
```

`clone` refuses if the Air has less than 25 GiB free, so a large repository can't
fill the disk. Override the floor with `AIRLIFT_MIN_DISK_GB=<gb>`.

Or open an existing Air-side checkout:

```bash
./airlift open '~/Developer/your-repo'
```

For a private GitHub repository, authenticate GitHub on the Air once:

```bash
./airlift shell
gh auth login --web
gh auth setup-git
exit
```

## Daily use

```bash
./airlift open                         # Open the last project
./airlift open '~/Developer/project'   # Open a specific Air-side project
./airlift doctor                       # Check SSH, agents, accounts, disk, and power
./airlift shell                        # Get a normal shell on the Air
./airlift stop                         # Close only the tunnel; active work continues
./airlift shutdown                     # Stop the cockpit; use after work is idle
```

Inside the cockpit, choose **Claude Code** or **Codex**, select the model and available mode/effort controls, enter a prompt, and continue the conversation normally.

Optional global installation:

```bash
./install.sh
airlift open
```

## What setup installs

Airlift installs these packages into the Air user's `~/.local` directory when they are missing:

- `@openai/codex`
- `@anthropic-ai/claude-code`
- `yepanywhere`

If the Air does not already have Node.js 22 or newer, Airlift downloads the current Node.js LTS release from nodejs.org, verifies its SHA-256 checksum, and installs it under `~/.airlift/runtime`. No administrator access is required.

To redo authentication:

```bash
./airlift login codex
./airlift login claude
```

## Different hostname or SSH alias

```bash
./airlift setup offload@192.168.1.42 --alias dylan-air
```

For access away from the local network, connect both Macs with a private mesh VPN such as Tailscale and keep using normal SSH. Do not expose port 22 or the cockpit port directly from the router.

## Know which account you are spending

The cockpit's provider picker runs whichever account each agent is signed in as on
the Air. If the Air is a borrowed machine, an agent may already be signed in as its
owner, and selecting that provider spends the owner's quota under the owner's
identity.

`./airlift doctor` names the account behind each agent and warns when Codex and
Claude are signed in as different accounts:

```
Agents
  Codex:   codex-cli 0.128.0
  Auth:    owner@example.com (pro)
  Claude:  2.1.201 (Claude Code)
  Auth:    you@example.com (max)

  ! Codex and Claude are signed in as DIFFERENT accounts.
```

Re-authenticate the odd one out with `./airlift login codex` or
`./airlift login claude`. Note that signing in replaces the account for that agent
across the whole Air user, including the owner's own use of that CLI.

## Keeping the Air awake

`./airlift awake` registers the keep-awake assertion as a launchd agent
(`com.airlift.keepawake`), so it **restarts after a reboot or logout**, not just
when the assertion crashes. A lone `caffeinate` is a single point of failure: if
it exits, the Air sleeps and every running agent stops. The launchd agent
supervises it and re-registers on boot; where launchd is unavailable it falls
back to a nohup supervisor. `./airlift open` re-asserts keep-awake every time, so
the daily command is enough to keep the worker awake.

`./airlift doctor` verifies the live `pmset` assertion rather than a PID file, and
says so loudly when nothing is holding the Air awake — and whether it will survive
a reboot. The assertion only holds on AC power, so keep the Air plugged in.
`./airlift sleep` bootouts the agent and removes the plist, so keep-awake stays
off until you run `awake` again.

## Staying connected

The `open` tunnel is supervised by a Pro-side watchdog: if the Air sleeps or
Wi-Fi drops, the watchdog re-establishes the SSH forward automatically (within
~15 seconds), so `127.0.0.1:3400` keeps working without re-running `open`.
`./airlift stop` (or `shutdown`) stops the watchdog along with the tunnel. Opt out
with `AIRLIFT_TUNNEL_KEEPALIVE=0`.

`./airlift doctor` reports whether the cockpit is actually serving on the Air and
whether the Pro → Air tunnel is live, not just that the binaries are installed.

## Choosing the session model

Set the model new sessions start with, once, instead of picking it every time:

```bash
./airlift model                       # show the current default + available models
./airlift model opus --effort xhigh   # new sessions start on Opus, extra-high effort
./airlift model sonnet                # switch the default; other settings untouched
```

It writes the cockpit's `newSessionDefaults` (a read-modify-write, so your
permission mode, thinking, and other session defaults are preserved). Already-open
sessions keep their model. `--thinking` and `--provider` are also accepted.

## Security defaults

- OpenSSH is the only network entry point.
- `ForwardAgent no` prevents the Air from using Dylan's Pro SSH agent.
- Yep Anywhere binds to `127.0.0.1` on the Air.
- The browser reaches it through an SSH local forward to `127.0.0.1` on the Pro.
- Host-key verification remains enabled.
- The setup edits only a marked SSH config block and keeps `~/.ssh/config.airlift.bak`.

For the strongest boundary, create a standard non-admin `offload` user on the Air and keep unrelated personal credentials out of that account.

## Open-source foundation

- [Yep Anywhere](https://github.com/kzahel/yepanywhere) — MIT
- [OpenAI Codex CLI](https://github.com/openai/codex) — Apache-2.0
- [Claude Code](https://github.com/anthropics/claude-code) — Anthropic's official CLI
- OpenSSH — included with macOS

Airlift does not vendor or modify these projects.

## Troubleshooting

Run:

```bash
./airlift doctor
```

Common failures:

- **Connection refused:** enable Remote Login on the Air.
- **Air disappears:** keep it plugged in and awake. Closing a Mac laptop lid normally suspends it unless using a supported clamshell setup.
- **Sign-in required:** run `./airlift login codex` or `./airlift login claude`.
- **Private clone fails:** authenticate GitHub separately on the Air. Airlift intentionally does not forward Dylan's Pro credentials.
- **Local port 3400 is busy:** run `./airlift open --local-port 3401`.

## License

MIT
