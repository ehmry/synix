{
  lib,
  config,
  pkgs,
  utils,
  ...
}:

let
  inherit (lib)
    getExe
    literalMD
    mkDefault
    mkEnableOption
    mkPackageOption
    mkIf
    mkOption
    types
    ;

  inherit (utils) makeLogger;

  ctrlSockPath = "/run/synit/system-bus.sock";

  cfg = config.synit;
  mkIfSynit = mkIf cfg.enable;

in
{
  imports = [
    ../system/service/synit/system.nix
    ./daemons.nix
    ./dependencies.nix
    ./filesystems.nix
    ./logging.nix
    ./mdevd.nix
    ./networking.nix
    ./tmpfiles.nix
  ];

  options.synit = {
    enable = mkEnableOption "the Synit system layer";

    controlSocket = {
      enable =
        mkEnableOption ''
          the system bus control socket.
          The socket will located at ${ctrlSockPath}
        ''
        // {
          default = true;
        };
    };

    syndicate-server.package = mkPackageOption pkgs "syndicate-server" { };

    pid1.package = mkPackageOption pkgs "synit-pid1" { };

  };

  config = mkIfSynit {
    assertions = [
      {
        assertion = !config.systemd.enable;
        message = "Synit and systemd cannot both be enabled";
      }
    ];

    environment.etc."syndicate/core/controlSocket.pr" = mkIf cfg.controlSocket.enable {
      text = ''
        <require-service <relay-listener <unix "${ctrlSockPath}"> $config>>
      '';
    };

    environment.systemPackages = [
      cfg.syndicate-server.package
      pkgs.synit-service
    ];

    boot.init.pid1Argv = {
      # This tells Rust programs built with jemallocator to be very aggressive about keeping their
      # heaps small. Synit currently targets small machines. Without this, I have seen the system
      # syndicate-server take around 300MB of heap when doing not particularly much; with this, it
      # takes about 15MB in the same state. There is a performance penalty on being so aggressive
      # about heap size, but it's more important to stay small in this circumstance right now. - tonyg
      mallocConf = {
        text = mkDefault [
          "export"
          "_RJEM_MALLOC_CONF"
          "narenas:1,tcache:false,dirty_decay_ms:0,muzzy_decay_ms:0"
        ];
      };
      synit-pid1 = {
        deps = [ "mallocConf" ];
        text = mkDefault [ (getExe cfg.pid1.package) ];
      };
      logger = {
        deps = [ "synit-pid1" ];
        text = mkDefault (makeLogger [ ] "/var/log/synit");
      };
      syndicate-server = {
        deps = [ "logger" ];
        text = mkDefault [
          (getExe cfg.syndicate-server.package)
          "--inferior"
          "--control"
        ];
      };
      syndicate-server-config = {
        deps = [ "syndicate-server" ];
        text = mkDefault [
          "--config"
          "${./static}/boot"
        ];
      };
    };

    system.activationScripts.synit-config = {
      deps = [ "specialfs" ];
      text = "install --mode=644 --directory /run/etc/syndicate/{core,system,services}";
    };

    system.tmpfiles.synit =
      let
        configAttrs.d = {
          mode = "0660";
          user = "root";
          group = "wheel";
        };
      in
      {
        "/run/etc/syndicate/core" = configAttrs;
        "/run/etc/syndicate/network" = configAttrs;
        "/run/etc/syndicate/services" = configAttrs;
        "/run/synit" = mkIf cfg.controlSocket.enable configAttrs;
      };

  };

  meta = {
    maintainers = with lib.maintainers; [ ehmry ];
    # doc = ./todo.md;
  };
}
