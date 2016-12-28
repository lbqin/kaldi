#!/usr/bin/env perl

# Copyright 2012  Johns Hopkins University (author: Daniel Povey)

# Generate a topology file.  This allows control of the number of states in the
# non-silence HMMs, and in the silence HMMs.

if (@ARGV != 4) {
  print STDERR "Usage: utils/gen_topo.pl <num-nonsilence-states> <num-silence-states> <colon-separated-nonsilence-phones> <colon-separated-silence-phones>\n";
  print STDERR "e.g.:  utils/gen_topo.pl 3 5 4:5:6:7:8:9:10 1:2:3\n";
  exit (1);
}

($num_nonsil_states, $num_sil_states, $nonsil_phones, $sil_phones) = @ARGV;

( $num_nonsil_states >= 1 && $num_nonsil_states <= 100 ) ||
  die "Unexpected number of nonsilence-model states $num_nonsil_states\n";
(( $num_sil_states == 1 || $num_sil_states >= 3) && $num_sil_states <= 100 ) ||
  die "Unexpected number of silence-model states $num_sil_states\n";

$nonsil_phones =~ s/:/ /g;
$sil_phones =~ s/:/ /g;
$nonsil_phones =~ m/^\d[ \d]+$/ || die "$0: bad arguments @ARGV\n";
$sil_phones =~ m/^\d[ \d]*$/ || die "$0: bad arguments @ARGV\n";

print "<Topology>\n";
print "<TopologyEntry>\n";
print "<ForPhones>\n";
print "$nonsil_phones\n";
print "</ForPhones>\n";
for ($state = 0; $state < $num_nonsil_states; $state++) {
  $statep1 = $state+1;
  print "<State> $state <PdfClass> $state <Transition> $state 0.75 <Transition> $statep1 0.25 </State>\n";
}
print "<State> $num_nonsil_states </State>\n"; # non-emitting final state.
print "</TopologyEntry>\n";

# use the same topology as non silence phone

print "<TopologyEntry>\n";
print "<ForPhones>\n";
print "$sil_phones\n";
print "</ForPhones>\n";
for ($state = 0; $state < $num_sil_states; $state++) {
  $statep1 = $state+1;
  print "<State> $state <PdfClass> $state <Transition> $state 0.75 <Transition> $statep1 0.25 </State>\n";
}
print "<State> $num_sil_states </State>\n"; # non-emitting final state.
print "</TopologyEntry>\n";

print "</Topology>\n";
