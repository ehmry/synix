{ testenv ? import ./testenv { } }:

let
  inherit (testenv) lib pkgs;
  sycl = pkgs.tclPackages.sycl;
in
testenv.mkTest {
  name = "synit";

  nodes.machine = { lib, ... }: {
    boot.serviceManager = "synit";
    services.dhcpcd.enable = true;

    # Configure the guest to connect to a syndicate-server on the host.
    environment.etc."/syndicate/core/connect-to-host.pr".text = ''
      let ?req = <resolve-path <route [<tcp "10.0.2.2" 2424>]>>
      <q $req>
      ? <a $req <ok <resolved-path _ _ ?host>>> [
        $host += <config machine $config>
        $log ! <log "-" { line: "connected to QEMU host" }>
      ]
    '';
  };

  runAttrs = {
    buildInputs = [ pkgs.syndicate-server ];

    # Make the host server quiet.
    RUST_LOG = "ERROR";

    # A the syndicate package to the Tcl library path.
    TCLLIBPATH = [ "${sycl}/lib/${sycl.name}" ];
  };

  tclScript = ''
    package require syndicate

    # Start a server for the guest to connect to.
    exec syndicate-server --no-banner --config ${./host-server.cfg.pr} &

    machine spawn
    machine expect {synit_pid1: Awaiting signals...}
    machine expect {syndicate_server: inferior server instance}
    machine expect {adding default route via 10.0.2.2}
    machine expect "connected to QEMU host*\n"

    # The guest is connected to a syndicate-server on the host.
    # Access the guest synit using that server as an intermediary.
    syndicate::spawn actor {
      connect {<route [<tcp "127.0.0.1" 2424>]>} srv {
        # Observe the dataspace of the guest machine.
        during {<config machine @guest #?>} {
          onAssert {<service-state @service #? up>} {
            puts stderr "guest service is up: $service"
          } $guest
          onAssert {<service-state <milestone system-machine> up>} {
            # Test complete.
            success
          } $guest
        } $srv
      }
    }

    # Enter an endless dispatch loop.
    machine expect {
      timeout exp_continue
    }
  '';
}
