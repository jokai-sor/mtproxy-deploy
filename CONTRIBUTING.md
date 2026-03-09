# Contributing

## Principles

- Keep the project focused on standalone MTProxy deployment
- Avoid adding features unrelated to MTProxy operations
- Prefer explicit, boring deployment logic over clever multiplexing

## Before opening a change

1. Run:

```bash
bash -n scripts/install.sh
bash -n scripts/uninstall.sh
```

2. If you changed docs, make sure examples match the current CLI flags.

3. If you changed FakeTLS behavior, test both:
- service start/restart
- generated Telegram link format
