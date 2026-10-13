# Join protocol

Standing rule, learned the hard way (2026-10-08):

**Self-healing is installed at join time. Never after a failure.**

A node that joins with a one-shot manual tunnel is a node that WILL go dark
the first time it sleeps, reboots, or the network hiccups — and then it costs
a human their evening to resurrect. The HP lane died exactly this way:
manual tunnel, no autossh, no `@reboot` cron, zero supervision. The fix took
an hour of the one person's time the whole system exists to save.

So the checklist for every new node, before it is considered joined:

1. `join.sh` run — dedicated keypair, pastebin URL delivered to Muse.
2. Muse registers the public key on the hub (restricted `authorized_keys` entry).
3. `@reboot` cron confirmed present on the node.
4. autossh confirmed running (or plain-ssh fallback acknowledged).
5. Lane verified from the hub side: port answers, git-inbox claim works.
6. Port recorded in `PORTS.md`.

A node that hasn't passed all six isn't joined — it's visiting.
