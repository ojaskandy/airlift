# Airlift

Use a spare Mac as the compute host for engineering agents while keeping the control surface on your main Mac.

Airlift does not invent a new remote-agent protocol. It configures the two proven paths that already have the right interaction model:

- **Native path:** Codex Remote SSH. The Codex desktop app on the MacBook Pro starts the Codex app server through SSH on the MacBook Air.
- **Open-source path:** OpenCode Web, bound to `127.0.0.1` on the Air and reached through a private SSH tunnel.

In both paths, repository files, shell commands, tests, worktrees, credentials, and compute stay on the Air.

## What Dylan gets

- The familiar Codex project/task surface on the Pro.
- Model and reasoning controls.
- Standard/Fast mode in Codex.
- Plan/Build modes and reasoning variants in OpenCode.
- Streamed commands, diffs, test results, approvals, and task history.
- No public command server and no router port forwarding.
- A dedicated SSH key with agent forwarding disabled.

## Two-minute setup

On the **MacBook Air**, do the one macOS step scripts cannot safely do:

1. Open **System Settings → General → Sharing**.
2. Turn on **Remote Login**.
3. Under “Allow access for,” select only the user that should run engineering tasks.
4. Keep the Air plugged in and awake while it is acting as the worker.

On **Dylan's MacBook Pro**:

```bash
git clone https://github.com/ojaskandy/airlift.git
cd airlift
./airlift setup dylan@Dylans-MacBook-Air.local
./airlift codex
```

The setup command:

1. Creates a dedicated Ed25519 key.
2. Adds a concrete `spare-air` host to `~/.ssh/config`.
3. Copies the key after one Mac password prompt.
4. Installs Codex and OpenCode on the Air if needed.
5. Ensures both tools are on the remote login-shell `PATH`.
6. Runs the one-time Codex device login if needed.
7. Starts a macOS keep-awake assertion that applies while the Air is on AC power.

Codex opens at **Settings → Connections → SSH**. Select `spare-air`, choose a project folder on the Air, and send the task.

## Put a repository on the Air

Clone directly on the worker:

```bash
./airlift clone git@github.com:your-org/your-repo.git
./airlift codex
```

For private GitHub repositories, authenticate GitHub on the Air first:

```bash
./airlift shell
gh auth login --web
gh auth setup-git
exit
```

Codex can also hand off an active task and its Git state between matching projects on the Pro and Air. It creates or reuses worktrees rather than synchronizing a mutable checkout with `rsync`.

## Fully open-source browser surface

OpenCode and its web UI are MIT licensed. Launch the UI from the Pro while the server and agent run on the Air:

```bash
./airlift web '~/Developer/your-repo'
```

This opens `http://127.0.0.1:4096` on the Pro through an SSH local forward. The OpenCode server remains bound to loopback on the Air.

Inside OpenCode:

- Switch between Plan and Build.
- Choose providers and models.
- Cycle reasoning variants: OpenAI `none` through `xhigh`, Anthropic `high`/`max`, and provider-specific variants.
- Use `/connect` once to add a model provider.

Stop the browser session later:

```bash
./airlift stop
```

## Useful commands

```bash
./airlift doctor                 # SSH, app, auth, versions, disk, and power
./airlift shell                  # Open a shell on the Air
./airlift awake                  # Keep the Air awake while it is on AC power
./airlift sleep                  # Release Airlift's keep-awake assertion
./airlift login codex            # Redo Codex device auth on the Air
./airlift login opencode         # Configure an OpenCode provider
./airlift config                 # Show the saved connection
./airlift web --local-port 4097  # Avoid a local port conflict
```

Optional global installation:

```bash
./install.sh
airlift doctor
```

## Different Air hostname or SSH alias

```bash
./airlift setup offload@192.168.1.42 --alias dylan-air
```

Codex auto-discovers concrete aliases from `~/.ssh/config`; wildcard-only hosts are not enough.

## Security defaults

- OpenSSH is the only network entry point.
- `ForwardAgent no` prevents the Air from using Dylan's Pro SSH agent.
- OpenCode binds only to `127.0.0.1` and is exposed to the Pro only through a local SSH forward.
- Codex app-server transports are never exposed directly.
- Host key verification remains enabled.
- The setup writes only a marked host block and keeps `~/.ssh/config.airlift.bak`.

For access away from the local network, use a private mesh VPN such as Tailscale and continue using ordinary SSH over it. Do not forward port 22 or an agent HTTP port from the router to the public internet.

For the strongest boundary, create a standard non-admin `offload` user on the Air and keep unrelated personal credentials out of that account.

## Open-source foundation

- [OpenAI Codex CLI](https://github.com/openai/codex) — Apache-2.0
- [OpenCode](https://github.com/anomalyco/opencode) — MIT
- [OpenChamber](https://github.com/openchamber/openchamber) — MIT, a richer optional OpenCode desktop client
- OpenSSH, included with macOS

Airlift is a bootstrap and lifecycle wrapper. It does not vendor or modify those projects.

## Troubleshooting

Run:

```bash
./airlift doctor
```

Common failures:

- **Connection refused:** enable Remote Login on the Air.
- **Air disappears:** keep it plugged in and awake. Closing a Mac laptop lid normally suspends it unless using a supported clamshell setup.
- **Codex host not listed:** the SSH entry must be a concrete `Host` alias; rerun `./airlift setup`.
- **Codex cannot start remotely:** run `./airlift shell`, then `codex --version` and `codex login status`. Airlift adds Homebrew and agent install directories to `.zprofile`.
- **Private clone fails:** authenticate GitHub separately on the Air. Airlift intentionally does not forward Dylan's Pro credentials.

## License

MIT
