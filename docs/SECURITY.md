# Network security notes

- Strict host-key checking is the default.
- Password prompting is suppressed with `BatchMode=yes`; use keys, agents, or an SSH configuration approved by the administrator.
- SSH agent forwarding, X11 forwarding, TTY allocation and arbitrary port forwarding are not enabled.
- Remote command paths are single-quoted before interpolation.
- Remote publication uses a unique staging directory and a per-archive lock.
- SHA-256 manifests detect corruption but do not authenticate against deliberate manifest replacement. A future signed-manifest extension should use `ssh-keygen -Y sign` and an explicit namespace.
- `accept-new` is provided for controlled bootstrap only. It does not accept changed host keys.
