# Temporary overlays for packages not yet in nixpkgs-unstable.
# Remove each entry once the corresponding PR is merged.
final: prev: {
  # https://github.com/NixOS/nixpkgs/pull/TODO — scrobblex PR pending
  scrobblex = final.callPackage ../packages/scrobblex.nix {};
}
