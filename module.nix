{ self }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.excaliself;
in
{
  options.services.excaliself = {
    enable = lib.mkEnableOption "excaliself, a self-hosted Excalidraw whiteboard";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalExpression "excaliself.packages.\${pkgs.stdenv.hostPlatform.system}.default";
      description = "Package providing excaliself.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "excaliself";
      description = ''
        User under which the service should run. If this is the default value,
        the user will be created, with the specified group as the primary
        group.
      '';
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "excaliself";
      description = "Group under which the service should run. If this is the default value, the group will be created.";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Interface for the server to listen on (the HOST environment variable).";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 3000;
      description = "Port the server listens on.";
    };

    baseUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        The public URL users open in the browser (BASE_URL), e.g.
        https://draw.example.com.
      '';
    };

    databaseUrl = lib.mkOption {
      type = lib.types.str;
      default = "local";
      description = ''
        DATABASE_URL. The literal string `local` provisions a database
        `excaliself` on `services.postgresql` and connects over its unix
        socket. Any other value is used verbatim. To keep credentials out of
        the Nix store, leave the value unset in {option}`environmentFile`:
        DATABASE_URL present there takes precedence.
      '';
    };

    authSecretFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/excaliself/auth-secret";
      description = ''
        File that contains the BETTER_AUTH_SECRET (at least 32 characters). If
        the file does not exist or is empty, a new secret is generated and
        saved here. If you point this outside `/var/lib/excaliself`, make it
        writable for `preStart`, e.g. add it to
        `systemd.services.excaliself.serviceConfig.ReadWritePaths`.
      '';
    };

    extraEnvironment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Extra environment variables for the server, e.g. `GOOGLE_CLIENT_ID` or `SSO_ALLOWED_DOMAINS`. Secrets belong in {option}`environmentFile`.";
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        {command}`systemd` {option}`EnvironmentFile` with secrets, e.g.
        GOOGLE_CLIENT_SECRET. Provide DATABASE_URL there to override
        {option}`databaseUrl`.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = lib.optionals (cfg.databaseUrl == "local") [
      {
        assertion = cfg.user == "excaliself";
        message = ''
          services.excaliself.databaseUrl = "local" requires
          services.excaliself.user to stay "excaliself": the PostgreSQL
          role/database is provisioned under that name and matched by peer
          authentication. Set an explicit databaseUrl for a custom user.
        '';
      }
    ];

    users.users = lib.optionalAttrs (cfg.user == "excaliself") {
      excaliself = {
        isSystemUser = true;
        group = cfg.group;
      };
    };

    users.groups = lib.optionalAttrs (cfg.group == "excaliself") { excaliself = { }; };

    systemd.tmpfiles.rules = [
      "f ${cfg.authSecretFile} 0600 ${cfg.user} ${cfg.group} -"
    ];

    services.postgresql = lib.mkIf (cfg.databaseUrl == "local") {
      enable = true;
      ensureDatabases = [ "excaliself" ];
      ensureUsers = [
        {
          name = "excaliself";
          ensureDBOwnership = true;
        }
      ];
    };

    systemd.services.excaliself = {
      description = "Excaliself, a self-hosted Excalidraw whiteboard";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ] ++ lib.optional (cfg.databaseUrl == "local") "postgresql.target";
      requires = lib.optional (cfg.databaseUrl == "local") "postgresql.target";

      environment = {
        HOST = cfg.host;
        PORT = toString cfg.port;
      } // lib.optionalAttrs (cfg.baseUrl != null) { BASE_URL = cfg.baseUrl; } // cfg.extraEnvironment;

      preStart = ''
        if [ ! -s ${lib.escapeShellArg cfg.authSecretFile} ]; then
          ${lib.getExe pkgs.openssl} rand -hex 32 > ${lib.escapeShellArg cfg.authSecretFile}
        fi
      '';

      script = ''
        BETTER_AUTH_SECRET="$(head -n1 ${lib.escapeShellArg cfg.authSecretFile})"
        export BETTER_AUTH_SECRET

        if [ -z "''${DATABASE_URL:-}" ]; then
          export DATABASE_URL=${lib.escapeShellArg (
            if cfg.databaseUrl == "local" then
              "postgres://localhost/excaliself?host=/run/postgresql"
            else
              cfg.databaseUrl
          )}
          ${lib.optionalString (cfg.databaseUrl == "local") ''
            export PGSSLMODE="''${PGSSLMODE:-disable}"
          ''}
        fi

        exec ${lib.getExe cfg.package}
      '';

      serviceConfig = {
        User = cfg.user;
        Group = cfg.group;
        Restart = "always";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        UMask = "0007";
        StateDirectory = "excaliself";
        EnvironmentFile = lib.mkIf (cfg.environmentFile != null) [ cfg.environmentFile ];
      };
    };
  };
}
