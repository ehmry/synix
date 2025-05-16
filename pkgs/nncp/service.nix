{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    getExe
    mkDefault
    mkOption
    types
    ;
  writeExeclineScript = pkgs.execline.passthru.writeScript;
  settingsFormat = pkgs.formats.json { };

  cfg = config.nncp;

  nncpCfgFile = "/run/nncp.${cfg.name}.json";
  jsonCfgFile = settingsFormat.generate "nncp.json" cfg.settings;

in
{
  _class = "service";
  options.nncp = {
    name = mkOption {
      type = types.str;
      description = ''
        Name used to distinguish this NNCP node from other local nodes.
      '';
    };

    package = mkOption {
      description = "Package to use for this NNCP node.";
      type = types.package;
    };

    group = mkOption {
      type = types.str;
      default = "uucp";
      description = ''
        The group under which NNCP files shall be owned.
        Any member of this group may access the secret keys
        of this NNCP node.
      '';
    };

    secrets = mkOption {
      type = with types; listOf str;
      example = [ "/run/keys/nncp.hjson" ];
      description = ''
        A list of paths to NNCP configuration files that should not be
        in the Nix store. These files are layered on top of the values of
        `nncp.settings`.
      '';
    };

    settings = mkOption {
      type = settingsFormat.type;
      description = ''
        NNCP configuration, see
        <http://www.nncpgo.org/Configuration.html>.
        At runtime these settings will be overlayed by the contents of
        `nncp.secrets` into the node configuration file . Node keypairs
        go in `secrets`, do not specify them in `settings` as they will be
        leaked into `/nix/store`!
      '';
      default = { };
    };

  };

  config = {

    nncp.settings = {
      spool = mkDefault "/var/spool/nncp-${cfg.name}";
      log = mkDefault "/var/spool/nncp-${cfg.name}/log";
    };

    services.tmpfiles.settings.nncp =
      let
        rule.d = {
          mode = "0770";
          user = "root";
          inherit (cfg) group;
        };
      in
      {
        ${cfg.settings.spool} = rule;
        ${cfg.settings.log} = rule;
      };

    process = {
      executable = writeExeclineScript "nncp-config.el" "" ''
        umask 127
        foreground { rm -f ${nncpCfgFile} }
        pipeline -r {
          forx -E f { ${jsonCfgFile} ${toString config.programs.nncp.secrets} }
            redirfd -r 0 $f
            ${getExe pkgs.hjson-go} -c
        }
        if {
          redirfd -w 1 ${nncpCfgFile}
          # Combine and remove neighbors that would clash with the self identity.
          ${getExe pkgs.jq} --slurp --sort-keys
            "reduce .[] as $x ({}; . * $x) | .neigh.self as $self | del(.neigh [] | select(.id == $self.id) | select(. != $self))"
        }
        chgrp ${cfg.group} ${nncpCfgFile}
      '';
    };

    systemd.service = {
      description = "Generate NNCP configuration";
      wantedBy = [ "basic.target" ];
      serviceConfig.Type = "oneshot";
    };

    synit.daemon = {
      restart = "on-error";
      logging.enable = false;
      provides = [
        [
          "milestone"
          "nncp"
        ]
      ];
    };
  };

  meta.maintainers = with lib.maintainers; [ ehmry ];
}
