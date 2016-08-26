#!/bin/sh
# Generates marytts mgc from a list of wav file.

export tooldir=$KALDI_ROOT/tools/SPTK/bin

help_message="Usage: ./compute-mgc-feats.sh [options] scp:<in.scp> <wspecifier>\n\tcf. top of file for list of options."

AWK=gawk
PERL=/usr/bin/perl
BC=/usr/bin/bc
TCLSH=/usr/bin/tclsh
WC=/usr/bin/wc

# SPTK commands
X2X=$tooldir/x2x
FRAME=$tooldir/frame
WINDOW=$tooldir/window
MGCEP=$tooldir/mcep
LPC2LSP=$tooldir/lpc2lsp
STEP=$tooldir/step
MERGE=$tooldir/merge
VSTAT=$tooldir/vstat
NRAND=$tooldir/nrand
SOPR=$tooldir/sopr
VOPR=$tooldir/vopr
NAN=$tooldir/nan
MINMAX=$tooldir/minmax

SAMPFREQ=44100   # Sampling frequency (48kHz)
FRAMELEN=1103   # Frame length in point (1200 = 48000 * 0.025)
FRAMESHIFT=221 # Frame shift in point (240 = 48000 * 0.005)
WINDOWTYPE=1 # Window type -> 0: Blackman 1: Hamming 2: Hanning
NORMALIZE=1  # Normalization -> 0: none  1: by power  2: by magnitude
FFTLEN=2048     # FFT length in point
FREQWARP=0.53   # frequency warping factor
GAMMA=0      # pole/zero weight for mel-generalized cepstral (MGC) analysis
MGCORDER=34   # order of MGC analysis
STRORDER=5     # order of STR analysis, number of filter banks for mixed excitation
MAGORDER=10    # order of Fourier magnitudes for pulse excitation generation
LNGAIN=1     # use logarithmic gain rather than linear gain
LOWERF0=80    # lower limit for f0 extraction (Hz)
UPPERF0=420    # upper limit for f0 extraction (Hz)
NOISEMASK=50  # standard deviation of white noise to mask noises in f0 extraction
MLEN=$(($MGCORDER+1))

job=1
srate=44100
fshift=5
FRAMESHIFT=$(( $srate * $fshift / 1000 ))

#echo "$0 $@"  # Print the command line for logging
. parse_options.sh

if [ $# != 2 ]; then
   echo "Wrong #arguments ($#, expected 2)"
   echo "Usage: compute-mgc-feats.sh [options] scp:<in.scp> <wspecifier>"
   echo " => will generate mcep using marytts tool"
   echo " e.g.: compute-mgc-feats.sh wav.scp ark:feats.ark"
   exit 1;
fi

for i in `awk -v lst="$1" 'BEGIN{if (lst ~ /^scp/) sub("[^:]+:[[:space:]]*","", lst); while (getline < lst) print $1 "___" $2}'`; do
    name=${i%%___*}
    wfilename=${i##*___}
    sox $wfilename -t raw - | ${X2X} +sf | \
    $FRAME -l $FRAMELEN -p $FRAMESHIFT | \
    $WINDOW -l $FRAMELEN -L $FFTLEN -w $WINDOWTYPE -n $NORMALIZE | \
    $MGCEP -a $FREQWARP -m $MGCORDER -l $FFTLEN -e 1.0E-08 | \
    $X2X +f +a$MLEN | \
    awk -v name=$name 'BEGIN{print name, "[";} {print} END{print "]"}'
done | copy-feats ark:- "$2"
