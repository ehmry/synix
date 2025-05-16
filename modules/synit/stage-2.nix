{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    attrNames
    escapeShellArgs
    flatten
    makeBinPath
    mkIf
    textClosureList
    ;

  cfg = config.synit;
in
{
  config.system.build = mkIf cfg.enable {
    bootStage2 = pkgs.replaceVarsWith {
      src = ./stage-2-init.sh;
      isExecutable = true;
      replacements = {
        shell = "${pkgs.bash}/bin/bash";
        systemConfig = null; # replaced in ../activation/top-level.nix
        synitPid1Cmd = escapeShellArgs (flatten (textClosureList cfg.pid1.args (attrNames cfg.pid1.args)));
        inherit (config.boot) readOnlyNixStore;
        inherit (config.system.nixos) distroName;
        path = makeBinPath [
          pkgs.coreutils
          pkgs.execline
          pkgs.util-linux
        ];
        postBootCommands = pkgs.writeText "local-cmds" ''
          ${config.boot.postBootCommands}
          ${config.powerManagement.powerUpCommands}
        '';
      };

      shell = "${pkgs.bash}/bin/bash";
      systemConfig = null; # replaced in ../activation/top-level.nix
      inherit (config.boot) readOnlyNixStore systemdExecutable;
      inherit (config.system.nixos) distroName;
      inherit (config.system.build) earlyMountScript;
      path = makeBinPath [
        pkgs.coreutils
        pkgs.util-linux
      ];
      postBootCommands = pkgs.writeText "local-cmds" ''
        ${config.boot.postBootCommands}
        ${config.powerManagement.powerUpCommands}
      '';
    };
  };
}
