#!/usr/bin/env perl
# bare-negations.pl FILE...: print FILE:LINE:TEXT for each bare negated command inside a bats @test.
#
# bash's set -e ignores a command inverted with `!`, so `! cmd` in a bats test never fails it (#26).
# The repository form is `! cmd || false` (or `run ! cmd`). A negation counts as bare when `!` starts
# a command (at the start of a line, after ; & && || | ( or then/do/else, inside { }, in a case branch)
# and the and-or list it starts does not end in `|| false`. A negation in an if/elif/while/until
# condition is not bare. Strings, comments, heredocs, $( ), ${ } and [[ ]] are skipped.
# Only @test bodies are read: a helper function may end with the negation it returns.
#
# Exit status: 0 when nothing is found, 1 when something is, 2 when a file cannot be read or followed
# (an unterminated string or heredoc, or a closing word that does not match), so a misparse fails loudly.

use strict;
use warnings;

my $SEPARATOR = qr/^(?:;|&|&&|\|\||\|)$/;
my $TERMINATOR = qr/^(?:;|;;|;;&|;&|&)$/;

# lex(text, file): the top-level tokens as [type, text, line]; type is w (word), op or nl.
sub lex {
  my ($text, $file) = @_;
  my ($i, $n, $line) = (0, length $text, 1);
  my (@tok, @mode, @heredocs, $word, $wline);
  my $at = sub { substr($text, $i, $_[0] // 1) };
  my $add = sub { if (!defined $word) { $word = ''; $wline = $line } $word .= $_[0] };
  my $end_word = sub { push @tok, ['w', $word, $wline] if defined $word; undef $word };
  my $enter = sub { push @mode, { m => $_[0], depth => $_[1] // 0, line => $line } };
  my $read_heredoc_op = sub {
    my $start = $line;
    $i += 2;
    my $strip = $at->() eq '-' ? 1 : 0;
    $i += $strip;
    $i++ while $i < $n && $at->() =~ /[ \t]/;
    my $delim = '';
    while ($i < $n) {
      my $c = $at->();
      last if $c =~ /[\s;&|<>()]/;
      if ($c eq "'" || $c eq '"') {
        my $j = index($text, $c, $i + 1);
        die "$file:$start: unterminated quote in a heredoc delimiter\n" if $j < 0;
        $delim .= substr($text, $i + 1, $j - $i - 1);
        $i = $j + 1;
      } elsif ($c eq '\\') { $delim .= substr($text, $i + 1, 1); $i += 2 }
      else { $delim .= $c; $i++ }
    }
    die "$file:$start: a heredoc without a delimiter\n" if $delim eq '';
    push @heredocs, [$delim, $strip, $start];
  };
  my $read_heredoc_bodies = sub {
    while (my $h = shift @heredocs) {
      my ($delim, $strip, $start) = @$h;
      my $closed = 0;
      while ($i < $n && !$closed) {
        my $j = index($text, "\n", $i);
        my $body = substr($text, $i, ($j < 0 ? $n : $j) - $i);
        $body =~ s/^\t+// if $strip;
        $closed = $body eq $delim;
        if ($j < 0) { $i = $n } else { $i = $j + 1; $line++ }
      }
      die "$file:$start: unterminated heredoc (no line $delim)\n" unless $closed;
    }
  };
  # An opening of a nested part ($( ${ $(( $' ` quotes <( >( ), or 0.
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
  while ($i < $n) {
    my $c = $at->();
    if (@mode) {
      my $m = $mode[-1]{m};
      if ($c eq "\n") { $line++ }
      if ($m eq 'sq') { pop @mode if $c eq "'"; $i++; next }
      if ($c eq '\\' && $m ne 'arith') { $line++ if substr($text, $i + 1, 1) eq "\n"; $i += 2; next }
      if ($m eq 'dsq') { pop @mode if $c eq "'"; $i++; next }
      if ($m eq 'arith') {
        $mode[-1] = { %{ $mode[-1] }, depth => $mode[-1]{depth} + ($c eq '(') - ($c eq ')') };
        pop @mode if $mode[-1]{depth} == 0;
        $i++;
        next;
      }
      if (($m eq 'dq' && $c eq '"') || ($m eq 'brace' && $c eq '}') || ($m eq 'bt' && $c eq '`')) {
        pop @mode; $i++; next;
      }
      my $o = $opening->($m eq 'sub' || $m eq 'brace' || $m eq 'bt');
      if ($o && !($m eq 'dq' && $o->[0] eq 'dq')) { $i += $o->[1]; $enter->($o->[0], $o->[2]); next }
      if ($m eq 'sub') {
        my $prev = $i ? substr($text, $i - 1, 1) : "\n";
        if ($c eq '#' && $prev =~ /[\s;&|()]/) { $i++ while $i < $n && $at->() ne "\n"; next }
        if ($at->(2) eq '<<' && $at->(3) ne '<<<') { $read_heredoc_op->(); next }
        if ($c eq "\n") { $i++; $read_heredoc_bodies->(); next }
        if ($c eq '(' || $c eq ')') {
          $mode[-1] = { %{ $mode[-1] }, depth => $mode[-1]{depth} + ($c eq '(' ? 1 : -1) };
          pop @mode if $mode[-1]{depth} == 0;
        }
      }
      $i++;
      next;
    }
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
    if ($c eq '#' && !defined $word) { $i++ while $i < $n && $at->() ne "\n"; next }
    if ($at->(2) eq '((' && !defined $word) { $add->('S'); $i += 2; $enter->('arith', 2); next }
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
  if (@mode) {
    my %name = (sq => q{'...' string}, dq => q{"..." string}, dsq => q{$'...' string}, sub => q{$( )},
      arith => q{$(( ))}, brace => q{${ }}, bt => q{`...`});
    die "$file:$mode[-1]{line}: unterminated $name{$mode[-1]{m}}\n";
  }
  die "$file:$heredocs[0][2]: unterminated heredoc (no line $heredocs[0][0])\n" if @heredocs;
  return \@tok;
}

# ends_in_or_false(tokens, k): the and-or list that starts after token k ends in `|| false`.
sub ends_in_or_false {
  my ($tok, $k) = @_;
  my ($depth, @list) = (0);
  for my $j ($k + 1 .. $#$tok) {
    my ($t, $v) = @{ $tok->[$j] };
    if ($t eq 'op' && $v eq '(') { $depth++ }
    elsif ($t eq 'op' && $v eq ')') { last if $depth == 0; $depth-- }
    elsif ($depth == 0 && ($t eq 'nl' || ($t eq 'op' && $v =~ $TERMINATOR))) { last }
    push @list, [$t, $v];
  }
  return @list >= 2 && $list[-2][1] eq '||' && $list[-1][0] eq 'w' && $list[-1][1] eq 'false';
}

# bare_lines(tokens, file): the line numbers of the bare negations, in order.
sub bare_lines {
  my ($tok, $file) = @_;
  my (@ctx, @found, $pending_test);
  my $cmd = 1;
  my $close = sub {
    my ($v, $l, @want) = @_;
    my $top = $ctx[-1];
    return if $top && grep { $top->{t} eq $_ } @want;
    die "$file:$l: $v does not close " . ($top ? "the $top->{t} opened on line $top->{line}" : 'anything') . "\n";
  };
  my $retop = sub { $ctx[-1] = { %{ $ctx[-1] }, @_ } };
  for (my $k = 0; $k < @$tok; $k++) {
    my ($t, $v, $l) = @{ $tok->[$k] };
    my $top = $ctx[-1];
    if ($top && $top->{t} eq 'case' && $top->{stage} ne 'body') {
      if ($top->{stage} eq 'word') { $retop->(stage => 'pattern') if $t eq 'w' && $v eq 'in' }
      elsif ($t eq 'w' && $v eq 'esac') { pop @ctx; $cmd = 0 }
      elsif ($t eq 'op' && $v eq ')') { $retop->(stage => 'body'); $cmd = 1 }
      next;
    }
    if ($t eq 'nl' || ($t eq 'op' && $v =~ $SEPARATOR)) { $cmd = 1; next }
    if ($t eq 'op' && $v =~ /^;(?:;&?|&)$/) { $close->($v, $l, 'case'); $retop->(stage => 'pattern'); next }
    if ($t eq 'op' && $v eq '(') {
      if ($k < $#$tok && $tok->[$k + 1][1] eq ')') { $k++ } else { push @ctx, { t => 'subshell', line => $l } }
      $cmd = 1;
      next;
    }
    if ($t eq 'op' && $v eq ')') { $close->($v, $l, 'subshell'); pop @ctx; $cmd = 0; next }
    if (!$cmd) {
      if ($pending_test && $v eq '{') { push @ctx, { t => '@test', line => $l }; $pending_test = 0; $cmd = 1 }
      next;
    }
    if ($v eq '!') {
      my $in_test = grep { $_->{t} eq '@test' } @ctx;
      my $in_cond = grep { $_->{t} =~ /condition/ } @ctx;
      push @found, $l if $in_test && !$in_cond && !ends_in_or_false($tok, $k) && !(@found && $found[-1] == $l);
    } elsif ($v eq '{') { push @ctx, { t => 'group', line => $l } }
    elsif ($v eq '}') { $close->($v, $l, 'group', '@test'); pop @ctx; $cmd = 0 }
    elsif ($v eq 'if') { push @ctx, { t => 'if condition', line => $l } }
    elsif ($v eq 'then') { $close->($v, $l, 'if condition'); $retop->(t => 'if') }
    elsif ($v eq 'elif') { $close->($v, $l, 'if'); $retop->(t => 'if condition') }
    elsif ($v eq 'else') { $close->($v, $l, 'if') }
    elsif ($v eq 'fi') { $close->($v, $l, 'if'); pop @ctx; $cmd = 0 }
    elsif ($v eq 'while' || $v eq 'until') { push @ctx, { t => 'loop condition', line => $l } }
    elsif ($v eq 'for' || $v eq 'select') { push @ctx, { t => 'for', line => $l }; $cmd = 0 }
    elsif ($v eq 'do') { $close->($v, $l, 'loop condition', 'for'); $retop->(t => 'loop') }
    elsif ($v eq 'done') { $close->($v, $l, 'loop'); pop @ctx; $cmd = 0 }
    elsif ($v eq 'case') { push @ctx, { t => 'case', stage => 'word', line => $l }; $cmd = 0 }
    elsif ($v eq '[[') {
      $k++ while $k < $#$tok && $tok->[$k][1] ne ']]';
      die "$file:$l: [[ without ]]\n" unless $tok->[$k][1] eq ']]';
      $cmd = 0;
    } elsif ($v eq '@test') { $pending_test = 1; $cmd = 0 }
    elsif ($v ne 'time') { $cmd = 0 }
  }
  die "$file:$ctx[-1]{line}: the $ctx[-1]{t} opened here never closes\n" if @ctx;
  return @found;
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
