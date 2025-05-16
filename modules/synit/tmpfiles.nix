{
  lib,
  config,
  pkgs,
  ...
}:

let
  inherit (lib)
    attrNames
    attrValues
    concatMap
    foldl'
    getExe'
    mapAttrs'
    mapAttrsToList
    mkIf
    mkMerge
    ;
  inherit (builtins) toJSON;

  preserves = pkgs.formats.preserves {
    ignoreNulls = true;
    rawStrings = true;
  };
  writePreservesFile = preserves.generate;

  # Create a Preserves record for a tmpfiles rule.
  mkRule =
    path: attrs:
    map (
      {
        type,
        mode,
        user,
        group,
        age,
        argument,
      }:
      let
        stringOrFalse = s: if s == "-" then "#f" else toJSON s;
      in
      [
        type
        (toJSON path)
        (if mode == "-" then "#f" else mode)
        (stringOrFalse user)
        (stringOrFalse group)
        (stringOrFalse age)
        (stringOrFalse argument)
        { _record = "tmpfile"; }
      ]
    ) (attrValues attrs);

  cfg = config.systemd.tmpfiles.settings;
in
{
  config = mkIf config.synit.enable {

    environment.etc = mkMerge (
      # Create a file for each top-level attrset in tmpfiles.settings.
      mapAttrsToList (name: paths: {
        "syndicate/tmpfiles/${name}.pr".source = writePreservesFile "tmpfiles-${name}.pr" (
          concatMap (path: mkRule path paths.${path}) (attrNames paths)
        );
      }) cfg
      ++ [
        {
          "syndicate/core/tmpfiles.pr".text = ''
            # Create a dedicated dataspace for tmpfiles.
            let ?tmpfiles = dataspace

            # Assert it.
            <tmpfiles-dataspace $tmpfiles>

            # Load rules.
            <require-service
              <config-watcher "/etc/syndicate/tmpfiles" { config: $tmpfiles }>>

            # Hand-off to tmpfiles script.
            ? <service-object <daemon tmpfiles> ?obj> [
              # TODO: attenuate.
              $obj += <tmpfiles-dataspace $tmpfiles>
            ]
          '';
        }
      ]
    );

    # Persistent script for handling tmpfiles rules.
    synit.core.daemons.tmpfiles =
      let
        inherit (pkgs.tclPackages) tcl sycl;
      in
      {
        argv = [
          # (getExe' pkgs.execline "umask")
          # "0177"
          (getExe' tcl "tclsh")
          ./tmpfiles.tcl
        ];
        env.TCLLIBPATH = "${sycl}/lib/${sycl.name}";
        protocol = "text/syndicate";
        logging.enable = true;
      };
  };
}
