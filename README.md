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
./airlift doctor                       # Check SSH, agents, auth, disk, and power
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
