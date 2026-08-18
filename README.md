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

## Install v0.4 (this hop release)

Clone the `v0.4` branch. Do not clone `main`; that is the older one-worker
cockpit.

**Controller** (the laptop that should stay light — Dylan's Mac):

```bash
git clone --branch v0.4 https://github.com/ojaskandy/airlift.git ~/airlift
cd ~/airlift
./install.sh
export PATH="$HOME/.local/bin:$PATH"
airlift metrics install
```

That installs `airlift` plus `claude` / `codex` shims. After the pool is joined,
those two commands hop to a spare Mac by themselves. `airlift metrics install`
enables the controller's CPU temperature and GPU stats on the board. If every
worker is asleep, routed tasks run locally and say so.

**Workers** (spare Macs that will take the load). Run this on each one, not
`./install.sh`:

```bash
git clone --branch v0.4 https://github.com/ojaskandy/airlift.git ~/airlift
cd ~/airlift
./install-worker.sh
```

The worker installer asks macOS to enable Remote Login, then prints a join
command. Run each printed command on the controller, then check the pool:

```bash
airlift join <user>@Spare-Air.local --alias spare
airlift nodes
airlift dashboard
```

`airlift dashboard` opens a localhost board of every Mac in the pool: online
state, load, RAM, CPU temperature, GPU activity/power, disk, power state,
running `claude`/`codex` tasks, and a feed of where hops went. It does not leave
this computer. Ctrl-C in that terminal stops it.

One-command worker install (same `v0.4` tree):

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ojaskandy/airlift/v0.4/install-worker.sh)"
```

Preview without changing the Mac:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ojaskandy/airlift/v0.4/install-worker.sh)" -- --dry-run
```

`setup` is the compatible one-worker path from Airlift v0.2; `join` adds more
workers to the same local pool. Cursor's in-editor Agent still runs on the
controller. `./install.sh` belongs on the controller only; workers that also
install those shims can hop into themselves.

The worker bootstrap must run locally once: a controller cannot connect over
SSH until Remote Login is enabled. Airlift uses Apple's supported
[`systemsetup -setremotelogin on`](https://support.apple.com/guide/remote-desktop/about-systemsetup-apd95406b8d/mac)
command and preserves the worker's existing allowed-users policy, adding only
the user running the installer when necessary. Review that later under
**System Settings → General → Sharing → Remote Login**.

## Route a task

`claude` and `codex` on the controller copy the current git worktree to the
chosen Mac only when that Mac scores better than the controller, run there, and
copy edits back. The controller itself is part of automatic selection. You do
not have to pre-clone the repo onto every worker for that hop. Start the agent
from the project directory.
Launches from your home directory use an empty temporary worker folder, so
Airlift never copies the entire home folder to another Mac.

Remote jobs never inherit the worker owner's Claude or Codex login. Airlift
stages the controller's authentication in a private per-job directory and
removes it when the job exits. If controller authentication cannot be staged,
automatic routing stays local and an explicitly pinned remote job is refused.

`airlift run` is the explicit one-shot path. To pin a shared checkout on every
worker instead of copying per job:

```bash
./airlift clone git@github.com:your-org/your-repo.git --worker all
```

Then send a task. Airlift probes the pool in parallel, chooses the least-used
Mac, and streams the agent's output back over SSH:

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
- RAM pressure;
- CPU temperature and thermal pressure when the metrics sampler is installed;
- GPU activity/power when the metrics sampler is installed;
- configured concurrent slots; and
- whether the requested project directory exists.

Offline workers and workers missing the project are excluded. The remaining
workers are scored by active work divided by slots, with load per CPU core as a
secondary pressure signal. High RAM usage, high CPU temperature, non-nominal
thermal pressure, and high GPU activity add penalties so a struggling Mac stops
winning just because it has no current Airlift lease. Ties are deterministic.
`--slots auto` allocates roughly one slot per four logical CPU cores; set an
explicit value when a beefy Mac should accept more concurrent work.

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
./airlift dashboard                              # Localhost board: RAM, temp, GPU, disk, tasks
./airlift metrics install                        # Enable CPU temp/GPU sampler on this Mac
claude -p 'Fix the failing unit test'            # Hops off this Mac when a worker is free
codex exec -C ~/Developer/your-repo -            # Same
./airlift run --project PATH 'task'              # Explicit one-shot hop (Codex)
./airlift run --agent claude --project PATH 'task'
./airlift local on|off                           # Force this Mac / resume hopping
./airlift open PATH                              # Auto-route a new cockpit
./airlift clone GIT_URL --worker all             # Prepare every worker
./airlift forget spare-air                       # Remove a retired worker
./airlift doctor --worker beefy                   # Check one worker
./airlift shell beefy                             # Normal worker shell
./airlift stop                                    # Close the active tunnel
```

Optional global installation:

```bash
./install.sh
airlift nodes
```

Without cloning the repository first:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ojaskandy/airlift/v0.4/install.sh)"
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

CPU temperature and live GPU power/activity come from Apple's `powermetrics`,
which requires administrator access. `install-worker.sh` installs a root-owned
LaunchDaemon sampler that writes a small readable cache to
`~/.airlift/metrics/latest.tsv`; normal dashboard refreshes read that cache and
do not ask for a password. On a controller Mac, run `airlift metrics install`
once if you also want this Mac's local temperature/GPU stats on the board.

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
- **Retired worker:** run `airlift forget WORKER_NAME` to remove its saved
  route from this controller.
- **Tailscale worker is offline:** confirm both devices are connected and run
  `tailscale ping WORKER_NAME` when the CLI is available.
- **Project missing:** `claude` / `codex` hop copies the worktree. For `airlift
  run` against a shared checkout, use the same path or `clone --worker all`.
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
