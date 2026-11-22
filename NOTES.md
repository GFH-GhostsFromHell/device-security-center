# PROJECT ZT-01 / GHOST PROTOCOL — open items

## Not finished

- `SweepPanel` never calls `POST /api/zt01/case`, so a desktop case and a portal case are
  separate records, and the desktop never uploads its wrapped key.
- `GhostProtocolDesktop.takeOver` rebuilds the timer as 24 hours instead of using the one
  the sweep produced, so the takeover clock is wrong for any other window.
- `ghost.html` has no CSRF header handling; the cookie repository is configured but the
  scripts never read `XSRF-TOKEN`.

## Known behaviour

- Sealing deletes the original only after the sealed copy decrypts to the right byte count.
- Skip list: `.git`, `node_modules`, `target`, `build`, `dist`, `.venv`, `__pycache__`,
  `.idea`, `.gradle`, recycle bin, System Volume Information.
- Files over 64 MiB and empty files are skipped and counted.
- Gift card claims are eyeballed by an operator; only BTC gets chain checks, on testnet.
- An approval is burned when its window closes or a newer approval supersedes it.
