#!/usr/bin/perl
# Differential test of the gates' shell tokenizer, with bash itself as the oracle.
#
# Generates commands from a closed grammar (a fixed seed, so every run is the same), runs each one
# with bash in an empty directory whose PATH holds only stubs, and records which `openspec archive
# <name>` / `gh pr merge <n>` bash actually ran. The gate's parser, taken byte for byte from the hook
# (the text between `<<'PERL'` and `PERL`) or from a fixture holding an older parser, must report
# every one of them. That is the one-way property the gates promise: what bash runs, the gate sees.
# The other way does not hold on purpose (`false && openspec archive x` is caught though bash skips
# it), so a parser reporting more than bash ran is never a failure here.
#
# Usage: perl tokenizer-differential.pl --kind ag|pmg --source <hook.sh|parser.pl>
#             [--seed N] [--n N] [--min-exercised N] [--show N] [--known-gaps | --gap I …]
#             [--fixed-by <hook.sh|parser.pl> | --superset-of <hook.sh|parser.pl> [--judge]] [--chars]
# --chars: noise is built from shell punctuation at random (quotes, #, \, <<, $(, ((, ${, `, ; and
#   newlines) instead of the hand-written list, to find kinds of input nobody wrote down yet. Most such
#   commands are syntax errors bash refuses; those run nothing and are not counted as exercised.
# --known-gaps adds the grammar items behind gaps that are recorded and not fixed yet (see @gaps);
#   --gap I adds only gap I (0-based, repeatable), so each gap can be shown to be still open on its own.
# --fixed-by <later parser>: instead of counting, look for one case the source misses and the later
#   parser catches — proof that this harness sees what a real fix changed. Exit 1 when found.
# --superset-of <earlier parser>: instead of asking bash, require that every line the earlier parser
#   prints for a generated command is printed by the source too — the gate never sees less than it did.
#   For the merge gate a line today that denies the command outright covers every earlier line.
#   With --judge, bash decides each case where a line was lost: it is a counterexample only when bash ran
#   something the source does not report — the same test as without --superset-of, on those cases, so
#   this is a listing tool, not a further check. The rest are counted and shown apart: lines only the
#   earlier parser printed, while the source still covers everything bash ran.
# Exit: 0 no counterexample, 1 counterexamples (printed), 2 the harness could not judge
#       (the parser did not compile, a tool is missing, or too few cases reached bash's payload).
use strict; use warnings;
use File::Temp qw(tempdir);
use Getopt::Long;
use List::Util qw(min);
use POSIX ();

my ($kind, $source, $seed, $n, $min_ex, $show, $gaps, $fixed_by, $superset, $chars, $judge, @gap_ids) = ('', '', 20261111, 400, 0, 5, 0, '', '', 0, 0);
GetOptions('kind=s' => \$kind, 'source=s' => \$source, 'seed=i' => \$seed, 'n=i' => \$n,
           'min-exercised=i' => \$min_ex, 'show=i' => \$show, 'known-gaps' => \$gaps,
           'gap=i' => \@gap_ids, 'fixed-by=s' => \$fixed_by, 'superset-of=s' => \$superset,
           'chars' => \$chars, 'judge' => \$judge) or exit 2;
$judge && !$superset and do { print STDERR "--judge goes with --superset-of\n"; exit 2 };
$kind =~ /^(ag|pmg)$/ or do { print STDERR "--kind must be ag or pmg\n"; exit 2 };
-f $source or do { print STDERR "no such source: $source\n"; exit 2 };
$fixed_by && $superset and do { print STDERR "--fixed-by and --superset-of do not combine\n"; exit 2 };
$fixed_by ||= $superset;   # the second parser, either way
!$fixed_by || -f $fixed_by or do { print STDERR "no such source: $fixed_by\n"; exit 2 };

# ---- the parser under test: the text the hook hands to perl ----
sub parser_text {
  my ($file) = @_;
  open my $sf, '<', $file or do { print STDERR "cannot read $file\n"; exit 2 };
  my @lines = <$sf>; close $sf;
  my $text = '';
  if ($file =~ /\.sh$/) {
    my $in = 0;
    for (@lines) {
      if (!$in) { $in = 1 if /<<'PERL'/; next; }
      last if /^\s*PERL\s*$/;
      $text .= $_;
    }
  } else {
    $text = join '', @lines;
  }
  length $text or do { print STDERR "no parser found in $file\n"; exit 2 };
  return $text;
}
my $var = $kind eq 'ag' ? 'AG_CMD' : 'PMG_CMD';
# Run it the way the hook does — `perl -e "$parser"` with the command in the environment, stderr
# dropped — not compiled into this process: wrapped in a sub, a named sub inside an older parser
# loses sight of the lexicals around it and the parser silently reads nothing.
sub parse {
  my ($text, $cmd) = @_;
  local $ENV{$var} = $cmd;
  my $pid = open(my $ph, '-|') // die "fork: $!";
  # alarm survives exec: a parser that never ends is killed, and that is the harness unable to judge
  # (exit 2), never a counterexample — its empty output would otherwise read as "missed everything"
  if (!$pid) { open STDERR, '>', '/dev/null'; alarm 10; { exec $^X, '-e', $text; } POSIX::_exit(127); }
  local $/; my $out = <$ph> // ''; close $ph;
  if (($? & 127) == 14) { print STDERR "a parser did not finish within 10 s on: " . oneline($cmd) . "\n"; exit 2; }
  return $out;
}
my @texts = (parser_text($source), $fixed_by ? parser_text($fixed_by) : ());
for my $t (@texts) {
  my $probe = $kind eq 'ag' ? 'openspec archive probe' : 'gh pr merge 1 --repo o/r';
  parse($t, $probe) =~ /\S/ or do { print STDERR "a parser reports nothing for [$probe]: not one this harness can drive\n"; exit 2 };
}

# ---- the oracle: bash with stub commands ----
sub which { my ($t) = @_; for (split /:/, $ENV{PATH} // '') { return "$_/$t" if -x "$_/$t" && !-d "$_/$t" } return }
my $bash = which('bash') or do { print STDERR "bash not found\n"; exit 2 };
my $base = tempdir('tokdiff.XXXXXX', TMPDIR => 1, CLEANUP => 1);
my ($stub, $work, $log) = ("$base/bin", "$base/work", "$base/calls");
mkdir $_ or die "mkdir $_: $!" for $stub, $work;
for my $t (qw(cat env)) { my $p = which($t) or do { print STDERR "$t not found\n"; exit 2 }; symlink $p, "$stub/$t" or die; }
symlink $bash, "$stub/bash" or die;
my %stubs = (
  openspec => <<'SH',
#!/bin/sh
[ "$1" = archive ] || exit 0
shift
for a in "$@"; do case $a in -*) ;; *) printf '%s\n' "$a" >> "$LOG"; exit 0 ;; esac; done
SH
  gh => <<'SH',
#!/bin/sh
[ "$1" = pr ] && [ "$2" = merge ] || exit 0
shift 2
repo=- num=
while [ $# -gt 0 ]; do
  case $1 in
    --repo|-R) repo=${2-}; [ $# -gt 1 ] && shift ;;
    --repo=*) repo=${1#--repo=} ;;
    ''|*[!0-9]*) ;;
    *) [ -n "$num" ] || num=$1 ;;
  esac
  shift
done
[ -n "$num" ] && printf '%s %s\n' "$repo" "$num" >> "$LOG"
exit 0
SH
);
for my $s (keys %stubs) { open my $f, '>', "$stub/$s" or die; print $f $stubs{$s}; close $f; chmod 0755, "$stub/$s"; }

sub run_bash {
  my ($cmd) = @_;
  unlink $log;
  my $pid = fork // die "fork: $!";
  if (!$pid) {
    setpgrp(0, 0);   # its own process group, so what it leaves running can be waited for below
    chdir $work or POSIX::_exit(127);
    open STDIN, '<', '/dev/null'; open STDOUT, '>', '/dev/null'; open STDERR, '>', '/dev/null';
    %ENV = (PATH => $stub, LOG => $log, HOME => $work, LC_ALL => 'C');
    alarm 5;   # survives exec: a command that hangs is killed, and counts as running nothing
    { exec $bash, '--noprofile', '--norc', '-c', $cmd; }
    POSIX::_exit(127);
  }
  waitpid $pid, 0;
  # bash can return before a process it started has finished (a heredoc body expanded in a pipeline):
  # its call would land in the next case's log. Wait for the group to empty, up to 3 s, then end it.
  my $until = time + 3;
  select undef, undef, undef, 0.02 while kill(0, -$pid) && time < $until;
  kill 'KILL', -$pid;
  my @calls;
  # a name with a newline in it would log as two lines, one of them empty: an empty line is not a call
  if (open my $f, '<', $log) { @calls = grep { length } map { chomp; $_ } <$f>; close $f; }
  return @calls;
}

# ---- the grammar ----
srand $seed;
sub pick { $_[int rand @_] }
my @names = qw(foo bar);
# A merge's number or repo with a substitution in it: bash merges what it expands to, which the hook
# cannot know, so the gate must report it as unreadable (`-`), never as its literal part.
my @nums = (3, 7, 12, '3$(echo 0)', '1${x:-2}', '"7$(true)"');
my @repos = ('o/r', 'o/r$(echo x)', '"o/r$(true)"', '`echo o`/r', 'o/${x:-r}');
sub payload {
  return 'openspec archive ' . pick('', '--yes ') . pick(@names) if $kind eq 'ag';
  my $r = rand();
  return 'gh pr merge ' . pick(3, 7, 12) . ' --repo o/r' if $r < 0.75;
  # an unquoted substitution that expands to nothing is no word at all: bash still runs the merge
  return pick('gh $(true) pr merge ', 'gh pr $(true) merge ', 'gh pr merge $(true) ') . pick(3, 7, 12) . ' --repo o/r' if $r < 0.8;
  return 'gh pr merge ' . pick(@nums) . ' --repo ' . pick(@repos);
}
# Each wrapper puts a command where bash still runs it; undef when the inner text cannot go there.
my @wrap = (
  sub { $_[0] },
  sub { "echo \"x \$($_[0]) y\"" },
  sub { "echo \$($_[0])" },
  sub { $_[0] =~ /`/ ? undef : "echo `$_[0]`" },
  sub { $_[0] =~ /`/ ? undef : "echo \"done: `$_[0]`\"" },
  sub { my $d = pick(qw(EOF END TXT)); $_[0] =~ /^$d$/m ? undef : "cat <<$d\n\$($_[0])\n$d" },
  sub { my $d = pick(qw(EOF END TXT)); $_[0] =~ /^$d$/m ? undef : "cat > n.md <<$d\nnote \$(true\n$_[0])\n$d" },
  sub { $_[0] =~ /'/ ? undef : "bash -c '$_[0]'" },
  sub { $_[0] =~ /'/ ? undef : "eval '$_[0]'" },
  sub { "if true; then\n$_[0]\nfi" },
  sub { "{\n$_[0]\n}" },
  sub { "true && $_[0]" },
  sub { "(\n$_[0]\n)" },
  sub { $_[0] =~ /\n/ ? undef : "env X=1 $_[0]" },
  sub { $_[0] =~ /\n/ ? undef : "$_[0] | cat" },
  sub { $_[0] =~ /\n/ ? undef : "echo `# don't`; $_[0]" },    # inside backticks a # comment ends at the backtick
  sub { $_[0] =~ /\n/ ? undef : "echo \${x:- #}; $_[0]" },     # inside ${…} a # is text, not a comment
  sub { $_[0] =~ /\n/ ? undef : "echo \${x:-'a b' #}; $_[0]" }, # …with a quoted string before it
  sub { $_[0] =~ /^(\w+)( [^\n]*)$/ ? "echo \${x:- #}; '$1'$2" : undef },   # …and the command word quoted
  sub { $_[0] =~ /[`\n]/ ? undef : "echo \${x:-`$_[0]`}" },    # a command inside ${…} still runs
  sub { $_[0] =~ /\n/ ? undef : "echo \${x:-'}'}; $_[0]" },   # a quoted } does not close it
  sub { $_[0] =~ /\n/ ? undef : "echo \${x:-{}; $_[0]; echo }" },   # a bare { inside ${…} opens nothing
  sub { $_[0] =~ /\n/ ? undef : "echo v\$(echo 1)#L10 && $_[0]" },  # a # glued to a substitution is text
  sub { $_[0] =~ /[`\n]/ ? undef : "echo `true`#; $_[0]" },
  sub { $_[0] =~ /\n/ ? undef : "echo a\x0b# ; $_[0]" },            # \v is not a blank to bash
  # what the lexer reads and the two older scanners did not (W5-8): the first three were the gaps
  # recorded with #57; the others came from --chars
  sub { $_[0] =~ /["\n]/ ? undef : "echo \"x \$(echo \"a\"; $_[0]) y\"" },   # "…" inside $( … ) inside "…"
  sub { "true && \\\n$_[0]" },                                       # \⏎ joins the lines
  sub { "echo `'-#`\n$_[0]" },                                       # a backtick closes before its quote does
  sub { $_[0] =~ /\n/ ? undef : $_[0] . pick('>/dev/null', '<<<x', ' 2>&1') },   # a redirection glued on
  sub { $_[0] =~ /\n/ ? undef : pick('>/dev/null ', '2>&1 ', '<<<x ') . $_[0] },   # …or before the command
  sub { "echo \$(( \$($_[0]) 0 ))" },                                # $( … ) inside arithmetic runs
  sub { "echo \$[ \$($_[0]) 0 ]" },                                  # …inside $[ … ] too
  sub { $_[0] =~ /['`\n]/ ? undef : "echo \$(( '`$_[0]`' ))" },      # …and a backtick inside its '…'
  sub { "echo \$[1<<2]\n$_[0]" },                                   # $[ … ] is arithmetic: << is a shift
  sub { $_[0] =~ /\n/ ? undef : "echo a\\ #; $_[0]" },               # a # after an escaped blank is in the word
  sub { $_[0] =~ /\n/ ? undef : "echo \$((true); $_[0])" },          # $(( not closed by )): a subshell
  sub { $_[0] =~ /\n/ ? undef : "\$(true) $_[0]" },                  # a word that expands to nothing is gone
  sub { "cat <<NEVER\n\$($_[0])" },                                 # a heredoc whose delimiter never comes
  # a quote on a line bash drops, never closed. Not under --chars: random text after it can close the
  # quote, and that is gap 0 (the parser cannot know the line is dropped)
  sub { my $q = pick("'", '"'); $chars || index($_[0], $q) >= 0 ? undef : "a=(-( $q\n$_[0]" },
  sub { $_[0] =~ /['`]/ ? undef : "echo \$((\n(\necho `'`\n$_[0]\n); :))" },   # an unclosed ' makes $(( a $( (
  sub { my $d = pick(qw(EOF END)); $_[0] =~ /^$d$/m ? undef : "cat <<\\\n$d\n\$($_[0])\n$d" },   # <<\⏎EOF is <<EOF
);
# Text before the command that once made a parser lose the lines after it (#48, #51), with the line
# that closes what an older parser took for a heredoc.
my @noise = (
  ['cat <<< hello', 'hello'], ['cat <<<EOF', 'EOF'], ['echo "<<EOF"', 'EOF'], ["echo 'x <<EOF'", 'EOF'],
  ['echo $((1<<2))', '2'], ["echo \$'it\\'s'", undef], ["# don't", undef],
  ["cat > m.md <<'EOF'\nit's\nEOF", undef], ["echo \"a 'b\"", undef], ["echo 'one\ntwo'", undef],
  ["x=\$(cat <<EOF\ntext\nEOF\n)", undef], ["cat <<EOF \\\n&& true\nbody\nEOF", undef],
  # from the "Not covered" list of #48, the items both gates now handle: two heredocs opened on one
  # line, parentheses inside $(( … )), $'…' and backticks inside double quotes
  ["cat <<A <<B\nx\nA\ny\nB", undef], ['echo $(( (1) + 2 ))', undef], ["echo \"\$'x' `true`\"", undef],
  ['echo "($(( 1<<2 )))"', undef],
  # the gaps recorded with #57, read by the lexer since W5-8
  ["x=\$(cat <<EOF\ntext\nEOF)", 'EOF'],   # a heredoc closed by EOF) inside $( … )
  ["cat <<'E'\"F\"\nit's\nEF", undef],    # a delimiter written with mixed quotes
  ['((x=1<<2))', undef],                   # (( … )) is arithmetic: << is a shift
);
# Gaps the gates still have. Recorded as findings and left out of the default grammar until they are
# fixed, so the suite guards everything else; --known-gaps / --gap I put them back, and the suite checks
# each one still finds counterexamples. An entry is a noise item, or a wrapper (a sub).
my @gaps = (
  # 0: a line bash rejects as a syntax error is dropped and the lines after it run (bash 3.2 and 5.3);
  # a heredoc opened on it was never one, so its "body" runs as commands. A parser cannot know which
  # lines bash rejects without bash's grammar. (A quote opened on such a line is covered: the text
  # after a quote that never closes is read as commands too.)
  ["a=(-( <<EOF", 'EOF'],
);
for (@gap_ids) { $_ >= 0 && $_ < @gaps or do { print STDERR "--gap $_: there are " . scalar(@gaps) . " gaps\n"; exit 2 } }
for my $g ($gaps ? @gaps : @gaps[@gap_ids]) { push @{ ref $g eq 'CODE' ? \@wrap : \@noise }, $g; }
# Shell punctuation for --chars, weighted toward what has broken a parser before; words and blanks
# keep enough of the output parseable for bash to run the command at all.
my @alpha = ("'", "'", '"', '"', '#', '# ', '\\', '<<', '<<-', '<<<', '$(', '(', ')', '$((', '))', '${',
             '}', '{', '`', ';', '&&', '|', "\n", "\n", ' ', ' ', ' ', 'x', 'EOF', "\$'", 'echo ', 'cat ',
             '-', '=', 'a=', ':');
sub chars { join '', map { pick(@alpha) } 1 .. 1 + int rand 7 }
sub gen {
  my $s = payload();
  for (1 .. 1 + int rand 2) { my $w = pick(@wrap)->($s); $s = $w if defined $w; }
  if ($chars) {   # random punctuation around the command, on its line or the lines next to it
    return join '', chars(), pick("\n", '; ', ' && ', "\n", ' '), $s, pick('', "\n", '; ', ' '), chars();
  }
  my (@pre, @post);
  for (1 .. int rand 3) { my $z = pick(@noise); push @pre, $z->[0]; push @post, $z->[1] if defined $z->[1]; }
  return join "\n", @pre, $s, @post;
}

# ---- run ----
sub missed {   # what bash ran (change names, or PR numbers) that this parser output does not report
  my ($out, @calls) = @_;
  my @seen = split /\n/, $out;
  my @m;
  for my $v (@calls) {
    if ($kind eq 'ag') { push @m, $v unless grep { $_ eq $v } @seen; }
    # read as pr-merge-gate reads it: `read -r repo num sha` (blanks run together), and a number that is
    # not all digits is a merge it cannot pin (`-`, denied). bash's call is `repo num`: the gate covers it
    # with that same repo and number (ready checks the PR that merges), with a `-` in either (denied), or
    # with a repo no GitHub repository can have (`o/r$`, `/r`: ready fails, denied). A well-formed repo or
    # number other than bash's is the gate checking one PR and letting another merge.
    else {
      my ($vr, $vn) = split ' ', $v;
      push @m, $v unless grep { my ($r, $num) = (split ' ')[0, 1]; $r //= ''; $num //= ''; $num = '-' unless $num =~ /^\d+$/;
                                $num eq '-' || $r eq '-' || $r !~ m{^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$} || ($num eq $vn && $r eq $vr) } @seen;
    }
  }
  return @m;
}
binmode STDOUT, ':utf8';
sub oneline { (my $s = $_[0]) =~ s/\n/\x{23ce}/g; return $s }
(my $flat = $source) =~ s{.*/}{};
my ($exercised, @bad, @loose) = (0);
for my $i (1 .. $n) {
  my $cmd = gen();
  if ($superset) {
    my $out = parse($texts[0], $cmd); my %now = map { $_ => 1 } split /\n/, $out;
    my @lost = grep { !$now{$_} } split /\n/, parse($texts[1], $cmd);
    # the merge gate denies the whole command on one line it cannot pin (a `-` for the repo, or a number
    # that is not all digits): with such a line today, no line of the earlier parser is lost
    @lost = () if $kind eq 'pmg' && grep { my ($r, $num) = (split ' ')[0, 1]; ($r // '-') eq '-' || ($num // '') !~ /^\d+$/ } keys %now;
    $exercised++;
    next unless @lost;
    my @m = $judge ? missed($out, run_bash($cmd)) : @lost;
    if (@m) { push @bad, [$i, $cmd, join(',', @m), join("\n", sort keys %now)]; }
    else { push @loose, [$i, $cmd, join(',', @lost), join("\n", sort keys %now)]; }
    next;
  }
  my @calls = run_bash($cmd);
  next unless @calls;
  $exercised++;
  my $out = parse($texts[0], $cmd);
  my @m = missed($out, @calls);
  next unless @m;
  if ($fixed_by) {
    next if missed(parse($texts[1], $cmd), @calls);   # the later parser misses it too: not this fix
    print "$kind $flat: case $i is missed here and caught by the fix: bash ran [@m]\n    " . oneline($cmd) . "\n";
    exit 1;
  }
  push @bad, [$i, $cmd, join(',', @m), $out];
}
if ($fixed_by && !$superset) { print "$kind $flat: no case in $n separates it from the fix ($exercised exercised)\n"; exit 0; }

print "$kind $flat: seed=$seed cases=$n exercised=$exercised counterexamples=" . scalar(@bad)
  . ($judge ? " earlier-only=" . scalar(@loose) : '') . "\n";
for my $b (@bad[0 .. min($show, scalar @bad) - 1]) {   # bounded: a slice past the end, aliased by for, grows @bad
  (my $o = $b->[3]) =~ s/\n/ | /g;
  print "  case $b->[0]: bash ran [$b->[2]], parser saw [$o]\n    " . oneline($b->[1]) . "\n";
}
for my $b (@loose[0 .. min($show, scalar @loose) - 1]) {
  (my $o = $b->[3]) =~ s/\n/ | /g;
  print "  earlier only, what bash ran still covered: case $b->[0]: lost [$b->[2]], parser saw [$o]\n    " . oneline($b->[1]) . "\n";
}
if ($exercised < $min_ex) { print STDERR "only $exercised cases reached the payload, expected at least $min_ex\n"; exit 2; }
exit(@bad ? 1 : 0);
