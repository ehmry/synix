{
  config,
  ...
}:

{
  config = {
    synit.core.daemons.mount-all = {
      argv = [
        "mount"
        "-a"
      ];
      restart = "on-error";
      logging.enable = false;
    };
  };
}
