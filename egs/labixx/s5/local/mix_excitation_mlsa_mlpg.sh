#!/bin/bash
#
# Copyright 2016 Liushouda

period=5
sample_frequency=44100
delta_order=0
mgc_order=34
str_order=5
f0_order=2
# Continuous f0, no mixing
voice_thresh=0.8
alpha=0.55
fftlen=1024
tmpdir=/tmp
win=local/win
syn_cmd=
filter_file=local/filters/mix_excitation_5filters_199taps_48Kz.txt
use_logf0=0
smooth=0

[ -f path.sh ] && . ./path.sh; 
. parse_options.sh || exit 1;

cmp_file=$1
out_wav=$2
var_file=$3
base=`basename $cmp_file .cmp`
var=$tmpdir/var
cmp=$tmpdir/$base.cmp
#variance file
vmgc=$tmpdir/$base.mgc.var
vf0=$tmpdir/$base.f0.var
vstr=$tmpdir/$base.str.var
#pdf files
mpdf=$tmpdir/$base.mgc.pdf
fpdf=$tmpdir/$base.f0.pdf
strpdf=$tmpdir/$base.str.pdf
#feature files
mgc=$tmpdir/$base.mgc
f0=$tmpdir/$base.f0
str=$tmpdir/$base.str

#mgc_order=39
# Assuming: F0 - mgc - str
delta_mult=$(( $delta_order + 1 ))
f0_offset=1
f0_len=$(( $f0_order * $delta_mult ))

mgc_offset=$(( $f0_offset + $f0_len ))
mgc_len=$(( ($mgc_order + 1) * $delta_mult ))
order=$mgc_order

str_offset=$(( $mgc_offset + $mgc_len ))
str_len=$(( $str_order * $delta_mult ))

echo $f0_offset $f0_len $mgc_offset $mgc_len $str_offset $str_len

cat $cmp_file | sed -e 's/^ *//g' -e 's/ *$//g' \
    | awk -v nit=$delta_mult \
    -v off=$(( $f0_order + $mgc_order + 1 + $str_order )) \
    -v bnd="$f0_offset;$(($f0_offset + $f0_order));$(($f0_offset + $f0_order + $mgc_order + 1))" \
'
BEGIN{nb = split(bnd, bnda, ";"); bnda[nb + 1] = off+1; nb += 1;}
{ 
  for (b = 1; b < nb; b++) {
    for (k = 0; k < nit; k++) {
      for (i = bnda[b]; i < bnda[b+1]; i++) {
         printf "%f ", $(i + k * off); 
      }
    }
  }
  printf "\n"
}' > $cmp

if [ "$var_file" != "" -a $smooth -eq 1 ]; then
    mgc_win="-d $win/logF0_d1.win -d $win/logF0_d2.win"
    f0_win="-d $win/logF0_d1.win -d $win/logF0_d2.win"
    str_win="-d $win/logF0_d1.win -d $win/logF0_d2.win"
    #mgc_win="-d -0.20 -0.10 0.00 0.10 0.20 -d 0.29 -0.14 -0.29 -0.14 0.29"
    #f0_win="-d -0.20 -0.10 0.00 0.10 0.20 -d 0.29 -0.14 -0.29 -0.14 0.29"
    #str_win="-d -0.20 -0.10 0.00 0.10 0.20 -d 0.29 -0.14 -0.29 -0.14 0.29"
    #mgc_win="-d -0.20 -0.10 0.00 0.10 0.20 -d 0.04 0.04 0.01 -0.04 -0.1 -0.04 0.01 0.04 0.04"
    #f0_win="-d -0.20 -0.10 0.00 0.10 0.20 -d 0.04 0.04 0.01 -0.04 -0.1 -0.04 0.01 0.04 0.04"
    #str_win="-d -0.20 -0.10 0.00 0.10 0.20 -d 0.04 0.04 0.01 -0.04 -0.1 -0.04 0.01 0.04 0.04"
    
    echo "Extracting variances..."
    cat $var_file | awk '{printf "%f ", $2}' > $var
    cat $var | cut -d " " -f $mgc_offset-$(( $mgc_offset + $mgc_len - 1 )) > $vmgc
    cat $var | cut -d " " -f $f0_offset-$(( $f0_offset + $f0_len - 1 )) > $vf0
    cat $var | cut -d " " -f $str_offset-$(( $str_offset + $str_len - 1 )) > $vstr

    echo "Creating pdfs..."
    cat $cmp | cut -d " " -f $mgc_offset-$(( $mgc_offset + $mgc_len - 1 )) | awk -v var="`cat $vmgc`" '{print $0, var}' | x2x +a +f > $mpdf
    cat $cmp | cut -d " " -f $f0_offset-$(( $f0_offset + $f0_len - 1 )) | awk -v var="`cat $vf0`" '{print $0, var}' | x2x +a +f > $fpdf
    cat $cmp | cut -d " " -f $str_offset-$(( $str_offset + $str_len - 1 )) | awk -v var="`cat $vstr`" '{print $0, var}' | x2x +a +f > $strpdf
    
    echo "Running mlpg..."
    echo "mgc smoothing"
    mlpg -i 0 -m $mgc_order $mgc_win $mpdf | x2x +f +a$(( $mgc_order + 1 )) > $mgc
    echo "f0 smoothing"
    mlpg -i 0 -m $(( $f0_order - 1 )) $f0_win $fpdf | x2x +f +a$f0_order > ${f0}_raw
    echo "str smoothing"
    mlpg -i 0 -m $(( $str_order - 1 )) $str_win $strpdf | x2x +f +a$str_order > $str

    cat ${f0}_raw | awk -v thresh=$voice_thresh '{if ($1 > thresh && $2 > 10) print $2; else print 0.0}' > $f0

    # Do not do mlpg on mgc
    #cat $cmp | cut -d " " -f $mgc_offset-$(($mgc_offset + $mgc_order)) > $mgc
else
    cat $cmp | cut -d " " -f $mgc_offset-$(($mgc_offset + $mgc_order)) > $mgc
    #cat $cmp | cut -d " " -f $(($f0_offset+1)) > $f0
    cat $cmp | cut -d " " -f $f0_offset-$(($f0_offset + $f0_order - 1)) | awk -v thresh=$voice_thresh '{if ($1 > thresh && $2 > 10) print $2; else print 0.0}' > $f0
    cat $cmp | cut -d " " -f $str_offset-$(($str_offset + $str_order - 1))  > $str
fi

x2x +af $mgc > $mgc.float
x2x +af $str > $str.float
x2x +af $f0 > $f0.float
echo "$syn_cmd $filter_file $mgc.float $f0.float $str.float $out_wav $use_logf0 $sample_frequency"
$syn_cmd $filter_file $mgc.float $f0.float $str.float $out_wav $use_logf0 $sample_frequency
