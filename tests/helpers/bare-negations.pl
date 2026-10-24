#!/usr/bin/env perl
# bare-negations.pl FILE...: print FILE:LINE:TEXT for each bare negated command in a bats file.
#
# bash's set -e ignores a command inverted with `!`, so `! cmd` in a bats test never fails it (#26).
# The repository form is `! cmd || false` (or `run ! cmd`). A negation counts as bare when `!` starts
# a command (at the start of a line, after ; & && || | ( or then/do/else, inside { }, in a case branch)
# and the and-or list it starts does not end in `|| false`, or runs in the background with &. It also
# counts as bare, even with `|| false`, inside a compound command whose status && || | or & ignores
# (`{ ! cmd || false; } || true`). A negation in an if/elif/while/until condition is not bare.
# The check is strict on purpose: `{ ! cmd; } || false` and `! cmd || { echo; false; }` do fail a
# test but are reported; write `! cmd || false`.
#
# @test bodies (also `name() { # @test`) and the setup/teardown hooks are read as tests. Other
# functions are read too, except that the last command of a function body may be a negation: the
# function returns it (`absent() { ! grep -q x "$1"; }`).
# Strings, comments, heredocs, $( ), ${ }, array values and [[ ]] are skipped.
#
# Exit status: 0 when nothing is found, 1 when something is, 2 when a file cannot be read or followed
# (an unterminated string or heredoc, or a closing word that does not match), so a misparse fails loudly.

use strict;
use warnings;

my $SEPARATOR = qr/^(?:;|&|&&|\|\||\|)$/;
my $TERMINATOR = qr/^(?:;|;;|;;&|;&|&)$/;
my $IGNORING = qr/^(?:&&|\|\||\||&)$/;
my $BOUNDARY = qr/[\s;&|()]/;
my %CLOSER = map { $_ => 1 } qw(then do else elif fi done esac });
my %HOOK = map { $_ => 1 } qw(setup teardown setup_file teardown_file);
my %OWNER = map { $_ => 1 } ('@test', 'function');
my %MODE_NAME = (sq => q{'...' string}, dq => q{"..." string}, dsq => q{$'...' string}, sub => q{$( )},
  arith => q{$(( ))}, brace => q{${ }}, bt => q{`...`});

# lex(text, file): the top-level tokens as [type, text, line]; type is w (word), op, nl or note
# (a `# @test` comment).
sub lex {
  my ($text, $file) = @_;
  my ($i, $n, $line) = (0, length $text, 1);
  my (@tok, @mode, @heredocs, $word, $wline);
  my $at = sub { substr($text, $i, $_[0] // 1) };
  my $prev = sub { $i ? substr($text, $i - 1, 1) : "\n" };
  my $add = sub { if (!defined $word) { $word = ''; $wline = $line } $word .= $_[0] };
  my $end_word = sub { push @tok, ['w', $word, $wline] if defined $word; undef $word };
  my $enter = sub { my ($m, $depth) = @_; push @mode, { m => $m, depth => $depth // 0, cases => 0, line => $line } };
  my $retop = sub { $mode[-1] = { %{ $mode[-1] }, @_ } };
  my $step_depth = sub {
    $retop->(depth => $mode[-1]{depth} + $_[0]);
    pop @mode if $mode[-1]{depth} == 0;
  };
  my $comment = sub {
    my $start = $i;
    $i++ while $i < $n && $at->() ne "\n";
    return substr($text, $start, $i - $start);
  };
  # A heredoc operator at i: its body starts after the next new line at the same nesting level.
  my $read_heredoc_op = sub {
    my $start = $line;
    $i += 2;
    my $strip = $at->() eq '-' ? 1 : 0;
    $i += $strip;
    $i++ while $i < $n && $at->() =~ /[ \t]/;
    my ($delim, $quoted) = ('', 0);
    while ($i < $n) {
      my $c = $at->();
      last if $c =~ /[\s;&|<>()]/;
      if ($c eq "'" || $c eq '"') {
        my $j = index($text, $c, $i + 1);
        die "$file:$start: unterminated quote in a heredoc delimiter\n" if $j < 0;
        $delim .= substr($text, $i + 1, $j - $i - 1);
        ($i, $quoted) = ($j + 1, 1);
      } elsif ($c eq '\\') { $delim .= substr($text, $i + 1, 1); ($i, $quoted) = ($i + 2, 1) }
      else { $delim .= $c; $i++ }
    }
    # <<"" and <<'' are valid: the body ends at an empty line.
    die "$file:$start: a heredoc without a delimiter\n" if $delim eq '' && !$quoted;
    push @heredocs, { delim => $delim, strip => $strip, line => $start, level => scalar @mode };
  };
  my $read_heredoc_bodies = sub {
    my $level = scalar @mode;
    my @here = grep { $_->{level} == $level } @heredocs;
    @heredocs = grep { $_->{level} != $level } @heredocs;
    for my $h (@here) {
      my $closed = 0;
      while ($i < $n && !$closed) {
        my $j = index($text, "\n", $i);
        my $body = substr($text, $i, ($j < 0 ? $n : $j) - $i);
        $body =~ s/^\t+// if $h->{strip};
        $closed = $body eq $h->{delim};
        if ($j < 0) { $i = $n } else { $i = $j + 1; $line++ }
      }
      die "$file:$h->{line}: unterminated heredoc (no line $h->{delim})\n" unless $closed;
    }
  };
  # The nested part that opens at i ($( ${ $(( $' ` quotes <( >( ) as [mode, length, depth], or 0.
  my $opening = sub {
    my ($code) = @_;
    return ['arith', 3, 2] if $at->(3) eq '$((';
    return ['sub', 2, 1] if $at->(2) eq '$(' || ($code && $at->(2) =~ /^[<>]\($/);
    return ['brace', 2] if $at->(2) eq '${';
    return ['dsq', 2] if $code && $at->(2) eq "\$'";
    return ['sq', 1] if $code && $at->() eq "'";
    return ['dq', 1] if $at->() eq '"';
    return ['bt', 1] if $at->() eq '`';
    return 0;
  };
  # One step of code inside $( ): comments, heredocs, case patterns and parentheses.
  my $nested_code = sub {
    my $c = $at->();
    my $start = $prev->() =~ $BOUNDARY;
    if ($c eq '#' && $start) { $comment->(); return }
    if ($start && $at->(2) eq '((') { $i += 2; $enter->('arith', 2); return }
    if ($start && substr($text, $i, 5) =~ /^(case|esac)(?=$BOUNDARY)/) {
      $retop->(cases => $mode[-1]{cases} + ($1 eq 'case' ? 1 : -1));
      $i += 4;
      return;
    }
    if ($at->(3) eq '<<<') { $i += 3; return }
    if ($at->(2) eq '<<') { $read_heredoc_op->(); return }
    if ($c eq "\n") { $i++; $read_heredoc_bodies->(); return }
    # The ) that ends a case pattern does not close the $( ).
    $step_depth->(1) if $c eq '(';
    $step_depth->(-1) if $c eq ')' && !($mode[-1]{cases} > 0 && $mode[-1]{depth} == 1);
    $i++;
  };
  # One character inside a nested part.
  my $nested = sub {
    my $c = $at->();
    my $m = $mode[-1]{m};
    $line++ if $c eq "\n";
    if ($m eq 'sq') { pop @mode if $c eq "'"; $i++; return }
    if ($c eq '\\' && $m ne 'arith') { $line++ if substr($text, $i + 1, 1) eq "\n"; $i += 2; return }
    if ($m eq 'dsq') { pop @mode if $c eq "'"; $i++; return }
    if ($m eq 'arith') { $step_depth->(($c eq '(') - ($c eq ')')); $i++; return }
    if (($m eq 'dq' && $c eq '"') || ($m eq 'brace' && $c eq '}') || ($m eq 'bt' && $c eq '`')) {
      pop @mode; $i++; return;
    }
    # bash reads quotes inside ${ } even within "...": "${x:-it's}" is an unterminated string.
    my $o = $opening->($m eq 'sub' || $m eq 'bt' || $m eq 'brace');
    if ($o && !($m eq 'dq' && $o->[0] eq 'dq')) { $i += $o->[1]; $enter->($o->[0], $o->[2]); return }
    if ($m eq 'sub') { $nested_code->(); return }
    $i++;
  };
  while ($i < $n) {
    if (@mode) { $nested->(); next }
    my $c = $at->();
    if ($c eq ' ' || $c eq "\t") { $end_word->(); $i++; next }
    if ($c eq "\n") {
      $end_word->();
      push @tok, ['nl', "\n", $line] unless @tok && $tok[-1][0] eq 'op' && $tok[-1][1] =~ /^(?:&&|\|\||\|)$/;
      $line++; $i++;
      $read_heredoc_bodies->();
      next;
    }
    if ($c eq '\\') {
      if (substr($text, $i + 1, 1) eq "\n") { $line++ } else { $add->('S') }
      $i += 2;
      next;
    }
    if ($c eq '#' && !defined $word) {
      my $l = $line;
      push @tok, ['note', '@test', $l] if $comment->() =~ /^#[ \t]*\@test[ \t]*$/;
      next;
    }
    if ($at->(2) eq '((' && !defined $word) { $add->('S'); $i += 2; $enter->('arith', 2); next }
    # name=( values ): the values are words, not a subshell.
    if ($c eq '(' && defined $word && $word =~ /=$/) { $add->('S'); $i++; $enter->('sub', 1); next }
    my $o = $opening->(1);
    if ($o) { $add->('S'); $i += $o->[1]; $enter->($o->[0], $o->[2]); next }
    if ($at->(3) eq '<<<') { $add->('<<<'); $i += 3; next }
    if ($at->(2) eq '<<') { $end_word->(); $read_heredoc_op->(); next }
    if (($c eq '&' && ((defined $word && $word =~ /[<>]$/) || substr($text, $i + 1, 1) eq '>'))
        || ($c eq '|' && defined $word && $word =~ />$/)) {
      $add->($c); $i++; next;
    }
    if ($c =~ /[;&|()]/) {
      $end_word->();
      my ($op) = substr($text, $i) =~ /^(;;&|;;|;&|&&|\|\||\|&|[;&|()])/;
      push @tok, ['op', $op eq '|&' ? '|' : $op, $line];
      $i += length $op;
      next;
    }
    $add->($c); $i++;
  }
  $end_word->();
  die "$file:$mode[-1]{line}: unterminated $MODE_NAME{$mode[-1]{m}}\n" if @mode;
  die "$file:$heredocs[0]{line}: unterminated heredoc (no line $heredocs[0]{delim})\n" if @heredocs;
  return \@tok;
}

# list_after(tokens, k): the and-or list that starts after token k, as (index of the token that
# ends it, the tokens of the list).
sub list_after {
  my ($tok, $k) = @_;
  my ($depth, @list) = (0);
  my $j = $k + 1;
  for (; $j <= $#$tok; $j++) {
    my ($t, $v) = @{ $tok->[$j] };
    next if $t eq 'note';
    my $open = ($t eq 'op' && $v eq '(') || ($t eq 'w' && $v eq '{');
    my $shut = ($t eq 'op' && $v eq ')') || ($t eq 'w' && $v eq '}');
    if ($open) { $depth++ }
    elsif ($shut) { last if $depth == 0; $depth-- }
    elsif ($depth == 0 && ($t eq 'nl' || ($t eq 'op' && $v =~ $TERMINATOR))) { last }
    push @list, [$t, $v];
  }
  return ($j, \@list);
}

# counts(tokens, end, list): the list ends in `|| false` and does not run in the background.
sub counts {
  my ($tok, $end, $list) = @_;
  return 0 if $end <= $#$tok && $tok->[$end][0] eq 'op' && $tok->[$end][1] eq '&';
  return @$list >= 2 && $list->[-2][1] eq '||' && $list->[-1][0] eq 'w' && $list->[-1][1] eq 'false';
}

# last_in_body(tokens, end, owner): only separators lie between token end and the close of owner.
sub last_in_body {
  my ($tok, $end, $owner) = @_;
  my $shut = $owner->{paren} ? ')' : '}';
  for my $j ($end .. $#$tok) {
    my ($t, $v) = @{ $tok->[$j] };
    next if $t eq 'nl' || $t eq 'note' || ($t eq 'op' && $v eq ';');
    return $v eq $shut;
  }
  return 0;
}

# status_ignored(tokens, k): the compound command closed at token k is followed by && || | or &
# (after its redirections), so a failure inside it does not fail the test.
sub status_ignored {
  my ($tok, $k) = @_;
  for my $j ($k + 1 .. $#$tok) {
    my ($t, $v) = @{ $tok->[$j] };
    return $v =~ $IGNORING if $t eq 'op';
    return 0 if $t eq 'nl' || $CLOSER{$v};
  }
  return 0;
}

# bare_lines(tokens, file): the line numbers of the bare negations, in order.
sub bare_lines {
  my ($tok, $file) = @_;
  my (@ctx, %found, $pending);
  my $cmd = 1;    # 1: a command may start here; 2: only a closing word may (after a compound); 0: neither
  my $fail = sub {
    my ($v, $l) = @_;
    my $top = $ctx[-1];
    die "$file:$l: $v does not close " . ($top ? "the $top->{t} opened on line $top->{line}" : 'anything') . "\n";
  };
  my $close = sub { my ($v, $l, @want) = @_; my $top = $ctx[-1]; $fail->($v, $l) unless $top && grep { $top->{t} eq $_ } @want };
  my $retop = sub { $ctx[-1] = { %{ $ctx[-1] }, @_ } };
  my $open = sub { my ($t, $l, @rest) = @_; push @ctx, { t => $t, line => $l, ok => [], @rest } };
  # Close the compound at token k; the negations it let through become bare when its status is ignored.
  my $pop = sub {
    my ($k) = @_;
    my $done = pop @ctx;
    $cmd = 2;
    return if $OWNER{ $done->{t} };
    if (status_ignored($tok, $k)) { $found{$_} = 1 for @{ $done->{ok} } }
    elsif (@ctx && !$OWNER{ $ctx[-1]{t} }) { $retop->(ok => [@{ $ctx[-1]{ok} }, @{ $done->{ok} }]) }
  };
  # A closing } or ) at token k: it must close a group, a subshell, or a test or function body.
  my $shut = sub {
    my ($v, $l, $k) = @_;
    my $top = $ctx[-1];
    my $paren = $v eq ')';
    my $fits = $top && ($top->{t} eq ($paren ? 'subshell' : 'group') || ($OWNER{ $top->{t} } && !$top->{paren} == !$paren));
    $fail->($v, $l) unless $fits;
    $pop->($k);
  };
  my $negation = sub {
    my ($k, $l) = @_;
    my ($o) = grep { $OWNER{ $ctx[$_]{t} } } reverse 0 .. $#ctx;
    return unless defined $o;
    return if grep { $_->{t} =~ /condition/ } @ctx[$o + 1 .. $#ctx];
    my ($end, $list) = list_after($tok, $k);
    my $owner = $ctx[$o];
    my $ok = counts($tok, $end, $list)
      || ($owner->{t} eq 'function' && $o == $#ctx && last_in_body($tok, $end, $owner));
    if (!$ok) { $found{$l} = 1 }
    elsif ($o < $#ctx) { $retop->(ok => [@{ $ctx[-1]{ok} }, $l]) }
  };
  for (my $k = 0; $k < @$tok; $k++) {
    my ($t, $v, $l) = @{ $tok->[$k] };
    my $top = $ctx[-1];
    if ($t eq 'note') {
      # name() { # @test: bats runs the function as a test.
      $retop->(t => '@test') if $top && $top->{t} eq 'function' && $top->{line} == $l;
      next;
    }
    if ($pending) {
      # The body of a test or function: { or ( after its name, maybe on the next line.
      if (($t eq 'w' && $v eq '{') || ($t eq 'op' && $v eq '(')) {
        $open->($pending, $l, paren => $v eq '(');
        ($pending, $cmd) = (undef, 1);
        next;
      }
      next if $t eq 'nl' || ($pending eq '@test' && $t eq 'w');
      $pending = undef;
    }
    if ($top && $top->{t} eq 'case' && $top->{stage} ne 'body') {
      if ($top->{stage} eq 'word') { $retop->(stage => 'pattern') if $t eq 'w' && $v eq 'in' }
      elsif ($t eq 'w' && $v eq 'esac') { $pop->($k) }
      elsif ($t eq 'op' && $v eq ')') { $retop->(stage => 'body'); $cmd = 1 }
      next;
    }
    if ($t eq 'nl' || ($t eq 'op' && $v =~ $SEPARATOR)) { $cmd = 1; next }
    if ($t eq 'op' && $v =~ /^;(?:;&?|&)$/) { $close->($v, $l, 'case'); $retop->(stage => 'pattern'); next }
    if ($t eq 'op' && $v eq '(') { $open->('subshell', $l); $cmd = 1; next }
    if ($t eq 'op' && $v eq ')') { $shut->($v, $l, $k); next }
    if (!$cmd || ($cmd == 2 && !$CLOSER{$v})) { $cmd = 0; next }
    if ($v eq '!') { $negation->($k, $l) }
    elsif ($v eq '{') { $open->('group', $l) }
    elsif ($v eq '}') { $shut->($v, $l, $k) }
    elsif ($v eq 'if') { $open->('if condition', $l) }
    elsif ($v eq 'then') { $close->($v, $l, 'if condition'); $retop->(t => 'if'); $cmd = 1 }
    elsif ($v eq 'elif') { $close->($v, $l, 'if'); $retop->(t => 'if condition'); $cmd = 1 }
    elsif ($v eq 'else') { $close->($v, $l, 'if'); $cmd = 1 }
    elsif ($v eq 'fi') { $close->($v, $l, 'if'); $pop->($k) }
    elsif ($v eq 'while' || $v eq 'until') { $open->('loop condition', $l) }
    elsif ($v eq 'for' || $v eq 'select') { $open->('for', $l); $cmd = 0 }
    elsif ($v eq 'do') { $close->($v, $l, 'loop condition', 'for'); $retop->(t => 'loop'); $cmd = 1 }
    elsif ($v eq 'done') { $close->($v, $l, 'loop'); $pop->($k) }
    elsif ($v eq 'esac') { $close->($v, $l, 'case'); $pop->($k) }
    elsif ($v eq 'case') { $open->('case', $l, stage => 'word'); $cmd = 0 }
    elsif ($v eq '[[') {
      $k++ while $k < $#$tok && $tok->[$k][1] ne ']]';
      die "$file:$l: [[ without ]]\n" unless $tok->[$k][1] eq ']]';
      $cmd = 2;
    } elsif ($v eq '@test') { ($pending, $cmd) = ('@test', 0) }
    elsif ($v eq 'function' || ($k + 2 <= $#$tok && $tok->[$k + 1][1] eq '(' && $tok->[$k + 2][1] eq ')')) {
      # A function definition: `name() {`, `function name {` or `function name() {`.
      $k++ if $v eq 'function';
      my $name = $tok->[$k][1] // '';
      $k += 2 if $k + 2 <= $#$tok && $tok->[$k + 1][1] eq '(' && $tok->[$k + 2][1] eq ')';
      ($pending, $cmd) = ($HOOK{$name} ? '@test' : 'function', 0);
    } elsif ($v ne 'time') { $cmd = 0 }
  }
  die "$file:$ctx[-1]{line}: the $ctx[-1]{t} opened here never closes\n" if @ctx;
  return sort { $a <=> $b } keys %found;
}

my $status = 0;
for my $file (@ARGV) {
  my @lines = eval {
    open my $fh, '<', $file or die "$file: cannot read: $!\n";
    my $text = do { local $/; <$fh> };
    close $fh;
    my @text = split /\n/, $text, -1;
    map { "$file:$_:$text[$_ - 1]" } bare_lines(lex($text, $file), $file);
  };
  if ($@) { print STDERR $@; $status = 2; next }
  print "$_\n" for @lines;
  $status = 1 if @lines && $status == 0;
}
exit $status;
