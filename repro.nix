{ 
  system ? builtins.currentSystem,
  failure ? "singular-info-file",
  longTests ? true,
  nthreads ? 1,
  extraArgs ? "",
}:

# Focus Sage test reruns on one recorded failing file instead of the full suite.
#
# Examples:
#   nix-build repro.nix
#   nix-build repro.nix --argstr failure ext-rep
#   nix-build repro.nix --arg nthreads 4
#   nix-build repro.nix --argstr extraArgs '--verbose --warn-long 0'

let
  pkgs = import ./. { inherit system; };
  lib = pkgs.lib;

  failures = {
    ext-rep = {
      file = "src/sage/combinat/designs/ext_rep.py";
      description = "Abort in ext_rep doctests on Darwin";
    };

    singular-info-file = {
      file = "src/sage/libs/singular/singular.pyx";
      description = "Blank output from get_resource('i') doctest";
    };

    matrix-double-dense = {
      file = "src/sage/matrix/matrix_double_dense.pyx";
      description = "Last-bit tolerance drift in SVD doctest";
    };

    multi-polynomial-libsingular = {
      file = "src/sage/rings/polynomial/multi_polynomial_libsingular.pyx";
      description = "Alarm-based doctests complete too quickly";
    };
  };

  selected =
    failures.${failure} or (throw "Unknown failure '${failure}'. Known failures: ${lib.concatStringsSep ", " (builtins.attrNames failures)}");
in
(pkgs.sage.tests.override {
  files = [ selected.file ];
  inherit longTests nthreads extraArgs;
}).overrideAttrs
  (oldAttrs: {
    pname = "sage-repro-${failure}";
    installCheckPhase = ''
      echo "Reproducing recorded Sage failure '${failure}'"
      echo "Target: ${selected.file}"
      echo "Description: ${selected.description}"
      ${oldAttrs.installCheckPhase}
    '';
  })
