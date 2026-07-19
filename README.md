# Airlift

Turn a few trusted Macs into one private coding pool for Codex and Claude Code.

Airlift routes a new task to the least-used reachable Mac, streams the answer
back to the person who sent it, and keeps interactive browser sessions pinned to
the Mac that owns their files and agent history. Three people can share five
Macs, or friends can lend one high-capacity Mac to the pool without exposing an
agent server to the public internet.

Airlift is a small SSH bootstrap, scheduler, and lifecycle wrapper around the
real [Codex CLI](https://github.com/openai/codex),
[Claude Code](https://docs.anthropic.com/en/docs/claude-code), and
[Yep Anywhere](https://github.com/kzahel/yepanywhere). It does not proxy prompts
through a new AI provider.

## Send this to Dylan

On every Mac that will do work, turn on:

**System Settings → General → Sharing → Remote Login**

Then run this on Dylan's MacBook Pro:

```bash
git clone https://github.com/ojaskandy/airlift.git
cd airlift

# Ojas's spare Air
./airlift setup <air-username>@Dylans-MacBook-Air.local

# Add more workers whenever they become available
./airlift join <username>@Beefy-Mac.local --alias beefy --slots 6

./airlift nodes
./airlift open '~/Developer/your-project'
```

Replace each username and hostname with the values shown on that worker Mac.
`setup` is the compatible one-worker path from Airlift v0.2; `join` adds more
workers to the same local pool.

## Route a task

Put the checkout at the same logical path on every eligible worker:

```bash
./airlift clone git@github.com:your-org/your-repo.git --worker all
```

Then send a task. Airlift probes the pool in parallel, chooses the least-used
Mac that has the checkout, and streams the agent's output back over SSH:

```bash
./airlift run \
  --agent codex \
  --project '~/Developer/your-repo' \
  'Fix the failing unit test and run the narrow test suite'
```

Claude Code works the same way:

```bash
./airlift run \
  --agent claude \
  --project '~/Developer/your-repo' \
  'Review the parser and fix the malformed-input bug'
```

Pin a task when you need a particular Mac:

```bash
./airlift run --worker beefy --project '~/Developer/your-repo' 'Run the full benchmark'
```

## Open the browser cockpit

```bash
./airlift open '~/Developer/your-repo'
```

`open` chooses the least-used eligible worker before launching Yep Anywhere.
That browser cockpit then stays pinned to the chosen Mac. Follow-up messages
cannot hop to a different worker because the session history, checkout, running
processes, approvals, and credentials live on the original worker.

Inside the cockpit, choose Codex or Claude Code, select the model and supported
mode/effort controls, enter a prompt, and continue the conversation normally.
Closing the browser does not stop active work.

## Share five Macs across three people

Each person clones Airlift on their own controller Mac and runs `airlift join`
for every worker they are allowed to use. Each controller installs its own SSH
public key; Airlift never shares one person's private key or forwards their SSH
agent.

For example, each teammate can build the same pool:

```bash
./airlift join worker@spare-air --alias spare-air --slots 2
./airlift join worker@mac-studio --alias studio --slots 8
./airlift join worker@joves-mac --alias jove --slots 3
./airlift nodes
```

All controllers query live load at dispatch time, so work started by one person
affects the next person's routing decision. There is no central Airlift account,
cloud scheduler, shared secret, or public command endpoint.

Pool membership is local to each controller. Adding a worker on one person's
Mac does not silently grant it to everyone else; the worker owner must authorize
each person's SSH key.

## Use Airlift away from the same Wi-Fi

Yes. The recommended path is a private Tailscale network.

1. Install and sign in to Tailscale on each controller and worker.
2. Put trusted teammates in the same tailnet, or share only the worker Mac with
   them.
3. Keep normal macOS **Remote Login** enabled on each worker.
4. Join the worker using its Tailscale MagicDNS name or `100.x` address:

```bash
./airlift join worker@mac-studio \
  --alias studio \
  --slots 8 \
  --transport tailscale
```

Tailscale gives the Mac a stable private address across networks. Airlift still
uses normal SSH, and Yep Anywhere still binds to `127.0.0.1` on the worker; the
browser reaches it through Airlift's local SSH tunnel. Do not expose port 22 or
the cockpit port through a router.

See Tailscale's official guides for
[connecting devices](https://tailscale.com/kb/1452/connect-to-devices) and
[sharing one machine](https://tailscale.com/kb/1084/sharing).

Yep Anywhere also offers its own end-to-end encrypted relay for a single server.
Airlift's automatic multi-worker routing still needs SSH reachability to each
worker, so Tailscale is the simpler pool transport.

## How least-used routing works

Each dispatch asks every configured worker for:

- active Airlift jobs;
- other running Codex and Claude processes;
- one-minute system load;
- logical CPU count;
- configured concurrent slots; and
- whether the requested project directory exists.

Offline workers and workers missing the project are excluded. The remaining
workers are scored by active work divided by slots, with load per CPU core as a
secondary pressure signal. Ties are deterministic. `--slots auto` allocates
roughly one slot per four logical CPU cores; set an explicit value when a beefy
Mac should accept more concurrent work.

Routing is deliberately best-effort and decentralized. Two people dispatching
at the exact same instant can briefly see the same score. The job lease appears
as soon as the remote agent starts, so later dispatches observe the new load.

## Repositories and concurrent work

Every selected worker must have the repository and its own Git/provider
authentication. Airlift does not copy credentials between Macs.

Do not run multiple write-capable agents in the same checkout. Give concurrent
jobs distinct Git worktrees or distinct Conductor workspace paths, then pass
that path with `--project`. Capacity slots describe the whole Mac; they do not
make one Git working tree safe for concurrent edits.

For a private GitHub repository, authenticate GitHub once on each worker:

```bash
./airlift shell beefy
gh auth login --web
gh auth setup-git
exit
```

## Daily commands

```bash
./airlift nodes                                  # Live load across the pool
./airlift run --project PATH 'task'              # Auto-route a Codex task
./airlift run --agent claude --project PATH 'task'
./airlift open PATH                              # Auto-route a new cockpit
./airlift open PATH --worker beefy               # Pin a cockpit
./airlift clone GIT_URL --worker all             # Prepare every worker
./airlift doctor --worker beefy                   # Check one worker
./airlift login codex --worker beefy              # Redo provider auth
./airlift shell beefy                             # Normal worker shell
./airlift stop                                    # Close the active tunnel
./airlift shutdown --worker beefy                 # Stop that cockpit server
```

Optional global installation:

```bash
./install.sh
airlift nodes
```

## What `setup` and `join` install

When missing, Airlift installs these packages into the worker user's `~/.local`
directory:

- `@openai/codex`
- `@anthropic-ai/claude-code`
- `yepanywhere`

If the worker does not have Node.js 22 or newer, Airlift downloads the current
Node.js LTS release from nodejs.org, verifies its SHA-256 checksum, and installs
it under `~/.airlift/runtime`. No administrator access is required.

## Security and trust

- OpenSSH is the only worker entry point.
- `ForwardAgent no` prevents a worker from using the controller's SSH agent.
- Each controller has a dedicated `~/.ssh/airlift_ed25519` key.
- Yep Anywhere binds to worker loopback, never the LAN or tailnet interface.
- Host-key verification stays enabled.
- Setup edits only a marked SSH config block and saves
  `~/.ssh/config.airlift.bak`.
- Tailscale can carry SSH privately across networks without public port
  forwarding.

A worker executes agents under its configured macOS user. That user can read the
prompts, repository, and credentials available to those agents. Share workers
only with people you trust. For a stronger boundary, create a standard non-admin
`airlift` user on the worker and keep unrelated personal credentials out of that
account.

## Troubleshooting

Run:

```bash
./airlift nodes
./airlift doctor --worker WORKER_NAME
```

Common failures:

- **Offline:** wake the Mac and enable Remote Login.
- **Tailscale worker is offline:** confirm both devices are connected and run
  `tailscale ping WORKER_NAME` when the CLI is available.
- **Project missing:** use the same path on that worker or run `clone --worker
  all`.
- **Sign-in required:** run `login codex` or `login claude` for that worker.
- **Private clone fails:** authenticate GitHub separately on that worker.
- **Local port 3400 is busy:** run `open --local-port 3401`.
- **Mac sleeps:** keep a laptop plugged in; closing its lid normally suspends it
  unless it is in a supported clamshell setup.

## Open-source foundation

- [Yep Anywhere](https://github.com/kzahel/yepanywhere) — MIT
- [OpenAI Codex CLI](https://github.com/openai/codex) — Apache-2.0
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) — official CLI
- OpenSSH — included with macOS
- [Tailscale](https://tailscale.com/) — optional private network transport

Airlift does not vendor or modify these projects.

## License

MIT
