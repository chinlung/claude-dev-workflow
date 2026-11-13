#!/bin/bash
# pr-closeout PreToolUse merge gate (matchers: Bash, and the GitHub MCP merge_pull_request tool).
#
# Before a PR is merged — `gh pr merge`, `gh api …/pulls/<n>/merge`, or the MCP merge tool — this
# hook runs `pr-closeout.mjs ready` for that PR itself and lets the merge through only on exit 0.
# Anything else is denied with the exit, the gate and what ready found. It asks GitHub itself
# rather than trusting a marker file: inside and outside the sandbox $TMPDIR differs, and a marker
# the sandbox can write is one it can forge.
#
# Which PR: `gh pr merge <n|url> --repo|-R <owner/repo> [--match-head-commit <sha>]` (the sha
# becomes --expect-head), `gh api repos/<owner>/<repo>/pulls/<n>/merge`, or the MCP tool's owner,
# repo, pullNumber and sha. A merge whose repo or number cannot be read is denied: write them out.
# Only command position counts (a shell-word tokenizer; quoted text and heredoc bodies never match,
# except the $( … ) and backticks the shell still runs inside double quotes or an unquoted heredoc body).
# Bypass for one command: PR_CLOSEOUT_OK=1 in it (the MCP tool has no bypass; use gh).
#
# A gate, so it fails closed: no jq, no node or no ready script denies a merge (and says how to
# bypass). Commands that are not a merge are allowed at once — after one `cat` to read the input,
# the first test is a builtin `case` on it, so ordinary Bash calls start no jq, perl or node.
# Design: docs/pr-closeout-skill-design-2026-11-09.md (D7). Tests: tests/pr-merge-gate.test.sh
set -uo pipefail
allow() { exit 0; }
deny() {
  local r="⛔ pr-closeout merge 閘門：$1
確定要略過：在命令前加 PR_CLOSEOUT_OK=1（只對 gh 有效；MCP 的 merge 工具請改用 gh）。"
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg r "$r" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  else
    printf '%s\n' "$r" >&2; exit 2
  fi
  exit 0
}

input=$(cat) || allow
case $input in *[Mm][Ee][Rr][Gg][Ee]*) ;; *) allow ;; esac   # any case: enablePullRequestAutoMerge
command -v jq >/dev/null 2>&1 || deny "需要 jq 才能判斷這是不是 merge。"
tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null) || deny "讀不懂 hook 的輸入。"

targets=""   # one line per merge: <owner/repo or -> <number or -> <head sha or ->
if [ "$tool" = Bash ]; then
  cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || deny "讀不懂 hook 的輸入。"
  case $cmd in *PR_CLOSEOUT_OK=1*) allow ;; esac
  command -v perl >/dev/null 2>&1 || deny "需要 perl 才能判斷這是不是 merge。"
  # Merges in command position, one per line. Same tokenizer as openspec's archive-gate: quoted
  # words never count and heredoc bodies are dropped, except the $( … ) and backticks the shell still
  # runs inside double quotes or an unquoted heredoc body (the heredoc pass is described where it runs).
  IFS= read -r -d '' parser <<'PERL' || true
use strict; use warnings;
# >>> shared-tokenizer: subs_of (same bytes in openspec's archive-gate.sh; tests/shared-tokenizer.test.sh compares them)
# Text the shell still runs although it sits inside a string: $( … ) and backticks within double
# quotes or an unquoted heredoc body. Each is scanned again as a command.
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
# <<< shared-tokenizer: subs_of
# >>> shared-tokenizer: lexer (same bytes in openspec's archive-gate.sh; tests/shared-tokenizer.test.sh compares them)
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
# The value of a substitution is bash's to know: a word keeps only its literal parts, and a word made
# of substitutions alone is left out (`` `x`openspec `` is the command openspec; `$(echo foo)` names nothing).
sub lex_dq {   # the inside of "…" from $i: the index past its closing ", its literal text, whether it held a substitution
  my ($sr, $i, $segs, $depth, $body) = @_; my $n = length $$sr; my ($t, $sub, $from) = ('', 0, $i);   # $body: an unquoted heredoc body, where " is text
  while ($i < $n) {
    lex_tick();
    my $ch = substr($$sr, $i, 1);
    return ($i + 1, $t, $sub) if $ch eq '"' && !$body;
    if ($ch eq "\\") { my $e = substr($$sr, $i + 1, 1); $t .= $e eq "\n" ? '' : $e =~ ($body ? qr/[\$`\\]/ : qr/[\$`"\\]/) ? $e : "\\$e"; $i += 2; next; }
    if (substr($$sr, $i, 3) eq '$((' || substr($$sr, $i, 2) eq '$[') { my $j = lex_arith($sr, $i, $segs, $depth); if (defined $j) { $i = $j; $sub = 1; next; } }
    if (substr($$sr, $i, 2) eq '$(') { $i = lex_cmd($sr, $i + 2, ')', $segs, $depth + 1); $sub = 1; next; }
    if ($ch eq '`') { $i = lex_bq($sr, $i, $segs, $depth, 1); $sub = 1; next; }
    if (substr($$sr, $i, 2) eq '${') {   # inside "…" a ' in ${…} is a plain character, so what it holds runs
      my $j = lex_param($sr, $i, $segs, $depth, 0);
      if (defined $j) { $i = $j; $sub = 1; next; }
    }
    $t .= $ch; $i++;
  }
  lex_rest($sr, $from, $segs, $depth) unless $body;   # the " never closed
  return ($n, $t, $sub);
}
# lex_cmd: commands from $i up to the $end that closes this level (')' for $( … ), '' for the whole
# text); returns the index past it. Each command is a new list in @$segs, nested ones included.
sub lex_cmd {
  my ($sr, $i, $end, $segs, $depth) = @_; my $n = length $$sr;
  if ($depth > 50) { $LEX_UNREAD = 1; return $n; }
  my $cur = []; push @$segs, $cur;
  my ($tok, $sub, $skip, $par, @pend) = (undef, 0, 0, 0);   # $sub: the word held a substitution; $skip: the next word is a redirection's target; @pend: [delimiter, quoted, strip tabs]
  my $word = sub { if (defined $tok && ($tok ne '' || !$sub)) { if ($skip) { $skip = 0 } else { push @$cur, $tok } } undef $tok; $sub = 0; };
  my $seg = sub { $word->(); $skip = 0; $cur = []; push @$segs, $cur; };
  while ($i < $n) {
    lex_tick();
    my $ch = substr($$sr, $i, 1);
    if ($ch eq "\\") { my $e = substr($$sr, $i + 1, 1); $tok .= $e eq '' ? "\\" : $e unless $e eq "\n"; $i += 2; next; }   # \⏎ joins two lines; a \ at the very end is itself
    if ($ch eq "'") { my $j = index($$sr, "'", $i + 1); if ($j < 0) { $j = $n; lex_rest($sr, $i + 1, $segs, $depth); } $tok .= substr($$sr, $i + 1, $j - $i - 1); $i = $j + 1; next; }
    # $'…': \' \" and \\ are decoded; any other escape keeps its backslash, so a word built with one is never read as other text
    if ($ch eq '$' && substr($$sr, $i + 1, 1) eq "'") { my $j = $i + 2; $tok .= ''; while ($j < $n && substr($$sr, $j, 1) ne "'") { if (substr($$sr, $j, 1) eq "\\") { my $e = substr($$sr, $j + 1, 1); $tok .= "\\" unless $e =~ /[\\'"]/; $j++; } $tok .= substr($$sr, $j, 1); $j++; } lex_tick($j - $i); lex_rest($sr, $i + 2, $segs, $depth) if $j >= $n; $i = $j + 1; next; }
    if ($ch eq '"') { my ($j, $t, $s) = lex_dq($sr, $i + 1, $segs, $depth); $tok .= $t; $sub ||= $s; $i = $j; next; }
    if (substr($$sr, $i, 3) eq '$((' || substr($$sr, $i, 2) eq '$[') { my $j = lex_arith($sr, $i, $segs, $depth); if (defined $j) { $i = $j; $tok .= ''; $sub = 1; next; } }
    if (substr($$sr, $i, 2) eq '$(') { $i = lex_cmd($sr, $i + 2, ')', $segs, $depth + 1); $tok .= ''; $sub = 1; next; }
    if ($ch eq '`') { $i = lex_bq($sr, $i, $segs, $depth, 0); $tok .= ''; $sub = 1; next; }
    if (substr($$sr, $i, 2) eq '${') {   # one word to bash; what runs in it is read as commands, except inside its own '…'
      my $j = lex_param($sr, $i, $segs, $depth, 1);
      if (defined $j) { $i = $j; $tok .= ''; $sub = 1; next; }
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
        if ($x eq "'" || $x eq '"') { my $k = index($$sr, $x, $j + 1); $k = $n if $k < 0; $d .= substr($$sr, $j + 1, $k - $j - 1); $quoted = 1; $j = $k + 1; next; }
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
        if (!defined $stop) {   # its delimiter never comes: the rest of the text is its body, and no line of it runs
          unless ($quoted) { my $x = substr($$sr, $i); lex_dq(\$x, 0, $segs, $depth, 1); }
          return $n;
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
my %takes = map { $_ => 1 } qw(--subject -t --body -b --body-file -F --author-email -A);   # gh pr merge options with a value
my %printed;
sub out { print $_[0] unless $printed{$_[0]}++ }   # the three readings below often find the same merge
# The command is read three times and what any reading finds counts. The first knows comments and
# ${…}; the second ($plain) is the reading from before those rules; the third ($mode 2) is the lexer.
# The older readings stay so that a mistake in a newer one can add to what is caught but never take
# away (docs/gate-lexer-design-2026-11-13.md §4).
for my $mode (0, 1, 2) {
my $plain = $mode == 1;
my @queue = ($ENV{PMG_CMD} // ''); my $rounds = 0;
while (@queue && $rounds++ < 50) {
  my $c = shift @queue;
  # >>> shared-tokenizer: heredoc pass and tokenizer (same bytes in openspec's archive-gate.sh, indentation aside)
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
    # a command string handed to a shell runs too: `bash -c '…'`, `sh -lc '…'`, `eval …`
    for (my $k = 0; $k < @$s; $k++) {
      my $w = ($s->[$k] =~ m{([^/]+)$})[0] // '';
      if ($w =~ /^(?:ba|z|da|k)?sh$/) {
        for (my $m = $k + 1; $m < @$s; $m++) { if ($s->[$m] =~ /^-[A-Za-z]*c[A-Za-z]*$/) { push @queue, $s->[$m + 1] if defined $s->[$m + 1]; last; } }
      } elsif ($w eq 'eval') { push @queue, join ' ', @$s[$k + 1 .. $#$s]; last; }
    }
    # gh anywhere in the segment, by basename: wrappers (command, env, time, sudo, xargs…) and a full
    # path to gh still reach it; a stray `echo gh pr merge` is read as a merge too (the safe side)
    my @t = @$s; shift @t while @t && !(($t[0] =~ m{([^/]+)$})[0] eq 'gh');
    next unless @t >= 2;
    my ($repo, $num, $sha, $two) = ('-', '-', '-', 0);
    if ($t[1] eq 'pr' && @t > 2 && $t[2] eq 'merge') {
      my @a = @t[3 .. $#t];
      for (my $k = 0; $k < @a; $k++) {
        my $x = $a[$k];
        if ($takes{$x}) { $k++; next; }
        if ($x eq '--repo' || $x eq '-R') { $repo = $a[++$k] // '-'; next; }
        if ($x =~ /^--repo=(.+)$/) { $repo = $1; next; }
        if ($x eq '--match-head-commit') { $sha = $a[++$k] // '-'; next; }
        if ($x =~ /^--match-head-commit=(.+)$/) { $sha = $1; next; }
        if ($x =~ m{^https://github\.com/([^/]+/[^/]+)/pull/(\d+)}) { $two = 1 if $num ne '-'; $repo = $1; $num = $2; next; }
        if ($x =~ /^\d+$/) { $two = 1 if $num ne '-'; $num = $x; next; }
      }
      $num = '-' if $two;   # two PR numbers: which one gh merges is not this parser's guess
      out("$repo $num $sha\n");
    } elsif ($t[1] eq 'api') {
      my $found = 0;
      for my $x (@t[2 .. $#t]) {
        if ($x =~ m{^/?repos/([^/]+/[^/]+)/pulls/(\d+)/merge/?(?:\?.*)?$}) { out("$1 $2 -\n"); $found = 1; last; }
      }
      # a merge this parser cannot pin to a PR (a GraphQL mergePullRequest, an odd endpoint): unreadable
      out("- - -\n") if !$found && grep { /mergePullRequest|AutoMerge|\/merge/i } @t[2 .. $#t];
    }
  }
}
out("- - -\n") if @queue || $LEX_UNREAD;   # more nested substitutions than this scan follows: unreadable, deny
}
PERL
  targets=$(PMG_CMD=$cmd perl -e "$parser" 2>/dev/null) || deny "無法解析命令。"
  [ -n "$targets" ] || allow
elif [[ $tool == mcp__*merge_pull_request ]]; then
  targets=$(printf '%s' "$input" | jq -r '.tool_input | "\(if .owner and .repo then "\(.owner)/\(.repo)" else "-" end) \(.pullNumber // "-") \(.sha // "-")"' 2>/dev/null) \
    || deny "讀不懂 MCP merge 工具的輸入。"
else
  allow
fi

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
script=${PR_CLOSEOUT_SCRIPT:-"${CLAUDE_PLUGIN_ROOT:-$here/..}/scripts/pr-closeout.mjs"}
command -v node >/dev/null 2>&1 || deny "需要 node 才能執行 pr-closeout ready。"
[ -f "$script" ] || deny "找不到 pr-closeout 腳本：$script"

# One budget for every ready run (PR_MERGE_GATE_BUDGET seconds, default 25) under the hook's 30 s
# timeout in hooks.json: each run gets what is left as its deadline, and too little left is a deny —
# a hook the harness gives up on must never be how a merge gets through. Milliseconds via perl:
# /bin/bash 3.2 has no EPOCHREALTIME.
now_ms() { perl -MTime::HiRes=time -e 'printf "%d", time * 1000'; }
budget_ms=$(( ${PR_MERGE_GATE_BUDGET:-25} * 1000 )); start_ms=$(now_ms)
while read -r repo num sha; do
  [ -n "$repo" ] || continue
  # One line of `repo number sha` per merge, from the parser or from the MCP input. A blank or a newline
  # in a value (a quoted string glued to --repo, an odd MCP field) splits a line, and a split line has
  # no PR number where one belongs: anything but digits there is a merge this hook cannot pin.
  [[ $num =~ ^[0-9]+$ ]] || num=-
  left=$(( budget_ms - ($(now_ms) - start_ms) ))
  if [ "$left" -lt 1000 ]; then
    deny "時間不夠，無法在 hook 的時限內確認 $repo#$num 能否合併。一次只合併一個 PR 再試。"
  fi
  if [ "$repo" = - ] || [ "$num" = - ]; then
    deny "看得出是 merge，但讀不出是哪個 repo 的哪個 PR。請明寫：gh pr merge <號碼> --repo <owner/repo>。"
  fi
  # The sha goes to ready as the head the PR must have. Anything but a literal full sha (a variable
  # or a substitution arrives here unexpanded, a branch name or a short sha is not a head oid) would
  # only come back as head-mismatch, with nothing saying why.
  if [ "$sha" != - ] && [[ ! $sha =~ ^[0-9a-f]{40}$ ]]; then
    deny "$repo#$num 的 --match-head-commit（MCP 的 sha）不是字面的 40 碼 commit sha：「$sha」。hook 看到的是命令文字，變數與 \$( ) 不會展開；請先取得 sha，直接寫進命令。"
  fi
  args=(ready "$repo" "$num")
  [ "$sha" = - ] || args+=(--expect-head "$sha")
  out=$(PR_CLOSEOUT_DEADLINE_MS=$left node "$script" "${args[@]}" 2>/dev/null); rc=$?
  [ "$rc" = 0 ] && continue
  summary=$(printf '%s' "$out" | jq -r '"gate: \(.gate // "-")\n" + ([.hits[]? | "  - \(.code)\(if .gate then " (" + .gate + ")" else "" end)：\(.detail)"] | join("\n"))' 2>/dev/null)
  deny "$repo#$num 還不能合併（pr-closeout ready exit $rc）。
${summary:-（ready 沒有輸出可讀的結果）}
先處理上面列的項目，或照 pr-closeout skill 的收尾步驟走。"
done <<< "$targets"
allow
