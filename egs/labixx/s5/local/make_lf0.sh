#!/bin/bash 

# Copyright 2016  Huanshi LTD (Author: Liushouda)
# Apache 2.0

# Begin configuration section.
nj=8
cmd=run.pl
compress=false
sample_frequency=16000
# End configuration section.

echo "$0 $@"  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;

if [ $# != 3 ]; then
   echo "usage: make_str.sh [options] <data-dir> <log-dir> <path-to-mfccdir>";
   echo "options: "
   echo "  --lf0-config <config-file>                     # config passed to compute-kaldi-lf0-feats "
   echo "  --nj <nj>                                        # number of parallel jobs"
   echo "  --cmd (utils/run.pl|utils/queue.pl <queue opts>) # how to run jobs."
   exit 1;
fi

data=$1
logdir=$2
lf0dir=$3


# make $lf0dir an absolute pathname.
lf0dir=`perl -e '($dir,$pwd)= @ARGV; if($dir!~m:^/:) { $dir = "$pwd/$dir"; } print $dir; ' $lf0dir ${PWD}`


# use "name" as part of name of the archive.
name=`basename $data`

mkdir -p $lf0dir || exit 1;
mkdir -p $logdir || exit 1;

scp=$data/wav.scp

required="$scp"

for f in $required; do
  if [ ! -f $f ]; then
    echo "make_lf0.sh: no such file $f"
    exit 1;
  fi
done
utils/validate_data_dir.sh --no-text --no-feats $data || exit 1;

for n in $(seq $nj); do
  # the next command does nothing unless $lf0dir/storage/ exists, see
  # utils/create_data_link.pl for more info.
  utils/create_data_link.pl $lf0dir/raw_lf0_$name.$n.ark  
done

# note: in general, the double-parenthesis construct in bash "((" is "C-style
# syntax" where we can get rid of the $ for variable names, and omit spaces.
# The "for" loop in this style is a special construct.

if [ -f $data/segments ]; then
    echo "$0 [info]: segments file exists: using that."
    split_segments=""
    for n in $(seq $nj); do
      split_segments="$split_segments $logdir/segments.$n"
    done

    utils/split_scp.pl $data/segments $split_segments || exit 1;
    rm $logdir/.error 2>/dev/null

    in_feats="ark,s,cs:extract-segments scp,p:$scp $logdir/segments.JOB ark:- |"
else
    echo "$0: [info]: no segments file exists: assuming wav.scp indexed by utterance."
    split_scps=""
    for n in $(seq $nj); do
      split_scps="$split_scps $logdir/wav_${name}.$n.scp"
    done

    utils/split_scp.pl $scp $split_scps || exit 1;

    in_feats="scp,p:$logdir/wav_${name}.JOB.scp"
fi

$cmd JOB=1:$nj $logdir/make_lf0.JOB.log \
    copy-feats --compress=$compress "ark,s,cs:compute-lf0-feats.sh --srate $sample_frequency --job JOB $in_feats ark:- |" \
      ark,scp:$lf0dir/raw_lf0_$name.JOB.ark,$lf0dir/raw_lf0_$name.JOB.scp \
     || exit 1;


if [ -f $logdir/.error.$name ]; then
  echo "Error producing lf0 features for $name:"
  tail $logdir/make_lf0.*.log
  exit 1;
fi

# concatenate the .scp files together.
for n in $(seq $nj); do
  cat $lf0dir/raw_lf0_$name.$n.scp || exit 1;
done > $data/lf0_feats.scp

rm $logdir/wav_${name}.*.scp  $logdir/segments.* 2>/dev/null

nf=`cat $data/lf0_feats.scp | wc -l` 
nu=`cat $data/utt2spk | wc -l`
if [ $nf -ne $nu ]; then
  echo "It seems not all of the feature files were successfully processed ($nf != $nu);"
  echo "consider using utils/fix_data_dir.sh $data"
fi

if [ $nf -lt $[$nu - ($nu/20)] ]; then
  echo "Less than 95% of the features were successfully generated.  Probably a serious error."
  exit 1;
fi

echo "Succeeded creating lf0 features for $name"
