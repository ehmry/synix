{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.networking;
  inherit (lib)
    mapAttrs'
    optionalAttrs
    ;

  preserves = pkgs.formats.preserves {
    ignoreNulls = true;
    rawStrings = true;
  };
  writePreservesFile = preserves.generate;

  quoteStrings =
    let
      __toPreserves = lib.generators.toPreserves {
        ignoreNulls = true;
        rawStrings = false;
      };
    in
    attrs: attrs // { inherit __toPreserves; };

  assertRecord = label: face: family: cfg: [
    face
    family
    (quoteStrings cfg)
    { _record = label; }
  ];

  mkInterfaceFile = face: cfg: {
    name = "syndicate/network/interface-${face}.pr";
    value.source = writePreservesFile "interface-${face}.pr" (
      [
        [
          cfg.name
          (
            quoteStrings {
              inherit (cfg)
                macAddress
                mtu
                tempAddress
                useDHCP
                ;
              proxyARP = if cfg.proxyARP then true else null;
            }
            // optionalAttrs cfg.wakeOnLan.enable { wakeOnLan.policy = cfg.wakeOnLan.policy; }
            // optionalAttrs cfg.virtual {
              owner = cfg.virtualOwner;
              type = cfg.virtualType;
            }
          )
          { _record = "interface"; }
        ]
      ]
      ++ map (assertRecord "address" cfg.name "ipv4") cfg.ipv4.addresses
      ++ map (assertRecord "address" cfg.name "ipv6") cfg.ipv6.addresses
      ++ map (assertRecord "route" cfg.name "ipv4") cfg.ipv4.routes
      ++ map (assertRecord "route" cfg.name "ipv6") cfg.ipv6.routes
    );
  };
in
{
  config = lib.mkIf config.synit.enable {
    environment.etc = lib.mkMerge [
      {
        "syndicate/network/loopback.pr".text = "<interface lo { }>";
        "syndicate/core/network-config.pr".text = ''
          # Dataspace of intended network configuration.
          let ?network = dataspace
          $network ? ?x [
            $log ! <log "-" { line: "network" |+++|: $x }>
            ?- $log ! <log "-" { line: "network" |---|: $x }>
          ]

          <require-service
            <config-watcher "/etc/syndicate/network" { config: $network log: $log }>>

          # Dataspace of actual network state.
          ? <machine-dataspace ?machine> [
            $config += <network-dataspace $network $machine>

            # Announce a network milestone while an address with global scope is present.
            $machine ? <address _ _ {"scope": "global"}> [
              $config += <run-service <milestone network>>
            ]

            ? <service-object <daemon network-configurator> ?obj> [
              # The configurator can only observe $network and
              # only assert <address> or <route> into $machine.
              $obj += <network-dataspace
                <* $network [ <reject <not <rec Observe>>> ]>
                <* $machine [<reject <and <not<rec address>> <not<rec route>>>> ]>>
            ]
          ]
        '';
      }
      (mapAttrs' mkInterfaceFile cfg.interfaces)
    ];
    synit.core.daemons.network-configurator =
      let
        inherit (pkgs.tclPackages) tcl sycl;
      in
      {
        argv = [
          (lib.getExe' tcl "tclsh")
          ./networking.tcl
        ];
        env.TCLLIBPATH = "${sycl}/lib/${sycl.name}";
        path = [ pkgs.iproute2 ];
        protocol = "text/syndicate";
      };
  };
}
