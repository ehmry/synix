{
  lib,
  config,
  pkgs,
  ...
}:

let
  inherit (lib)
    getExe
    literalMD
    mkEnableOption
    mkIf
    ;
  cfg = config.hardware.mdevd;
in
{
  options = {
    hardware.mdevd.enable = (mkEnableOption "the mdevd uevent manager") // {
      default = config.synit.enable;
      defaultText = literalMD "config.synit.enable";
    };
  };

  config = mkIf (config.synit.enable && cfg.enable) {

    environment.etc = mkIf config.boot.modprobeConfig.enable {
      # We don't place this into `extraModprobeConfig` so that stage-1 ramdisk doesn't bloat.
      "modprobe.d/firmware.conf".text =
        "options firmware_class path=${config.hardware.firmware}/lib/firmware";
    };

    synit.core.daemons.mdevd = {
      argv = [
        (getExe pkgs.mdevd)
        "-v"
        "2"
        "-O"
        "4"
        "-f"
        ./mdev.conf
        "-C"
      ];
      path = [
        pkgs.kmod
        pkgs.coreutils
        pkgs.execline
      ];
      logging.enable = true;
    };

    system.activationScripts.mdevd = mkIf config.boot.kernel.enable ''
      # The deprecated hotplug uevent helper is not used anymore
      if [ -e /proc/sys/kernel/hotplug ]; then
        echo "" > /proc/sys/kernel/hotplug
      fi

      # Allow the kernel to find our firmware.
      if [ -e /sys/module/firmware_class/parameters/path ]; then
        echo -n "${config.hardware.firmware}/lib/firmware" > /sys/module/firmware_class/parameters/path
      fi
    '';
  };
}
