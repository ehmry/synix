{
  lib,
  config,
  pkgs,
  ...
}:

let
  inherit (lib) getExe';
in

{
  config = {
    synit.core.daemons.syslog = {
      argv = [ (getExe' pkgs.s6 "s6-socklog") ];
      logging.enable = true;
    };
  };
}
