# hpc-tools

Small terminal tools for working on the LSF farm over ssh, mostly from inside zellij. They are
plain bash and Python 3 scripts (standard library only), they call no web services, and they only
read: none kills, moves or deletes anything. The one exception is `bq`, which submits the job you
give it.

The most useful one is probably **the jobs picker, `bjpick`**: a pop-up list of your jobs where the
highlighted job shows a live card (time against its limit, memory and CPU against what it asked for,
why it is pending or how it failed) and the tails of its stdout and stderr, updated every two
seconds. Run it in any shell, or bind it to `Alt b` in zellij.

## Quick start (on the farm)

```bash
git clone https://github.com/<you>/hpc-tools ~/hpc-tools
cd ~/hpc-tools
./install.sh --deps
```

That links the tools into `~/.local/bin` and downloads anything they need that you don't already
have (fzf, fd, zellij, mdcat, viu and chafa, as prebuilt Linux binaries, into the same directory; no
root or compiling). Without `--deps` it only links the tools and lists what is missing. If it says
`~/.local/bin` is not on your `PATH`, add the line it prints to `~/.bashrc` and open a new shell.
Then try:

```bash
bjstat          # summary of your jobs
bjpick          # the jobs picker; Esc closes, Enter follows a job's logs
bq -x -m 8G -t 2h -- echo hi    # dry run: shows the bsub command it would submit
```

Every tool has `-h`. Updating is `git pull` in `~/hpc-tools` (the installed commands are links, so
they update with it). `./install.sh --uninstall` removes the links. The installer never overwrites a
command you already have with the same name; it tells you and skips it. Set `PREFIX=/some/dir` to
install somewhere other than `~/.local/bin`.

## The tools

**`bq`** is `bsub` with sensible defaults. It prints only the job id, so `j=$(bq -m 16G -n 8 -t 30h -- cmd)`
just works. It fills in the memory request in all three places LSF wants it (`-M`, `select[mem>]`,
`rusage[mem=]`), keeps multi-core jobs on one host, picks the queue from the run limit, writes logs
to `./logs/NAME.<jobid>.out/.err`, and runs the command under bash with `pipefail`. Arrays (`-a 1-100%20`),
dependencies (`-w "$j1 $j2"`), module loads (`-l 'samtools/1.20'`) and a dry run (`-x`) are built in.

**`bdone`** waits for jobs to finish and then prints one line per job: state, exit code, peak memory
against what was requested, run time, and whether LSF killed it for memory or time. For failures it
shows the tail of stderr. Exit status is 0 when all succeeded, 1 when some failed, 3 on timeout.

**`bjstat`** is a readable summary of your jobs: counts, ETAs per job group, why jobs are pending in
plain words, jobs near their memory or time limits, memory and CPU actually used against the request
with smaller `-M`/`-n` suggestions, and how busy each queue is. `bjstat JOBID` looks at one job in
depth (time and memory bars, log tails with the LSF report trimmed, the files it has written since it
started and where, and a diagnosis of the exit), and `bjstat JOBID -F` follows its stdout and stderr
live. `bjstat --explain` is a glossary of LSF terms.

**`bjpick`** is an fzf picker over your jobs with a live preview: the job card plus the tails of its
logs, redrawn every two seconds. Enter follows the logs full-screen. Bound to a zellij key it gives
you a pop-up job monitor (see below).

**`figs`** browses the figures (PNG, JPG, SVG, PDF) in a project, newest first, with previews in the
terminal. It asks the terminal what it can display and uses kitty graphics (Ghostty, kitty), sixel
(WezTerm, iTerm2, foot) or chafa's text rendering (anything else, including inside zellij).
`figs -w` redraws the newest figure as it is written, which is handy in a split next to a running
plot script or a LaTeX/typst build.

**`md`** renders Markdown in the terminal with mdcat; `md -w FILE` re-renders whenever the file changes.

**`tol`** finds a Darwin Tree of Life species' data on the Wellcome Sanger Institute farm from a ToL id
(`tol dmAdoAnnu1`), a species name or part of one: assemblies and releases, reads, GenomeScope
k-mer stats and the paths to them. `tol -f ID hap1` prints the current release FASTA, `tol -p ID` the
species directory, `tol -k ID` the k-mer directory. *Note: unlike the other tools this one is
specific to Sanger's Tree of Life data layout (`/data/tol/data/<project>/<group>/<Genus_species>`)
and is only useful there. `TOL_DATA` overrides the root if it moves.*

**`zbig`** is a helper for zellij keybindings: it grows its own floating pane to nearly full screen
and then runs the command it was given, since zellij's `Run` action cannot size floating panes.

## What each tool needs

The installer checks all of this. LSF, Python 3, curl, `pdftoppm` and ImageMagick are already on the
farm's head nodes.

| Tool | Needs |
|------|-------|
| `bq`, `bdone` | LSF (`bsub`, `bjobs`) |
| `bjstat` | LSF, Python 3.8+; `fd` for the "files written" section |
| `bjpick` | LSF, Python 3, `fzf` 0.56+, `curl` (for the live preview) |
| `figs` | `fzf`, `fd`, and `chafa` and/or `viu`; `pdftoppm` for PDFs, `inkscape` or ImageMagick for SVGs |
| `md` | `mdcat` (or Python `rich` with `md -r`) |
| `tol` | Python 3; access to the Sanger ToL data tree |
| `zbig` | zellij 0.42+ |

## Other LSF sites

The queue names default to those of the Wellcome Sanger Institute farm (`normal` up to 12 h, `long`
up to 48 h, `week` up to 7 days, then `basement`). Set your own with environment variables:

```bash
export BQ_QUEUES="short:60 medium:720 long"   # queue:max-minutes, shortest first; the last has no limit
export BQ_DEFAULT_QUEUE=medium                # used when no -t is given
export BJSTAT_QUEUES="short medium long"      # general queues bjstat compares when suggesting a switch
```

Other overrides: `FIGS_MODE=kitty|sixel|symbols` forces a figure renderer, `FIGS_CHAFA` points at a
chafa binary that isn't on `PATH`, `MDCAT` likewise for mdcat, and `ZBIG_GEOM="x y width height"`
sets the size `zbig` grows a pane to.

If you use Claude Code, `bjstat` also tells you which Claude session submitted each set of jobs, by
reading the session files under `~/.claude`. Without them that column is simply left out.

## Zellij keys

`zellij/keybindings.kdl` adds two pop-up (floating) panes: `Alt b` for the jobs picker and `Alt e` for
the figure browser. Neither clashes with zellij's own keys, and they work in every mode. To add them:

1. If you have no `~/.config/zellij/config.kdl` yet, create one with
   `mkdir -p ~/.config/zellij && zellij setup --dump-config > ~/.config/zellij/config.kdl`.
2. Paste the `shared { ... }` block from `zellij/keybindings.kdl` inside the `keybinds { ... }` section.
3. Check it with `zellij setup --check` (it should say "Well defined"), then start a new session or
   detach and reattach.

On a Mac the terminal must send Option as Alt: in Ghostty add `macos-option-as-alt = true` to its
config; in iTerm2 set Profiles › Keys › Left Option key to "Esc+".

## Licence

MIT.
