# Level-triggered nginx provider for the http/v1 contract: renders server
# blocks from /run/flakelet/exports into an include dir and reloads nginx.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.flakelet-nginx;

  render = pkgs.writeScriptBin "flakelet-nginx-render" (
    "#!${pkgs.python3}/bin/python3\n"
    + builtins.replaceStrings
      [
        "@exportsDir@"
        "@certificate@"
        "@key@"
        "@listenAddresses@"
      ]
      [
        (toString cfg.exportsDir)
        (if cfg.tls != null then cfg.tls.certificate else "")
        (if cfg.tls != null then cfg.tls.key else "")
        (builtins.toJSON cfg.listenAddresses)
      ]
      (builtins.readFile ./render.py)
  );
in
{
  options.services.flakelet-nginx = {
    enable = lib.mkEnableOption "the nginx provider for the http/v1 flakelet contract";
    listenAddresses = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = config.services.nginx.defaultListenAddresses;
      defaultText = lib.literalExpression "config.services.nginx.defaultListenAddresses";
      description = "Addresses the rendered vhosts listen on. Must match the sockets the other vhosts bind.";
    };
    exportsDir = lib.mkOption {
      type = lib.types.path;
      default = "/run/flakelet/exports";
      description = "Directory of published flakelet exports.";
    };
    tls = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.submodule {
          options = {
            certificate = lib.mkOption {
              type = lib.types.str;
              description = "Certificate (fullchain) path; @host@ expands to the vhost name.";
            };
            key = lib.mkOption {
              type = lib.types.str;
              description = "Private key path; @host@ expands to the vhost name.";
            };
          };
        }
      );
      default = null;
      example = lib.literalExpression ''
        {
          # Per-site ACME; a fixed path serves one wildcard cert for all vhosts.
          certificate = "/var/lib/acme/@host@/fullchain.pem";
          key = "/var/lib/acme/@host@/key.pem";
        }
      '';
      description = "Serve vhosts over TLS; null = plain http.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.etc."flakelet/providers.d/http-v1.json".text = builtins.toJSON {
      contract = "http/v1";
    };

    # Guest in the host nginx: NixOS-defined vhosts and rendered ones
    # coexist; only a duplicate server_name conflicts (nginx warns).
    services.nginx = {
      enable = lib.mkDefault true;
      appendHttpConfig = "include /run/flakelet-nginx/*.conf;";
    };

    systemd.services.flakelet-nginx-render = {
      description = "render nginx config from flakelet http/v1 exports";
      wantedBy = [ "multi-user.target" ];
      before = [ "nginx.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe render;
      };
    };

    systemd.paths.flakelet-nginx-render = {
      wantedBy = [ "multi-user.target" ];
      pathConfig.PathChanged = cfg.exportsDir;
    };
  };
}
