# nix-excaliself

Nix flake for [Excaliself](https://excaliself.com) — a self-hosted, collaborative
Excalidraw-style whiteboard ([upstream](https://github.com/maciekzygmunt/excaliself),
MIT, currently v0.9.0). You get a package, a NixOS module, and a throwaway demo VM.

## Try it

From the repo root, on a Linux machine:

```bash
nix run github:debling/nix-excaliself#demo-vm
```

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
          services.excaliself.enable = true;
        }
      ];
    };
  };
}
```

That's it. Local PostgreSQL is provisioned, migrations run on boot, and
`BETTER_AUTH_SECRET` is generated on first boot (or point `authSecretFile` at
your own). The app listens on `http://localhost:3000`.

Options that matter:

- `databaseUrl`: `"local"` (default; provisions local PostgreSQL over its unix
  socket) or a full `postgres://…` URL. Put `DATABASE_URL` in `environmentFile`
  to keep credentials out of the Nix store.
- `environmentFile`: systemd EnvironmentFile for secrets (SSO client secrets,
  `DATABASE_URL`).
- `extraEnvironment`:  plain env vars, e.g. `GOOGLE_CLIENT_ID`,
  `SSO_ALLOWED_DOMAINS`. Single sign-on is just the app's env vars, see the
  [upstream SSO docs](https://excaliself.com/docs/single-sign-on/).
- `authSecretFile`: defaults to `/var/lib/excaliself/auth-secret`,
  auto-generated if not supplied.


## Reverse proxy, TLS and single sign-on

Point nginx at the service, websocket upgrades keep drawing sessions alive:

```nix
services.nginx.virtualHosts."draw.example.com" = {
  forceSSL = true;
  enableACME = true;
  locations."/" = {
    proxyPass = "http://127.0.0.1:3000";
    proxyWebsockets = true; # needed collaborative drawing
    extraConfig = "proxy_read_timeout 300s;";
  };
};
security.acme.acceptTerms = true;
security.acme.defaults.email = "you@example.com";

services.excaliself = {
  baseUrl = "https://draw.example.com";
  extraEnvironment = {
    GOOGLE_CLIENT_ID = "…";
    SSO_ALLOWED_DOMAINS = "example.com";
  };
  # put sensive credentials like GOOGLE_CLIENT_SECRET=...
  # checkout agenix or nix-sops to have those secrets be stored in a secure
  # manner inside your config
  environmentFile = "/run/secrets/excaliself";
};
```

Microsoft and others OIDC providers are configured the same way, with their own env
vars, see the [upstream SSO docs](https://excaliself.com/docs/single-sign-on/).

## License

MIT. The packaged [Excaliself app](https://github.com/maciekzygmunt/excaliself) is MIT as well.
