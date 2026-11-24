# farm-tools

Small terminal tools for working on the LSF farm over ssh. They are
plain bash and Python 3 scripts (standard library only), they call no web services, and they only
read: none kills, moves or deletes anything. The one exception is `bq`, which submits the job you
give it.

The most useful one is probably **the jobs picker, `bjpick`**: a pop-up list of your jobs where the
highlighted job shows a live card (time against its limit, memory and CPU against what it asked for,
why it is pending or how it failed) and the tails of its stdout and stderr, updated every two
seconds. Just type `bjpick` in any terminal.

## Quick start (on the farm)

```bash
git clone https://github.com/caganlab/farm-tools ~/farm-tools
cd ~/farm-tools
./install.sh --deps
```

That links the tools into `~/.local/bin` and downloads anything they need that you don't already
have (fzf, fd, mdcat, viu and chafa, as prebuilt Linux binaries, into the same directory; no
root or compiling). Without `--deps` it only links the tools and lists what is missing. If it says
`~/.local/bin` is not on your `PATH`, add the line it prints to `~/.bashrc` and open a new shell.
Then try:

```bash
bjstat          # summary of your jobs
bjpick          # the jobs picker; Esc closes, Enter follows a job's logs
bq -x -m 8G -t 2h -- echo hi    # dry run: shows the bsub command it would submit
```

Every tool has `-h`. Updating is `git pull` in `~/farm-tools` (the installed commands are links, so
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
logs, redrawn every two seconds. Enter follows the logs full-screen. If a job's stdout and stderr
are nearly empty because its tools write their own log files, it finds the newest log file the job
has written in its directories and shows that too. If you use zellij, one key gives
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

## Examples

The outputs below are real (trimmed, paths shortened), except the `bjpick` sketch.

**Submit a job with `bq`, wait for it with `bdone`.** `bq` prints only the job id, so you can keep it
in a variable. `-x` shows the `bsub` it would run instead of submitting:

```console
$ bq -x -m 16G -n 8 -t 30h -J map -- 'minimap2 -t 8 ref.fa reads.fq.gz > aln.paf'
bsub -q long -n 8 -M 16000 -R select[mem>16000] rusage[mem=16000] span[hosts=1] -J map
     -o ./logs/map.%J.out -e ./logs/map.%J.err -W 30:00 bash -c 'set -o pipefail; minimap2 ...'

$ j=$(bq -m 16G -n 8 -t 30h -J map -- 'minimap2 -t 8 ref.fa reads.fq.gz > aln.paf')
$ bdone $j        # waits; here for a job that ran out of time
JOBID     IDX   STAT  EXIT MAXMEM       REQ    RUNTIME   REASON         NAME
642554    0     EXIT  140  330 Mbytes   8 G    1h00m     RUNLIMIT       e2e3.Huperzia_selago
    | User defined signal 2
```

Arrays and dependencies: `bq -a 1-100%20 -J chunk -- 'run.sh $LSB_JOBINDEX'`, then
`bq -w "$j" -J merge -- merge.sh` starts only when job `$j` has finished successfully.

**See all your jobs with `bjstat`:**

```console
$ bjstat
  1 running · 3 pending · 3 done · 1 failed   (done/failed = last ~hour)
  Using 1 cores, 0.1G RAM in use of 8.0G reserved

By job group  (grouped by prefix; -g name for full names)
  group          run  pend  done  fail  med runtime  fin/hr         ETA  queue
  assembly         0     3     0     0            -       0  no history  hugemem
  e2e3             1     0     3     1        7m30s       4      ~4m07s  normal

Why pending
      3  There are no suitable hosts for the job

Needs attention
  1 job(s) failed:
            642554  e2e3.Huperzia_selago  exit 140, TERM_RUNLIMIT: job killed after reaching
                    LSF run time limit   .../logs/e2e3.Huperzia_selago.642554.err

Resource use of finished jobs  (to right-size the next batch)
  group  n  med mem  peak mem  requested  cpu eff  suggestion
  e2e3   3     0.8G      0.8G       8.0G      98%  -M 2G would do
```

**Look into one job with `bjstat JOBID`** (`-F` follows its logs live instead):

```console
$ bjstat 642554
642554  e2e3.Huperzia_selago  EXIT  queue normal  1 core  node-13-27

Time
  submitted 11:45, waited 1s in the queue
  started   11:45, ran 1h00m of 1h00m limit  ████████████████████████
  finished  12:45 (4m51s ago)

Resources
  memory    max 0.3G, avg 0.1G of 8.0G  █░░░░░░░░░░░░░░░░░░░░░░░  4% efficient
            next time -M 1G would do (uses < 1/4 of the request)
  cpu       0.1 of 1 core(s) on average  (11% efficient, peak 1.0)

Exit
  exit code 140: SIGUSR2 (LSF run-limit warning)
  TERM_RUNLIMIT: hit the queue's / -W run limit; use a longer queue or checkpoint

Logs
  stdout: .../logs/e2e3.Huperzia_selago.642554.out  2K, last write 4m52s ago
  stderr: .../logs/e2e3.Huperzia_selago.642554.err  22B, last write 4m58s ago
    │ User defined signal 2
```

**Pick a job with `bjpick`.** A sketch of the screen: your jobs on the left; on the right, the same card for the highlighted
job plus the last lines of its stdout and stderr, redrawn every two seconds. Move with the arrow
keys, type to filter, Enter to follow a job's logs full-screen, Esc to close.

```console
$ bjpick
  642901 RUN   normal  8  map.chr1      myproject  │ 642901  map.chr1  RUN  queue normal  8 cores
> 642554 EXIT  normal  1  e2e3.Huper…   rnaedit    │ Time
  983557 PEND  hugemem 16 asm.v2        assembly   │   started 11:45, ran 23m of 30h limit  ██░░░
                                                   │ ── stdout · 2K · last write 3s ago · live ──
                                                   │ [M::mm_idx_gen] read 1.2 Gbp ...
```

**Browse figures with `figs`:**

```console
$ figs                     # figures in this project (git repo or dir), newest first, with previews
$ figs -w results/         # keep showing the newest figure written under results/
$ figs show plots/pca.png  # draw one figure right here
```

**Read Markdown with `md`:** `md README.md`, `md -w notes.md` (re-renders whenever it changes), or
`some-command | md`.

**Find a species' data with `tol`:**

```console
$ tol dmAdoAnnu1
Adonis annua  (dicots · taxon 212759 · darwin, tol)
  /lustre/scratch122/tol/data/f/6/0/d/d/9/Adonis_annua

Release  reference → GCA_964200825.2
  dmAdoAnnu1.hap1.2        GCA_964200825.2    GCA_964200825.2.fa.gz 4.2G ★
  dmAdoAnnu1.hap2.2        GCA_964214385.2    GCA_964214385.2.fa.gz 4.2G

Reads
  dmAdoAnnu1   hic-arima2     1 cram (284.4G)
  dmAdoAnnu1   pacbio         12 bam (278.8G)

K-mers  k31
  GenomeScope: haploid 7.12 Gb, het 26.1%, fit 90.9%

$ minimap2 -x asm5 $(tol -f dmAdoAnnu1 hap1) my_contigs.fa > aln.paf
$ cd $(tol -p 'Adonis annua')
```

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

## Other LSF sites

The queue names default to those of the Wellcome Sanger Institute farm (`normal` up to 12 h, `long`
up to 48 h, `week` up to 7 days, then `basement`). Set your own with environment variables:

```bash
export BQ_QUEUES="short:60 medium:720 long"   # queue:max-minutes, shortest first; the last has no limit
export BQ_DEFAULT_QUEUE=medium                # used when no -t is given
export BJSTAT_QUEUES="short medium long"      # general queues bjstat compares when suggesting a switch
```

Other overrides: `FIGS_MODE=kitty|sixel|symbols` forces a figure renderer, `FIGS_CHAFA` points at a
chafa binary that isn't on `PATH`, `MDCAT` likewise for mdcat, and (with zellij)
`ZBIG_GEOM="x y width height"` sets the size `zbig` grows a pane to.

If you use Claude Code, `bjstat` also tells you which Claude session submitted each set of jobs, by
reading the session files under `~/.claude`. Without them that column is simply left out.

## Optional: zellij

Nothing above needs zellij. If you do use it (a terminal multiplexer, like tmux), the jobs picker
and figure browser can pop up over whatever you're doing with one key: `Alt b` for jobs, `Alt e`
for figures, and `Alt s` switches to another of your zellij sessions. Set it up with:

```bash
./install.sh --zellij            # add --deps to also download zellij 0.42 if you don't have it
```

This also installs `zbig`, a small helper that grows the pop-up pane to nearly full screen (zellij
can't size pop-ups from a keybinding itself), and `zpick`, the session switcher. zellij 0.42 has no
command to switch sessions from a script, but its plugins can, so `zpick` lists your sessions
(exited ones too) in fzf and hands your choice to `zswitch`, a 70-line plugin whose Rust source is
in `zswitch/` and whose compiled form (`zellij/zswitch.wasm`) is linked into
`~/.config/zellij/plugins`. Enter switches, and `ctrl-n` starts a new session named as you typed,
in the current directory. The first time, zellij pops up a question asking whether zswitch may
change sessions: press `y`, and it remembers. Outside zellij, `zpick` simply attaches.
To rebuild the plugin yourself: `rustup target add wasm32-wasip1 && cd zswitch && cargo build --release`.

Then add the keys:

1. If you have no `~/.config/zellij/config.kdl` yet, create one with
   `mkdir -p ~/.config/zellij && zellij setup --dump-config > ~/.config/zellij/config.kdl`.
2. Paste the `shared { ... }` block from `zellij/keybindings.kdl` inside the `keybinds { ... }` section.
   None of the keys clashes with zellij's own, and they work in every mode.
3. Check it with `zellij setup --check` (it should say "Well defined"), then start a new session or
   detach and reattach.

On a Mac the terminal must send Option as Alt: in Ghostty add `macos-option-as-alt = true` to its
config; in iTerm2 set Profiles › Keys › Left Option key to "Esc+".

## Licence

MIT.
