# nix-excaliself

Nix flake for [Excaliself](https://excaliself.com) — a self-hosted, collaborative
Excalidraw-style whiteboard ([upstream](https://github.com/maciekzygmunt/excaliself),
MIT, currently v0.9.0). You get a package, a NixOS module, and a throwaway demo VM.

## Try it

From the repo root, on a Linux machine:

```bash
nix run .#demo-vm
```

A NixOS VM (~2 GB RAM) boots and prints its log in your terminal, ending at a root
shell. PostgreSQL, migrations and the auth secret are all automatic — nothing to
configure. Open http://localhost:3000 in your host browser and sign up.

- Needs Nix with flakes enabled, on Linux. The VM uses KVM when available;
  without it, it falls back to software emulation and boots slowly.
- Host port 3000 must be free — the VM forwards it to 127.0.0.1:3000.
- Quit with `Ctrl-A x`.
- The VM is stateless: no disk, every run starts pristine. Quitting destroys
  all boards and accounts.
- `nix build .#demo-vm` builds the VM without booting it.

## NixOS module

```nix
# flake-based host
{
  inputs.excaliself.url = "github:debling/nix-excaliself";

  outputs = { self, nixpkgs, excaliself }: {
    nixosConfigurations.draw = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        excaliself.nixosModules.default
        {
          services.excaliself = {
            enable = true;
            nginx.domain = "draw.example.com"; # ACME cert + websocket-ready proxy
            baseUrl = "https://draw.example.com";
          };
          security.acme.acceptTerms = true; # nginx.enableACME defaults to true
          security.acme.defaults.email = "you@example.com";
        }
      ];
    };
  };
}
```

That's it. Local PostgreSQL is provisioned, migrations run on boot, and
`BETTER_AUTH_SECRET` is generated on first boot (or point `authSecretFile` at
your own).

Options that matter:

- `databaseUrl` — `"local"` (default; provisions local PostgreSQL over its unix
  socket) or a full `postgres://…` URL. Put `DATABASE_URL` in `environmentFile`
  to keep credentials out of the Nix store.
- `environmentFile` — systemd EnvironmentFile for secrets (SSO client secrets,
  `DATABASE_URL`).
- `extraEnvironment` — plain env vars, e.g. `GOOGLE_CLIENT_ID`,
  `SSO_ALLOWED_DOMAINS`. Single sign-on is just the app's env vars — see the
  [upstream SSO docs](https://excaliself.com/docs/single-sign-on/).
- `authSecretFile` — defaults to `/var/lib/excaliself/auth-secret`,
  auto-generated.
- `port` (3000), `host` (`127.0.0.1`; nginx proxies locally), `package`
  (defaults to this flake's package).
- `nginx.forceSSL` / `nginx.enableACME` — both default to `true`; ACME needs
  the two `security.acme` lines above.

The service runs as its own user with `ProtectSystem=strict`, `ProtectHome`,
`PrivateTmp` and `NoNewPrivileges`.

## Binary cache

Speeds up cold machines and CI by ~2 minutes of building: run `cachix use nix-excaliself` first (needs a free [cachix.org](https://cachix.org) account). The cache is filled from CI on every release tag.

## Package only

Not on NixOS? `nix build .#` builds the app (`result/bin/excaliself`); bring
your own PostgreSQL, `DATABASE_URL` and `BETTER_AUTH_SECRET` (min 32 chars).
`nix flake check` runs a NixOS VM test that boots the module and expects a 200
from `/api/health`.

## License

MIT. The packaged [Excaliself app](https://github.com/maciekzygmunt/excaliself) is MIT as well.
