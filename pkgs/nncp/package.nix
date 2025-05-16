{ nncp }:
nncp.overrideAttrs (
  { passthru, ... }:
  {
    passthru.services.default = {
      imports = [ ./service.nix ];
      nncp.package = nncp;
    };
  }
)
