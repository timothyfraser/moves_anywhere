# <a href="https://github.com/timothyfraser/moves_anywhere"><img src="docs/img/movesanywhere_hexagon.png" height="44" align="top"/></a> Contributing to `moves_anywhere`

How to propose a change, and the header every script in `moves_anywhere/scripts/` carries.

> **Image versions:** `tmf77/moves-anywhere:v3` is the current release (3.1.0). `v3.0.0` and `v2` are previous images and do not change.
> A change to the scripts goes into `v3`.

## Proposing a change

1. Make a branch from `main`, named for what it does (for example `docs/<yourname>-headers-adapt`).
2. Keep one change per branch: a header batch, a bug fix, or a guide. Not all three.
3. Open a pull request into `main`. Say what you changed and how you checked it.
4. Nothing is pushed straight to `main`, and nothing is pushed to Docker Hub from a pull request.

## The script header

Every script starts with the same header, so anyone can see what it is, where it runs, and what it touches.
Keep the existing comments word for word, keep `=` for assignment, and number the steps inside the script
with `#` banners ending in `####`. Step numbers follow the order in `moves_anywhere/launch.sh`.

### R

```r
# <filename>.R ################################################################
#
# What:      <one line: what this script is>
# Does:      <one or two lines: what it does, in plain words>
# Called by: <script>, step <N> of launch.sh     (or: Not used by v3. Legacy ... / Developer tool ...)
# Reads:     <files, tables>
# Writes:    <files, tables>
# Needs:     <sourced files, packages>
###############################################################################

#' <Title, as in catr: one line>
#' @param .runspec path to the run's runspec (XML)
<function> = function(.runspec = "EPA_MOVES_Model/rs_custom.xml"){
  # 1. <step> ########################################
```

### Shell

The first line is `#!/bin/bash`. Same fields, plus `Exits:` with the exit codes. Scripts that already list
their exit codes keep that content, reshaped into the fields.

```bash
#!/bin/bash
# <filename>.sh ###############################################################
#
# What:      <one line: what this script is>
# Does:      <one or two lines: what it does, in plain words>
# Called by: <script>, step <N> of launch.sh     (or: Not used by v3. Legacy ... / Developer tool ...)
# Reads:     <files, tables>
# Writes:    <files, tables>
# Exits:     <code> if <reason>
###############################################################################

# 1. <step> ###################################
```

### Python

Same fields, as `#` lines under the first line. Leave the module docstring as it is: the checker treats a
docstring as code.

```python
#!/usr/bin/env python3
# <filename>.py ###############################################################
#
# What:      <one line: what this script is>
# Does:      <one or two lines: what it does, in plain words>
# Called by: <script>, step <N> of launch.sh     (or: Not used by v3. Legacy ... / Developer tool ...)
# Reads:     <files>
# Writes:    <files>
# Exits:     <code> if <reason>
###############################################################################
```

## Comments only

A header change adds or edits comment lines and nothing else. Fixing a broken first line (`#/bin/bash` to
`#!/bin/bash`) or a wrong file name in a header counts as a comment change. Moving, renaming or deleting a
script does not, and goes in its own pull request.

Before you open the pull request, run the checker from the repository root:

``` bash
bash moves_anywhere/tests/test_comments_only.sh origin/main
```

It compares every changed `.R`, `.r`, `.sh` and `.py` file and every `Dockerfile` with `origin/main` after
dropping comment lines and blank lines. It prints `PASS n files` and exits `0` only when no code line changed.
Otherwise it prints one line per change, `FAIL <file>: code line changed: <line>`, and exits `1`.
Other changed files are listed as `OTHER <file>` and are not checked.

To check the checker itself:

``` bash
bash moves_anywhere/tests/test_comments_only_selftest.sh
```

<p align="center"><a href="https://github.com/timothyfraser/moves_anywhere"><img src="docs/img/movesanywhere_hexagon.png" height="60"/></a><br/><sub>MOVES Anywhere · Apache 2.0 · Gao Labs @ Cornell University</sub></p>
