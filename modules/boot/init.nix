{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.boot;

  # finit needs to mount extra file systems not covered by boot
  fsPackages =
    cfg.supportedFilesystems
    |> lib.filterAttrs (_: v: v.enable)
    |> lib.attrValues
    |> lib.catAttrs "packages"
    |> lib.flatten
    |> lib.unique;

  # Sort and join the command-line of PID 1.
  pid1Argv =
    (attrs: lib.textClosureList cfg.pid1Argv (builtins.attrNames cfg.pid1Argv))
    |> lib.flatten
    |> lib.escapeShellArgs;

  # Sets PATH when prepended to a command-line statement.
  # The exceline PATH is prepended as a side effect.
  execlineSetPath = pkgs: [
    (lib.getExe pkgs.execlineb "export")
    "PATH"
    (lib.makeBinPath pkgs)
  ];
in
{
  # TODO: something not quite sitting right with me here
  options.boot.init = {
    script = lib.mkOption {
      type = lib.types.path;
    };
  };

  pid1Argv = lib.mkOption {
    description = ''
      The PID 1 command line as a closure-list.
    '';
    type = types.attrsOf (
      types.submodule {
        options = {
          deps = mkOption {
            type = with types; either str (listOf str);
            default = [ ];
            description = "List of argument groups that must preceded this one.";
          };
          text = mkOption {
            type = types.uniq (types.listOf (types.either types.str types.path));
            description = "Group of arguments for the pid1 command-line.";
          };
        };
      }
    );
  };

  config = {
    boot.init.pid1Argv = mkIf config.finit.enable {
      # finit requires fsck, modprobe & mount commands
      # before PATH can be read from finit.conf
      exportPath.text = lib.mkDefault (
        execlineSetPath (
          [
            pkgs.unixtools.fsck
            pkgs.kmod
            pkgs.util-linux.mount
          ]
          ++ fsPackages
        )
      );
      finit = {
        deps = [ "exportPath" ];
        text = lib.mkDefault "${config.finit.package}/bin/finit";
      };
    };

    boot.init.script = pkgs.writeScript "init" ''
      #!${pkgs.runtimeShell}

      systemConfig='@systemConfig@'

      echo
      echo "[1;32m<<< finix - stage 2 >>>[0m"
      echo

      echo "running activation script..."
      $systemConfig/activate

      # record the boot configuration.
      ${pkgs.coreutils}/bin/ln -sfn "$systemConfig" /run/booted-system

      echo "about to launch PID 1"
      exec ${pid1Argv} "$@"
    '';
  };
}
