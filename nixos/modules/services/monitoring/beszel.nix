{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.beszel;
in
{
  options = {
    services.beszel = {
      enable = lib.mkEnableOption "Beszel.";

      package = lib.mkPackageOption pkgs "beszel" { };

      user = lib.mkOption {
        type = lib.types.str;
        default = "beszel";
        description = "User account under which the service runs.";
      };

      group = lib.mkOption {
        type = lib.types.str;
        default = "beszel";
        description = "Group under which the service runs.";
      };

      dataDir = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/beszel";
        description = "Data directory for the service.";
      };

      hub = lib.mkOption {
        type = lib.types.submodule {
          enable = lib.mkEnableOption "Beszel Hub.";

          options.port = lib.mkOption {
            type = lib.types.port;
            default = 8090;
            description = "Port to listen on.";
          };

          options.listenAddress = lib.mkOption {
            type = lib.types.str;
            default = "0.0.0.0";
            description = "Address to listen on.";
          };

          options.environment = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = { };
            description = ''
              Environment variables for the webserver.
              Examples: https://beszel.dev/guide/environment-variables#hub
            '';
          };

          options.environmentFile = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = ''
              Environment variables for the webserver (sourced from a file).
              Examples: https://beszel.dev/guide/environment-variables#hub
            '';
          };
        };
      };

      agent = lib.mkOption {
        type = lib.types.submodule {
          enable = lib.mkEnableOption "Beszel Agent.";

          options.port = lib.mkOption {
            type = lib.types.port;
            default = 45876;
            description = "Port to listen on.";
          };

          options.publicKey = lib.mkOption {
            type = lib.types.str;
            default = null;
            description = ''
              Public SSH key path for authentication.
              The value is displayed when adding a new system.
            '';
          };

          options.publicKeyFile = lib.mkOption {
            type = lib.types.path;
            default = null;
            description = ''
              Public SSH key path for authentication.
              The value is displayed when adding a new system.
            '';
          };

          options.environment = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = { };
            description = ''
              Environment variables for the agent.
              Examples: https://beszel.dev/guide/environment-variables#agent
            '';
          };

          options.environmentFile = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = ''
              Environment variables for the agent (sourced from a file).
              Examples: https://beszel.dev/guide/environment-variables#agent
            '';
          };
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.beszel ];

    users.users.beszel = lib.mkIf (cfg.user == "beszel") {
      description = "Service user for Beszel.";
      isSystemUser = true;
      createHome = false;
      home = cfg.dataDir;
      group = cfg.group;
    };

    users.groups.beszel = lib.mkIf (cfg.group == "beszel") {
      gid = config.ids.gids.beszel;
      members = [ cfg.user ];
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 ${cfg.user} ${cfg.group} -"
    ];

    systemd.services = {
      beszel-hub = {
        enable = cfg.hub.enable;
        description = "Beszel Hub Service";
        after = [ "network.target" ];
        serviceConfig = {
          User = cfg.user;
          Restart = "always";
          RestartSec = 5;
          WorkingDirectory = cfg.dataDir;
          Environment = lib.mapAttrsToList (k: v: "${k}=${v}") cfg.hub.environment;
          EnvironmentFile = cfg.hub.environmentFile;
          ExecStart = "${pkgs.beszel}/bin/beszel-hub serve --http ${cfg.hub.listenAddress}:${cfg.hub.port}";
        };
        wantedBy = [ "multi-user.target" ];
      };

      beszel-agent = {
        enable = cfg.agent.enable;
        description = "Beszel Agent Service";
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        serviceConfig = {
          Environment = lib.mapAttrsToList (k: v: "${k}=${v}") (
            cfg.agent.environment
            // lib.optionalAttrs (cfg.agent.publicKey != null) { KEY = cfg.agent.publicKey; }
            // lib.optionalAttrs (cfg.agent.publicKeyFile != null) { KEY_FILE = cfg.agent.publicKeyFile; }
          );
          EnvironmentFile = cfg.agent.environmentFile;
          User = cfg.user;
          Restart = "on-failure";
          RestartSec = 5;
          WorkingDirectory = cfg.dataDir;
          StateDirectory = "beszel-agent"; # TODO! Seriously check this
          ExecStart = "${pkgs.beszel}/bin/beszel-agent";

          # Security/sandboxing settings
          KeyringMode = "private";
          LockPersonality = "yes";
          NoNewPrivileges = "yes";
          ProtectClock = "yes";
          ProtectHome = "read-only";
          ProtectHostname = "yes";
          ProtectKernelLogs = "yes";
          ProtectSystem = "strict";
          RemoveIPC = "yes";
          RestrictSUIDSGID = true;
        };
        wantedBy = [ "multi-user.target" ];
      };
    };
  };
}
