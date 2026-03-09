# FakeTLS Notes

## Core rule

FakeTLS is not generic HTTPS reverse proxying. MTProxy must own the public client port, usually `443`.

## What MTProxy needs

1. A domain that resolves to the server
2. TLS-mode enabled with `-D <domain>`
3. A local HTTPS endpoint that answers for that domain so MTProxy can learn TLS handshake characteristics

## Practical deployment patterns

### Cleanest

- dedicated VPS or dedicated IP
- MTProxy owns public `443`
- separate web service elsewhere

### Single-host compromise

- public `443` goes to MTProxy
- web server is moved to another public port such as `4443`
- the same web server also listens on `127.0.0.1:443`
- `/etc/hosts` resolves the chosen domain to `127.0.0.1` locally

This is the pattern supported by `install.sh --local-tls-proxy nginx --local-tls-port 4443`.

## Caveats

- Keep the design explicit. Do not pretend `nginx` is acting as a normal reverse proxy for MTProxy TLS transport.
- Upstream may log warnings about incomplete handshake emulation depending on the domain characteristics.
- If your domain or certificate changes, restart `mtproxy` and verify logs again.
