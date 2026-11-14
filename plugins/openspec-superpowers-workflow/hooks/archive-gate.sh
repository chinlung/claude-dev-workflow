#!/bin/bash
# openspec-superpowers-workflow PreToolUse archive gate (matcher Bash; hooks.json narrows it with
# `if` to `openspec archive *` and `mv *`, so it does not spawn for every Bash call).
#
# Denies archiving an OpenSpec change until `reconcile-check.cjs check` has recorded a pass verdict
# and none of the files that verdict hashed changed since (`reconcile-check.cjs verify`). Both ways
# of archiving are covered: `openspec archive <name>` and the OpenSpec 1.16 /opsx:archive template,
# which syncs specs itself and then runs `mv <changes>/<name> <changes>/archive/<date-name>`
# (bulk-archive runs one mv per change; every change in the command must pass).
# On allow it leaves ${TMPDIR}/claude-openspec-archived-<session>, which skip-gate reads.
# Bypass for one command: OPENSPEC_ARCHIVE_OK=1 in the command.
# Fail-open: missing jq/perl/node, malformed input, no change name, a change dir that does not
# exist, or any unexpected error all allow — this hook must never be the reason a command fails.
# Design: docs/openspec-workflow-2-design-2026-11-09.md §4.1(b). Tests: tests/archive-gate.test.sh
set -uo pipefail
allow() { exit 0; }
trap allow ERR

input=$(cat) || allow
# Cheapest exit first: a project without openspec/ has nothing to gate (cwd is only needed when
# CLAUDE_PROJECT_DIR is unset, so this decides the same way as the proj check below).
if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ ! -d "${CLAUDE_PROJECT_DIR%/}/openspec" ]; then allow; fi
command -v jq >/dev/null 2>&1 || allow
command -v perl >/dev/null 2>&1 || allow
command -v node >/dev/null 2>&1 || allow

# The command stays its own jq call: it may hold tabs and newlines, which @tsv would escape.
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || allow
[ -n "$cmd" ] || allow
case $cmd in *OPENSPEC_ARCHIVE_OK=1*) allow ;; esac
# Joined with US (0x1f), not tab: tab is IFS whitespace and would collapse an empty session_id away.
IFS=$'\x1f' read -r session_id cwd < <(printf '%s' "$input" | jq -r '[.session_id // "", .cwd // ""] | join("\u001f")' 2>/dev/null) || allow
session_id="${session_id//[^a-zA-Z0-9._-]/_}"; session_id="${session_id:-unknown}"
proj="${CLAUDE_PROJECT_DIR:-$cwd}"
[ -n "$proj" ] || allow
proj="${proj%/}"

# Change names the command archives, one per line. The text is read three ways (a lexer that reads it
# the way bash does, and two older scanners; what any of them finds counts), so quoted paths are read
# as the shell reads them and words inside quotes (a commit message that mentions
# `openspec archive`) never count; heredoc bodies are dropped. What the shell still runs inside a
# string — $( … ) and backticks within double quotes or an unquoted heredoc body — is scanned as a
# command (the lexer is shared with pr-closeout's merge gate). Only command position counts: the
# first word of a segment after any VAR=value prefixes, shell keywords (then, do, !, {, …) and
# wrappers (env, command, exec, time, nohup); segments split on ; & | ( ) ` and newlines. A command
# string handed to `bash -c`, `sh -lc` or `eval` is parsed the same way. Not seen: a script fed to a
# shell on stdin (`bash <<EOF`, `… | bash`), an alias, a variable holding the command.
IFS= read -r -d '' parser <<'PERL' || true
use strict; use warnings;
# >>> shared-tokenizer: lexer (same bytes in pr-closeout's pr-merge-gate.sh; tests/shared-tokenizer.test.sh compares them)
# The $( … ) and backticks inside the text of a ${…}, each to be read as commands (lex_param); with
# $sq, those inside its '…' are text.
sub subs_of {
  my ($s, $sq) = @_; my @out; my $i = 0; my $n = length $s;   # $sq: '…' at this level is text (not so inside "…")
  while ($i < $n) {
    my $ch = substr($s, $i, 1);
    if ($ch eq "\\") { $i += 2; next; }
    if ($sq && $ch eq "'") { my $j = index($s, "'", $i + 1); last if $j < 0; $i = $j + 1; next; }
    if ($ch eq '`') { my $j = index($s, '`', $i + 1); $j = $n if $j < 0; push @out, substr($s, $i + 1, $j - $i - 1); $i = $j + 1; next; }
    if (substr($s, $i, 2) eq '$(') {
      my ($d, $j) = (1, $i + 2);
      while ($j < $n && $d) { my $c = substr($s, $j, 1); $d++ if $c eq '('; $d-- if $c eq ')'; $j++; }
      push @out, substr($s, $i + 2, $d ? $n - $i - 2 : $j - $i - 3); $i = $j; next;
    }
    $i++;
  }
  return @out;
}
# The command read the way bash reads it, in one pass with a context for each quote and substitution
# (docs/gate-lexer-design-2026-11-13.md). lex_segs returns the commands it holds, those inside every
# $( … ), `…` and ${…} included, as lists of words. A heredoc body is read where bash reads it, at the
# end of its line; one whose delimiter never comes takes the rest of the text, as it does in bash.
# $LEX_UNREAD: set when nesting runs deeper than 50 or the reading takes more than $LEX_MAX steps, so
# what lies past that was not read. The merge gate denies on it; archive-gate, fail-open, does not read it.
# A step is a character one of the loops below looks at; a scan that finds no close and a text copied
# for a reading of its own count every character again, so no input reads for longer than the limit.
our ($LEX_UNREAD, $LEX_STEPS, $LEX_MAX, %LEX_READ) = (0, 0, 3_000_000);
eval { require Digest::MD5; 1 };   # core perl; without it a text is its own key
sub lex_tick { die "lex: step limit\n" if ($LEX_STEPS += $_[0] // 1) > $LEX_MAX; }
sub lex_segs {   # past the limit, the commands read so far; the steps are the whole command's, its bash -c strings included
  my ($s) = @_; my @segs; %LEX_READ = ();
  unless (eval { lex_cmd(\$s, 0, '', \@segs, 0); 1 }) { die $@ unless $@ eq "lex: step limit\n"; $LEX_UNREAD = 1; }
  return @segs;
}
# A text of its own (a substitution's, the rest after a quote, an arithmetic body) read as commands.
# Each text once: the readings below that also read a text a second way nest, and reading the same
# text again could only find the same commands — without this, nested ones cost time exponential in
# their depth.
sub lex_text {
  my ($t, $segs, $depth) = @_;
  lex_tick(length $t);
  return if $LEX_READ{eval { Digest::MD5::md5($t) } // $t}++;
  lex_cmd(\$t, 0, '', $segs, $depth + 1);
}
# A quote that never closes runs to the end, and bash fails there. But a line bash rejects as a syntax
# error is dropped and the lines after it still run (bash 3.2 and 5.3), and a quote on such a line was
# never one: so the text after the quote is read as commands too.
sub lex_rest { my ($sr, $i, $segs, $depth) = @_; lex_text(substr($$sr, $i), $segs, $depth); }
# A $(( or (( is arithmetic only when the ) that closes its first ( is followed at once by another );
# otherwise bash reads it as ( ( … ) … ). Its text is expanded as if in "…" with quotes plain, so the
# $( … ), `…` and ${…} in it run, those inside '…' too (bash 3.2 and 5.3 alike). $[ … ] is the old
# spelling of $(( … )) and is read the same way, up to the ] that closes its [. Where the arithmetic
# ends, bash finds with quotes that count (an unclosed ' in it makes a $( ( … ) … ) of it), so the text
# of a $(( … )) or (( … )) is also read as the ( … ) it would be then.
sub lex_arith {   # a $((, (( or $[ at $i: the index past its close, or undef when it is not arithmetic
  my ($sr, $i, $segs, $depth) = @_; my $n = length $$sr; my $d = 0;
  if ($depth > 50) { $LEX_UNREAD = 1; return $n; }
  $i++ if substr($$sr, $i, 1) eq '$';
  my $from = $i + 1;   # where the ( … ) reading starts
  my ($o, $c, $last) = substr($$sr, $i, 1) eq '[' ? ('[', ']', 0) : ('(', ')', 1);
  while ($i < $n) {
    lex_tick();
    my $x = substr($$sr, $i, 1);
    if ($x eq "\\") { $i += 2; next; }
    if (substr($$sr, $i, 2) eq '$(') {
      my $j = substr($$sr, $i, 3) eq '$((' ? lex_arith($sr, $i, $segs, $depth + 1) : undef;
      $i = defined $j ? $j : lex_cmd($sr, $i + 2, ')', $segs, $depth + 1); next;
    }
    if ($x eq '`') { $i = lex_bq($sr, $i, $segs, $depth, 1); next; }
    if (substr($$sr, $i, 2) eq '${') { my $j = lex_param($sr, $i, $segs, $depth, 0); if (defined $j) { $i = $j; next; } }
    if ($x eq $o) { $d++ } elsif ($x eq $c && --$d == $last) {
      return $i + 1 unless $last;
      return undef unless substr($$sr, $i + 1, 1) eq ')';
      lex_text(substr($$sr, $from, $i + 1 - $from), $segs, $depth);
      return $i + 2;
    }
    $i++;
  }
  lex_rest($sr, $from, $segs, $depth);   # it never closed: bash fails there, or drops only that line (as for a quote)
  return $n;
}
sub param_end {   # the index past the } that closes a ${ at $i, a quoted } not counting; undef when it never comes
  my ($sr, $i) = @_; my $n = length $$sr; my ($d, $j) = (1, $i + 2);
  while ($j < $n && $d) {
    lex_tick();
    my $x = substr($$sr, $j, 1);
    if ($x eq "\\") { $j += 2; next; }
    if ($x eq "'") { my $k = index($$sr, "'", $j + 1); lex_tick(($k < 0 ? $n : $k) - $j); return undef if $k < 0; $j = $k + 1; next; }
    if ($x eq '"') { my $k = $j + 1; while ($k < $n && substr($$sr, $k, 1) ne '"') { $k++ if substr($$sr, $k, 1) eq "\\"; $k++; } lex_tick($k - $j); return undef if $k >= $n; $j = $k + 1; next; }
    if (substr($$sr, $j, 2) eq '${') { $d++; $j += 2; next; }   # only a nested ${ opens a level: a bare { is text
    $d-- if $x eq '}'; $j++;
  }
  return $d ? undef : $j;
}
sub lex_bq {   # a `…` at $i: bash finds its closing backtick first, then reads the text as a command line
  my ($sr, $i, $segs, $depth, $indq) = @_; my $n = length $$sr; my ($j, $t) = ($i + 1, '');
  my $esc = $indq ? qr/[\\`\$"]/ : qr/[\\`\$]/;
  while ($j < $n && substr($$sr, $j, 1) ne '`') { $j++ if substr($$sr, $j, 1) eq "\\" && substr($$sr, $j + 1, 1) =~ $esc; $t .= substr($$sr, $j, 1); $j++; }
  lex_tick($j - $i);
  lex_text($t, $segs, $depth);
  return $j < $n ? $j + 1 : $n;
}
sub lex_param {   # a ${…} at $i ($sq: its '…' is text): the index past it, or undef when its } never comes
  my ($sr, $i, $segs, $depth, $sq) = @_;
  my $j = param_end($sr, $i); return undef unless defined $j;
  if (substr($$sr, $i + 2, 1) =~ /[ \t\n|]/) {   # ${ cmd; } and ${| cmd; }: bash 5.3 runs it (3.2 rejects it)
    my $x = substr($$sr, $i + 2, $j - $i - 3); $x =~ s/^\|//; lex_text($x, $segs, $depth);
  } else {
    lex_text($_, $segs, $depth) for subs_of(substr($$sr, $i, $j - $i), $sq);
  }
  return $j;
}
# The value of a substitution is bash's to know, so a mark stands where it goes. Inside "…", and for
# arithmetic, it is \x01: part of exactly one word (`--match-head-commit "$(git rev-parse HEAD)"` is a
# word in its place). Unquoted, a $( … ), `…` or ${…} is \x02: any number of words, none included
# (`gh $(true) pr merge 3` is a merge; in `--subject $(x) 3` the 3 may be the subject). As a name a word
# is read without its marks (lex_kw: `` `x`openspec `` is openspec); a value with one is the gate's to
# read: the merge gate takes it as unknown (`gh pr merge 3$(echo 0)` merges 30, not 3), archive-gate
# as empty.
sub lex_kw { (my $w = $_[0] // '') =~ tr/\x01\x02//d; return $w; }
sub lex_dq {   # the inside of "…" from $i: the index past its closing ", its text (\x01 where a substitution is)
  my ($sr, $i, $segs, $depth, $body) = @_; my $n = length $$sr; my ($t, $from) = ('', $i);   # $body: an unquoted heredoc body, where " is text
  while ($i < $n) {
    lex_tick();
    my $ch = substr($$sr, $i, 1);
    return ($i + 1, $t) if $ch eq '"' && !$body;
    if ($ch eq "\\") { my $e = substr($$sr, $i + 1, 1); $t .= $e eq "\n" ? '' : $e =~ ($body ? qr/[\$`\\]/ : qr/[\$`"\\]/) ? $e : "\\$e"; $i += 2; next; }
    if (substr($$sr, $i, 3) eq '$((' || substr($$sr, $i, 2) eq '$[') { my $j = lex_arith($sr, $i, $segs, $depth); if (defined $j) { $i = $j; $t .= "\x01"; next; } }
    if (substr($$sr, $i, 2) eq '$(') { $i = lex_cmd($sr, $i + 2, ')', $segs, $depth + 1); $t .= "\x01"; next; }
    if ($ch eq '`') { $i = lex_bq($sr, $i, $segs, $depth, 1); $t .= "\x01"; next; }
    if (substr($$sr, $i, 2) eq '${') {   # inside "…" a ' in ${…} is a plain character, so what it holds runs
      my $j = lex_param($sr, $i, $segs, $depth, 0);
      if (defined $j) { $i = $j; $t .= "\x01"; next; }
    }
    $t .= $ch; $i++;
  }
  lex_rest($sr, $from, $segs, $depth) unless $body;   # the " never closed
  return ($n, $t);
}
# lex_cmd: commands from $i up to the $end that closes this level (')' for $( … ), '' for the whole
# text); returns the index past it. Each command is a new list in @$segs, nested ones included.
sub lex_cmd {
  my ($sr, $i, $end, $segs, $depth) = @_; my $n = length $$sr;
  if ($depth > 50) { $LEX_UNREAD = 1; return $n; }
  my $cur = []; push @$segs, $cur;
  my ($tok, $skip, $par, @pend) = (undef, 0, 0);   # $skip: the next word is a redirection's target; @pend: [delimiter, quoted, strip tabs]
  my $word = sub { if (defined $tok) { if ($skip) { $skip = 0 } else { push @$cur, $tok } } undef $tok; };
  my $seg = sub { $word->(); $skip = 0; $cur = []; push @$segs, $cur; };
  while ($i < $n) {
    lex_tick();
    my $ch = substr($$sr, $i, 1);
    if ($ch eq "\\") { my $e = substr($$sr, $i + 1, 1); $tok .= $e eq '' ? "\\" : $e unless $e eq "\n"; $i += 2; next; }   # \⏎ joins two lines; a \ at the very end is itself
    if ($ch eq "'") { my $j = index($$sr, "'", $i + 1); if ($j < 0) { $j = $n; lex_rest($sr, $i + 1, $segs, $depth); } $tok .= substr($$sr, $i + 1, $j - $i - 1); $i = $j + 1; next; }
    # $'…': \' \" and \\ are decoded; any other escape keeps its backslash, so a word built with one is never read as other text
    if ($ch eq '$' && substr($$sr, $i + 1, 1) eq "'") { my $j = $i + 2; $tok .= ''; while ($j < $n && substr($$sr, $j, 1) ne "'") { if (substr($$sr, $j, 1) eq "\\") { my $e = substr($$sr, $j + 1, 1); $tok .= "\\" unless $e =~ /[\\'"]/; $j++; } $tok .= substr($$sr, $j, 1); $j++; } lex_tick($j - $i); lex_rest($sr, $i + 2, $segs, $depth) if $j >= $n; $i = $j + 1; next; }
    if ($ch eq '"') { my ($j, $t) = lex_dq($sr, $i + 1, $segs, $depth); $tok .= $t; $i = $j; next; }
    if (substr($$sr, $i, 3) eq '$((' || substr($$sr, $i, 2) eq '$[') { my $j = lex_arith($sr, $i, $segs, $depth); if (defined $j) { $i = $j; $tok .= "\x01"; next; } }
    if (substr($$sr, $i, 2) eq '$(') { $i = lex_cmd($sr, $i + 2, ')', $segs, $depth + 1); $tok .= "\x02"; next; }
    if ($ch eq '`') { $i = lex_bq($sr, $i, $segs, $depth, 0); $tok .= "\x02"; next; }
    if (substr($$sr, $i, 2) eq '${') {   # one word to bash; what runs in it is read as commands, except inside its own '…'
      my $j = lex_param($sr, $i, $segs, $depth, 1);
      if (defined $j) { $i = $j; $tok .= "\x02"; next; }
    }
    # a # that starts a word comments out the rest of the line (inside `…`, its text is a line of its own)
    if ($ch eq '#' && !defined $tok && ($i == 0 || substr($$sr, $i - 1, 1) =~ /[ \t\n;&|(]/)) { my $j = index($$sr, "\n", $i); $i = $j < 0 ? $n : $j; next; }
    if (!defined $tok && substr($$sr, $i, 2) eq '((') {   # (( … )): arithmetic, << in it is a shift
      my $j = lex_arith($sr, $i, $segs, $depth); if (defined $j) { $i = $j; next; }
    }
    if (substr($$sr, $i, 3) eq '<<<') { $word->(); $skip = 1; $i += 3; next; }   # here-string: the word after it is data
    if (substr($$sr, $i, 2) eq '<<') {   # heredoc: the delimiter is the whole word, its quoted and unquoted parts joined
      $word->(); my $strip = substr($$sr, $i + 2, 1) eq '-' ? 1 : 0; my $j = $i + 2 + $strip;
      $j++ while $j < $n && substr($$sr, $j, 1) =~ /[ \t]/;
      my ($d, $quoted) = ('', 0);
      while ($j < $n) {
        my $x = substr($$sr, $j, 1);
        last if $x =~ /[ \t\n;&|()<>]/;
        # a ${…} or `…` in it is part of the word, and a quote or \ inside one does not make the body literal
        if (substr($$sr, $j, 2) eq '${') { my $k = param_end($sr, $j); if (defined $k) { $d .= substr($$sr, $j, $k - $j); $j = $k; next; } }
        if ($x eq '`') { my $k = index($$sr, '`', $j + 1); $k = $n - 1 if $k < 0; $d .= substr($$sr, $j, $k + 1 - $j); $j = $k + 1; next; }
        if ($x eq "'" || $x eq '"') { my $k = index($$sr, $x, $j + 1); if ($k < 0) { $k = $n; lex_rest($sr, $j + 1, $segs, $depth); } $d .= substr($$sr, $j + 1, $k - $j - 1); $quoted = 1; $j = $k + 1; next; }
        if ($x eq "\\") { if (substr($$sr, $j + 1, 1) ne "\n") { $d .= substr($$sr, $j + 1, 1); $quoted = 1; } $j += 2; next; }   # \⏎ joins lines
        $d .= $x; $j++;
      }
      lex_tick($j - $i);
      push @pend, [$d, $quoted, $strip] if length $d;
      $i = $j; next;
    }
    if ($ch eq '<' || $ch eq '>') {   # redirection: a number right before it is the fd, the word after it the target
      undef $tok if defined $tok && $tok =~ /^\d+$/;
      $word->(); my $j = $i + 1; $j++ while $j < $n && substr($$sr, $j, 1) =~ /[<>&|]/;
      $skip = 1; $i = $j; next;
    }
    if ($ch eq '(') { $par++; $seg->(); $i++; next; }
    if ($ch eq ')') { if ($par) { $par-- } elsif ($end eq ')') { $word->(); return $i + 1; } $seg->(); $i++; next; }
    if ($ch eq ';' || $ch eq '&' || $ch eq '|') { $seg->(); $i++; next; }
    if ($ch eq "\n") {
      $seg->(); $i++;
      while (my $h = shift @pend) {   # each heredoc of the line, in order: its body ends at a line equal to its delimiter
        my ($d, $quoted, $strip) = @$h; my ($p, $stop, $next) = ($i);
        while (1) {
          my $e = index($$sr, "\n", $p); $e = $n if $e < 0; lex_tick($e - $p + 1);
          my $raw = substr($$sr, $p, $e - $p); my $l = $raw; $l =~ s/^\t+// if $strip;
          if ($l eq $d) { ($stop, $next) = ($p, $e < $n ? $e + 1 : $n); last; }
          # inside $( … ) a line DELIM) ends the body there, and the ) closes the substitution (bash 3.2 and 5.3 alike)
          if ($end eq ')' && substr($l, 0, length($d) + 1) eq "$d)") { ($stop, $next) = ($p, $p + length($raw) - length($l) + length $d); last; }
          last if $e >= $n; $p = $e + 1;
        }
        if (!defined $stop) {
          # Its delimiter never comes. To bash the rest of the text is its body and no line of it runs —
          # unless this was no heredoc (a shift: `let x=1<<n`), or bash dropped its line as a syntax
          # error: then the lines run. So it is read both ways: the rest as a body, for what an unquoted
          # one expands, and then as if there were no heredoc, the lines after it as commands.
          unless ($quoted) { my $x = substr($$sr, $i); lex_dq(\$x, 0, $segs, $depth, 1); }
          next;
        }
        unless ($quoted) { my $x = substr($$sr, $i, $stop - $i); lex_dq(\$x, 0, $segs, $depth, 1); }   # an unquoted body is expanded as in "…"
        $i = $next;
      }
      next;
    }
    if ($ch eq ' ' || $ch eq "\t") { $word->(); $i++; next; }
    $tok .= $ch; $i++;
  }
  $word->();
  return $n;
}
# <<< shared-tokenizer: lexer
my %seen;
# The command is read three times and what any reading finds counts. The first knows comments and
# ${…}; the second ($plain) is the reading from before those rules; the third ($mode 2) is the lexer.
# The older readings stay so that a mistake in a newer one can add to what is caught but never take
# away (docs/gate-lexer-design-2026-11-13.md §4).
for my $mode (0, 1, 2) {
my $plain = $mode == 1;
my @queue = ($ENV{AG_CMD} // ''); my $rounds = 0;
# A command string handed to a shell runs too (`bash -c '…'`, `sh -lc '…'`, `eval …`): it is queued and
# parsed like the command itself. 50 rounds bound a string that keeps quoting itself.
while (@queue && $rounds++ < 50) {
my $c = shift @queue;
# >>> shared-tokenizer: heredoc pass and tokenizer (same bytes in pr-closeout's pr-merge-gate.sh, indentation aside)
# Heredoc bodies, found in one pass over the characters that carries an open quote from line to
# line: a << opens a heredoc only outside quotes (a $( … ) starts over, unquoted, inside the quote
# around it) and outside $(( … )) and (( … )), where it is a shift; never in a # comment or a
# here-string (<<<). $'…' is a quote whose \' does not close it. The delimiter
# is the whole word (<<EOF-TEXT closes on EOF-TEXT), quoted or \-escaped too. Bodies start on the
# line after the command line ends (after the string closes or the trailing-backslash
# continuation runs out, when that line left one open), one per << on that line in order, each
# ending at a line equal to its delimiter. An unquoted body still runs its $( … ) and backticks.
# A heredoc whose delimiter line never comes is not one ($((1<<n)) looks like it): its lines are
# put back and scanned again (fail closed), the later heredocs of its line first.
my @segs;
if ($mode == 2) { @segs = lex_segs($c); } else {   # the third reading is the lexer; the two below are the older scanners
my @todo = split /\n/, $c, -1; my @keep; my @hd;   # @hd: [delimiter, quoted] whose bodies come next
my ($q, $ar, @st) = ('', 0);   # open quote, $(( )) depth, quote outside each open (: kept when a body is rescanned
while (@todo) {
  my (@pend, @body);
  while (@todo) {
    my $l = shift @todo;
    if (@hd) {
      push @body, $l; (my $t = $l) =~ s/^\t+//;
      # the body as one text: a $( … ) may run across lines, and only the whole of it says which lines it holds
      if ($t eq $hd[0][0]) { push @queue, subs_of(join "\n", @body) unless $hd[0][1]; shift @hd; @body = (); }
      next;
    }
    push @keep, $l; my $cont = 0;
    for (my $i = 0; $i < length $l; $i++) {
      my $ch = substr($l, $i, 1);
      if ($ar) { $ar++ if $ch eq '('; $ar-- if $ch eq ')'; next; }             # not-a-heredoc: arithmetic
      if ($q eq "'") { $q = '' if $ch eq "'"; next; }
      if ($q eq 'A') { if ($ch eq "\\") { $i++; next; } $q = '' if $ch eq "'"; next; }   # $'…': \' does not close it
      if ($ch eq "\\") { $cont = 1 if $i == length($l) - 1; $i++; next; }        # not-a-heredoc: continuation
      last if $q eq '' && $ch eq '#' && ($i == 0 || substr($l, $i - 1, 1) =~ /[\s;&|()]/);   # not-a-heredoc: comment
      my $sub = $ch eq '$' && substr($l, $i + 1, 1) eq '(';
      if ($sub ? substr($l, $i + 2, 1) eq '(' : $q eq '' && substr($l, $i, 2) eq '((') { $ar = 2; $i += $sub ? 2 : 1; next; }
      if ($sub) { push @st, $q; $q = ''; $i++; next; }                           # not-a-heredoc: substitution
      if ($q eq '"') { $q = '' if $ch eq '"'; next; }
      if ($ch eq '$' && substr($l, $i + 1, 1) eq "'") { $q = 'A'; $i++; next; }               # not-a-heredoc: ansi-c
      if ($ch eq "'" || $ch eq '"') { $q = $ch; next; }                          # not-a-heredoc: quoted
      if ($ch eq '(') { push @st, ''; next; }
      if ($ch eq ')') { $q = pop @st if @st; next; }
      if (substr($l, $i, 3) eq '<<<') { $i += 2; next; }                        # not-a-heredoc: here-string
      next unless substr($l, $i) =~ /^<<-?\s*(?:'([^']+)'|"([^"]+)"|(\\?)([A-Za-z_][^\s;&|()<>'"\\`]*))/;
      push @pend, [$1 // $2 // $4, defined $1 || defined $2 || $3 ne ''];
      $i += length($&) - 1;
    }
    if (@pend && $q eq '' && !$cont) { @hd = @pend; @pend = (); }
  }
  if (@hd) { shift @hd; @todo = @body; }   # never closed: scan its lines again as commands (fail closed)
}
$c = join "\n", @keep;
@segs = ([]); my $tok; my $i = 0; my $n = length $c; my $bq = 0;   # $bq: inside a `…` substitution
my $endtok = sub { push @{$segs[-1]}, $tok if defined $tok; undef $tok; };
while ($i < $n) {
  my $ch = substr($c, $i, 1);
  # $'…': \' \" and \\ are decoded; any other escape (\n, \062, \x41) keeps its backslash, so a word built
  # with one is never read as other text — a PR number or a change name written that way is not one
  if ($ch eq '$' && substr($c, $i + 1, 1) eq "'") { my $j = $i + 2; $tok //= ''; while ($j < $n && substr($c, $j, 1) ne "'") { if (substr($c, $j, 1) eq "\\") { my $e = substr($c, $j + 1, 1); $tok .= "\\" unless $e =~ /[\\'"]/; $j++; } $tok .= substr($c, $j, 1); $j++; } $i = $j + 1; next; }   # ansi-c: tokenizer
  # ${…} is the inside of one word to bash: a #, a quote or a blank in it starts nothing. Taken whole
  # into the word, up to the } that closes it — one inside '…' or "…" does not. The $( … ) and
  # backticks it holds still run, except inside '…', so those are scanned on their own.
  # Left to the rules below when its } (or the end of a quote in it) never comes.
  if (!$plain && $ch eq '$' && substr($c, $i + 1, 1) eq '{') {
    my ($d, $j) = (1, $i + 2);
    while ($j < $n && $d) {
      my $x = substr($c, $j, 1);
      if ($x eq "\\") { $j += 2; next; }
      if ($x eq "'") { my $k = index($c, "'", $j + 1); last if $k < 0; $j = $k + 1; next; }
      if ($x eq '"') { my $k = $j + 1; while ($k < $n && substr($c, $k, 1) ne '"') { $k++ if substr($c, $k, 1) eq "\\"; $k++; } last if $k >= $n; $j = $k + 1; next; }
      if (substr($c, $j, 2) eq '${') { $d++; $j += 2; next; }   # only a nested ${ opens a level: a bare { is text
      $d-- if $x eq '}'; $j++;
    }
    if (!$d) { my $w = substr($c, $i, $j - $i); push @queue, subs_of($w, 1); $tok .= $w; $i = $j; next; }
  }
  # a # that starts a word comments out the rest of its line — inside `…`, the rest up to the closing
  # backtick — so an apostrophe in it opens no string (the heredoc pass has its own test). A word
  # starts at the start, after a blank or newline, after ; & | ( or after an opening backtick: not
  # after the ) or backtick that closes a substitution, where bash is still in the same word.
  if (!$plain && $ch eq '#' && !defined $tok && ($i == 0 || substr($c, $i - 1, 1) =~ /[ \t\n;&|(]/ || ($bq && substr($c, $i - 1, 1) eq '`'))) {
    my $j = index($c, "\n", $i); $j = $n if $j < 0;
    if ($bq) { my $k = index($c, '`', $i); $j = $k if $k >= 0 && $k < $j; }
    $i = $j; next;
  }
  if ($ch eq "'") { my $j = index($c, "'", $i + 1); $j = $n if $j < 0; $tok .= substr($c, $i + 1, $j - $i - 1); $i = $j + 1; next; }
  if ($ch eq '"') {
    my $j = $i + 1; $tok //= '';
    while ($j < $n && substr($c, $j, 1) ne '"') { if (substr($c, $j, 1) eq "\\") { $j++; } $tok .= substr($c, $j, 1); $j++; }
    push @queue, subs_of(substr($c, $i + 1, $j - $i - 1));   # the raw text, escapes kept: subs_of skips \$ and \`
    $i = $j + 1; next;
  }
  if ($ch eq "\\") { $tok .= substr($c, $i + 1, 1); $i += 2; next; }
  if ($ch =~ /[;&|()`\n]/) { $bq = !$bq if $ch eq '`'; $endtok->(); push @segs, []; $i++; next; }   # a backtick opens a command too
  if ($ch =~ /\s/) { $endtok->(); $i++; next; }
  $tok .= $ch; $i++;
}
$endtok->();
}
# <<< shared-tokenizer: heredoc pass and tokenizer
for my $s (@segs) {
  # Command position: after VAR=value prefixes, and after the shell keywords and wrappers a command
  # can sit behind (`if …; then openspec archive x`, `! …`, `env X=1 …`, `command …`).
  # Every word is read as lex_kw reads it, a substitution in it taken as empty: for a change name that is
  # the one bash archives when it expands to nothing, and a name this hook checks beats one it lets
  # through unread (fail-open). The merge gate reads values the other way (fail-closed).
  # A word that is a substitution alone reads as empty, as one that expands to nothing: skipped.
  my @t = grep { $_ ne '' } map { lex_kw($_) } @$s; shift @t while @t && $t[0] =~ /^(?:[A-Za-z_]\w*=.*|if|then|elif|else|while|until|do|time|exec|command|env|nohup|!|\{)$/s;   # command-position: prefixes
  next unless @t;
  # A command string handed to a shell runs too, when the shell or eval is itself the command.
  my $w = ($t[0] =~ m{([^/]+)$})[0] // '';
  if ($w =~ /^(?:ba|z|da|k)?sh$/) {                                                # shell-string: queue
    for (my $m = 1; $m < @t; $m++) { if ($t[$m] =~ /^-[A-Za-z]*c[A-Za-z]*$/) { push @queue, $t[$m + 1] if defined $t[$m + 1]; last; } }
    next;
  }
  if ($w eq 'eval') { push @queue, join ' ', @t[1 .. $#t]; next; }
  if ($t[0] eq 'openspec' && @t > 1 && $t[1] eq 'archive') {
    my ($name) = grep { !/^-/ } @t[2 .. $#t];
    print "$name\n" if defined $name && !$seen{$name}++;
  } elsif ($t[0] eq 'mv') {
    my @args = grep { !/^-/ } @t[1 .. $#t];
    next unless @args >= 2 && $args[-1] =~ m{(^|/)changes/archive(/|$)};
    for my $src (@args[0 .. $#args - 1]) {
      (my $p = $src) =~ s{/+$}{};
      next unless $p =~ m{(^|/)changes/([^/]+)$};
      print "$2\n" unless $seen{$2}++;
    }
  }
}
}
}
PERL

names=$(AG_CMD=$cmd perl -e "$parser" 2>/dev/null) || allow
[ -n "$names" ] || allow

here=$(dirname "${BASH_SOURCE[0]}")
check_dir=$(cd "$here/../skills/openspec-superpowers-workflow/validators" 2>/dev/null && pwd) || allow
check="$check_dir/reconcile-check.cjs"
[ -f "$check" ] || allow

failures=""; verified=0
while IFS= read -r name; do
  [ -n "$name" ] || continue
  dir="$proj/openspec/changes/$name"
  [ -d "$dir" ] || continue
  # `|| rc=$?`, not a bare assignment: a non-zero exit would fire the ERR trap, which allows.
  rc=0; reason=$(node "$check" verify "$dir" 2>/dev/null) || rc=$?
  # verify answers with exit 3 (no verdict, or stale); node's own crash exit is 1, so anything but
  # 0 and 3 is the checker failing, not the change — fail-open.
  case $rc in
    0) verified=1 ;;
    3) failures+="  - ${name}: ${reason}"$'\n' ;;
  esac
done <<< "$names"

if [ -n "$failures" ]; then
  reason="⛔ openspec 歸檔閘門：下列 change 沒有有效的 Phase 6 核查結果，歸檔已擋下。
${failures}no-verdict＝還沒跑過 check，或上一次 check 沒有通過；stale:<artifact>＝check 之後該檔又被改過；stale:rules＝這份結果是舊版核查規則寫的（plugin 升級後要重跑 check）。
處理方式：Phase 6 開始時先跑 \`node ${check} snapshot <change 目錄>\`；reconcile 完成後跑 \`node ${check} check <change 目錄>\`，逐項處理 fail 與 warn，並在回覆中寫出 manual 項（C1、C2、C5）的判斷。check 通過、且之後沒有再改檔，才能歸檔。review-notes 最後一輪必須標 final，而且只有使用者明說 review 已收斂後才能加。
確定要略過本閘門：在命令前加 OPENSPEC_ARCHIVE_OK=1。"
  jq -cn --arg r "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
fi

if [ "$verified" = 1 ]; then touch "${TMPDIR:-/tmp}/claude-openspec-archived-${session_id}" 2>/dev/null || true; fi
allow
