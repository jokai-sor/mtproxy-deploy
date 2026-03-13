# FakeTLS Notes

## How it works

mtg implements fake-TLS by acting as a proper TLS proxy: when a Telegram client connects,
mtg performs a real TLS handshake by connecting to the upstream domain and relaying the
certificate and all handshake records. The client sees a valid TLS session with a real
certificate, which satisfies strict TLS validation on all platforms (including Android).

The domain is encoded in the proxy secret (`ee<secret><hex_domain>`). Telegram clients
read the domain from the secret and send it as SNI in their TLS ClientHello.

## Core rule

mtg must own the public client port, usually `443`.

## What mtg needs

1. A domain with a valid TLS certificate reachable from the server
2. The domain encoded in the proxy secret via `mtg generate-secret --hex <domain>`

mtg connects to the domain at startup and on each client connection to obtain the real
TLS certificate. The domain does not need to resolve to the same server — a separate host
works fine.

## Practical deployment patterns

### Cleanest

- Dedicated VPS or dedicated IP
- mtg owns public `443`
- Domain resolves to a separate server (e.g., your website elsewhere)

### Single-host workaround

- Public `443` goes to mtg
- Web server moved to another public port (e.g., `4443`)
- Web server also listens on `127.0.0.1:443` for mtg to reach the certificate
- `/etc/hosts` resolves the chosen domain to `127.0.0.1` locally

This is supported by `install.sh --local-tls-proxy nginx --local-tls-port 4443`.

## Caveats

- If the domain certificate renews (e.g., Let's Encrypt), restart mtg so it picks up
  the new certificate on the next connection probe.
- The domain in the secret must match the domain actually served at the TLS endpoint.
  A mismatch will cause connection failures on clients that validate certificates.
