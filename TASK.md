Continuing to debug:

https://github.com/NixOS/nixpkgs/issues/545650

- the earlier one-off local build did reproduce the Hydra-style failure set:
  - ext_rep.py aborted
  - singular.pyx doctest failed
  - matrix_double_dense.pyx doctest failed
  - multi_polynomial_libsingular.pyx doctests failed
  - pytest still passed

Can we figure out what are the root causes of each?

# ext_rep.py aborted

Local repro:

- `src/sage/combinat/designs/ext_rep.py`
- failed with `Killed due to abort`
- the process made it through several doctest steps around `dump_to_tmpfile`, `check_dtrs_protocols`, and `XTreeProcessor().parse(...)` before aborting
- there was no Python traceback, so this looks like a lower-level abort rather than a normal doctest assertion failure

Hypothesis:

- this is probably a native/runtime bug or an upstream Sage bug in the `ext_rep` path rather than a Nix packaging typo
- `collares` pointed at <https://github.com/sagemath/sage/issues/25921>; the open question is why that fix does not seem to cover our Darwin build here
- because the failure is an abort instead of a deterministic mismatch, it may be platform-specific or dependent on the exact XML/parser/native library combination used here

Focused repro and root cause:

- the new `repro.nix` target makes this fail quickly with just `ext_rep.py`, so we can iterate without rerunning the full suite
- the abort consistently happens at the doctest calling `ext_rep.open_extrep_url("file://" + file_loc)`
- the Darwin abort backtrace goes through Python's `_scproxy` module and then macOS `SystemConfiguration` / Objective-C initialization, not through Sage's XML parsing itself
- this matters because `open_extrep_url()` uses `urllib.request.urlopen()` even for local `file://` URLs; on Darwin that can trigger proxy discovery machinery in a forked doctest subprocess
- we validated that this is the actual trigger, not just correlation:
  - baseline focused repro aborts immediately
  - rerunning the same doctest with `no_proxy='*'` or `NO_PROXY='*'` makes it pass
  - patching `open_extrep_url()` to special-case `file://` and read the local file directly also makes the focused repro pass
- taken together, that is strong evidence that the root cause is Darwin proxy lookup during `urlopen(file://...)`, not the ext-rep parser and not general Sage runtime instability

Current fix direction:

- patch `src/sage/combinat/designs/ext_rep.py` so `open_extrep_url()` handles `file://` URLs by opening the local path directly via `open_extrep_file()` instead of going through `urlopen()`
- this is narrowly targeted at the crashing path, keeps the behavior for real remote URLs unchanged, and matches the fact that the failing doctest is only using a local temporary file

Next checks:

- look up whether upstream Sage already has an equivalent `file://` handling fix or Darwin workaround
- decide whether we want to upstream the code fix itself or carry it as a Nix patch for now

# singular.pyx doctest failed

Local repro:

- `src/sage/libs/singular/singular.pyx`
- failing doctest: `get_resource('i')            # SINGULAR_INFO_FILE`
- expected: `'.../singular...'`
- got: blank output

Hypothesis:

- this does not look like a computation bug; it looks like a resource discovery / environment wiring problem
- the doctest is specifically about `SINGULAR_INFO_FILE`, but our Nix environment wiring in `pkgs/by-name/sa/sage/env-locations.nix` exports `SINGULARPATH`, `SINGULAR_SO`, and `SINGULAR_EXECUTABLE`, not `SINGULAR_INFO_FILE`
- likely causes:
  - Sage on Darwin is no longer able to infer the Singular info resource from the packaged layout
  - the doctest assumes upstream filesystem conventions that do not exactly match the Nix-packaged Singular layout
  - the resource exists, but the lookup path is not propagated into the doctest subprocess in the way Sage expects

Focused repro and root cause:

- the new `repro.nix` target reproduces this in about three seconds with just `src/sage/libs/singular/singular.pyx`
- `get_resource('D')` works and returns the packaged `share` directory, but `get_resource('i')` returns `None` and Singular prints:
  - either set `SINGULAR_INFO_FILE`
  - or make sure `singular.info` exists at `.../share/info/singular.info`
- inspecting `pkgs/by-name/si/singular/package.nix` showed the actual root cause: on `aarch64-darwin`, `enableDocs` defaults to `false`
- that matters because the Singular package only installs `share/info/singular.info` when docs are enabled
- we confirmed the package layout mismatch directly:
  - Sage's wrapped environment had `SINGULARPATH`, but no `SINGULAR_INFO_FILE`
  - the packaged Singular used by Sage had no `share/info` directory at all
  - a docs-enabled `singular.override { enableDocs = true; }` build succeeds locally and does contain `share/info/singular.info`
- we also validated the exact missing input:
  - setting `SINGULAR_INFO_FILE` to a real `singular.info` file makes the focused `singular.pyx` doctest pass immediately
  - wiring Sage to export `SINGULAR_INFO_FILE` from a docs-enabled sibling Singular package also makes the focused repro pass
- so this is not numeric flakiness and not a libSingular logic bug; it is a packaging mismatch where Sage expects a Singular info file that our Darwin build currently omits

Current fix direction:

- keep Sage's main Singular package unchanged for library/runtime use
- add a docs-enabled sibling Singular derivation just for the info file
- export `SINGULAR_INFO_FILE` from `pkgs/by-name/sa/sage/env-locations.nix` so Sage's resource lookup sees a valid `singular.info`

Current confidence:

- very high that this is packaging/resource-related, specifically missing `singular.info` on Darwin

# matrix_double_dense.pyx doctest failed

Local repro:

- `src/sage/matrix/matrix_double_dense.pyx`
- failing doctest: `U*S*V.transpose()  # tol 1e-15`
- expected and actual values differ only in the last bits
- reported failure: `tolerance 2e-15 > 1e-15`

Hypothesis:

- this looks like pure floating-point tolerance drift, not a semantic regression
- the result matrix is numerically the same for practical purposes; the doctest tolerance is just too strict for this Darwin/aarch64 BLAS/LAPACK stack
- likely contributors:
  - different linear algebra backend behavior on Darwin arm64
  - slightly different rounding/order of operations in the SVD implementation or underlying libraries

Current confidence:

- high that this is a flaky tolerance issue and the fix is to relax or rewrite the doctest comparison

# multi_polynomial_libsingular.pyx doctests failed

Local repro:

- `src/sage/rings/polynomial/multi_polynomial_libsingular.pyx`
- two doctests expect `AlarmInterrupt` after `alarm(0.5); h = (x^2^n-y^2^n).factor()`
- actual result: blank output, meaning the computation finished before the alarm fired
- a third follow-up doctest then sees `AlarmInterrupt` in a different place than expected

Hypothesis:

- this is the clearest case of a stale timing-sensitive doctest
- `collares` already called this out in <https://github.com/NixOS/nixpkgs/pull/538506#issuecomment-5085550287>: the test comment itself says to increase `n` when hardware or algorithms get faster
- so the most likely root cause is not a regression in correctness, but that FLINT/Singular is now fast enough on this setup that the 0.5s alarm-based expectation no longer holds

Current confidence:

- very high that this is a timing-sensitive doctest that needs to be updated rather than a real functional bug

Overall read so far:

- `matrix_double_dense.pyx` and `multi_polynomial_libsingular.pyx` both look like test fragility, not real math failures
- `singular.pyx` looks like environment/resource wiring
- `ext_rep.py` is the least understood one and is the strongest candidate for a real Darwin-specific runtime bug
