# catr

`catr` is the R package that goes with MOVES Anywhere. It writes MOVES runspecs, adapts input tables, reads MOVES output, and formats results into CAT Format.

The Docker image installs it at build time from the tarball `catr_0.2.0.tar.gz`, using `moves_anywhere/scripts/task_install_catr.R`. You can also install it in R yourself: see the install lines in the [main README](../README.md).

For the functions and a usage workflow, see the [catr guide](../docs/README_catr.md).
