# muse-join

One command gives a Muse fleet node **permanent, self-healing SSH access**.

```bash
curl -fsSL https://raw.githubusercontent.com/SuperInstance/muse-join/main/join.sh | bash -s -- <reverse-port>
```

That's the whole UX. No second command. No babysitting.

## The model

The fleet is a hub and spokes. The hub is an always-on box (currently Oracle Cloud).
Each node dials **out** to the hub and holds open a reverse tunnel (`-R <port>:localhost:22`),
so the hub — and Muse through it — can reach back into the node.

- The node never accepts inbound connections. Its firewall stays closed.
- The tunnel redials on every boot (`@reboot` cron) and autossh heals mid-session drops.
- Each node gets a **dedicated keypair** (`~/.ssh/muse_fleet_ed25519`). Your own keys are never touched.
- The private key never leaves the node. Only the public key is published (via pastebin URL you forward to Muse).

## What Muse does on its side (none of this is yours)

1. Assigns the reverse port (registry in `PORTS.md` — no collisions).
2. Fetches your public key from the URL and appends it to the hub's `authorized_keys`
   with restrictions (`no-pty,no-X11-forwarding,no-agent-forwarding`).
3. Verifies the lane from the hub side and watches it with the fleet lane-watcher.
4. Revokes by deleting one line when a node leaves (`join.sh --uninstall` tells you to say so).

## Join protocol

Self-healing is installed **at join time, never after a failure**.
A node that joins without the `@reboot` cron is a node that will go dark
the first time it sleeps — and then cost a human their evening.
See `JOIN-PROTOCOL.md`.

## Security notes

- Trust-on-first-use for the hub host key, then fingerprint-verified against the
  pinned value in `join.sh`. A mismatch aborts loudly. If the hub is ever rebuilt,
  the pinned fingerprint here must be updated out-of-band first.
- The pastebin carries a **public** key. Public keys are designed to be shared;
  GitHub displays thousands of them. The private key is generated with an empty
  passphrase and `600` permissions and never transmitted.
- Uninstall: `curl -fsSL .../join.sh | bash -s -- --uninstall`

## Files

- `join.sh` — the installer. The only file that matters.
- `PORTS.md` — reverse-port registry. Muse assigns; collisions are a bug.
- `JOIN-PROTOCOL.md` — the standing rule: self-healing at join time.
