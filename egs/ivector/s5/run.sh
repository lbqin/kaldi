#!/bin/bash

. cmd.sh
. path.sh
set -e
mfccdir=`pwd`/mfcc
vaddir=`pwd`/mfcc
nj=8
audio_dir_train=/home/sooda/data/ivector_train/
audio_dir_test=/home/sooda/data/ivector_test/

stage=3
num_gauss=2048
ivecdim=100


if [ $stage -le 1 ] ; then
    rm -rf data/{train,test}
    mkdir -p data/{train,test}

    makeid="xargs -i basename {} .wav"

    for step in train test; do
        eval audio_dir=\${audio_dir_${step}}
        #find $audio_dir -name "*.wav" | sort | $makeid | awk -v audiodir=$audio_dir '{line=$1" "audiodir"/"$1".wav"; print line}' > data/$step/wav.scp


        #cat data/$step/wav.scp | awk  '{
        #str_num = split($1, strs, "_");
        #speaker_id = strs[1];
        #line = $1" "speaker_id
        #print line
        #}' > data/$step/utt2spk
        #utils/utt2spk_to_spk2utt.pl data/$step/utt2spk > data/$step/spk2utt

         for nn in `find  $audio_dir/*.wav | sort -u | xargs -i basename {} .wav`; do
              spkid=`echo $nn | awk -F"_" '{print "" $1}'`
              spk_char=`echo $spkid | sed 's/\([A-Z]\).*/\1/'`
              spk_num=`echo $spkid | sed 's/[A-Z]\([0-9]\)/\1/'`
              spkid=$(printf '%s%.2d' "$spk_char" "$spk_num")
              utt_num=`echo $nn | awk -F"_" '{print $2}'`
              uttid=$(printf '%s%.2d_%.3d' "$spk_char" "$spk_num" "$utt_num")
              echo $uttid $audio_dir/$nn.wav >> data/$step/wav.scp
              echo $uttid $spkid >> data/$step/utt2spk
              #echo $uttid `sed -n 1p $audio_dir/$nn.wav.trn` >> data/$step/word.txt
              #echo $uttid `sed -n 3p $audio_dir/$nn.wav.trn` >> data/$step/phone.txt
          done 
          sort data/$step/wav.scp -o data/$step/wav.scp
          sort data/$step/utt2spk -o data/$step/utt2spk
          utils/utt2spk_to_spk2utt.pl data/$step/utt2spk > data/$step/spk2utt
          #cp data/$step/word.txt data/$step/text
          #sort data/$step/text -o data/$step/text
          #sort data/$step/phone.txt -o data/$step/phone.txt
    done
fi

if [ $stage -le 2 ] ; then
    steps/make_mfcc.sh --mfcc-config conf/mfcc.conf data/train exp/make_mfcc $mfccdir

    sid/compute_vad_decision.sh --nj $nj --cmd "$train_cmd" data/train exp/make_vad $vaddir

    sid/train_diag_ubm.sh --nj $nj --cmd "$train_cmd" data/train $num_gauss exp/diag_ubm_$num_gauss
    sid/train_full_ubm.sh --nj $nj --cmd "$train_cmd" data/train exp/diag_ubm_$num_gauss exp/full_ubm_$num_gauss
fi

if [ $stage -le 3 ] ; then
    sid/train_ivector_extractor.sh --cmd "$train_cmd -l mem_free=25G,ram_free=25G" \
      --num-iters 5 --ivector-dim $ivecdim exp/full_ubm_$num_gauss/final.ubm data/train \
      exp/extractor_$num_gauss
    sid/extract_ivectors.sh --cmd "$train_cmd -l mem_free=6G,ram_free=6G" --nj $nj \
  exp/extractor_$num_gauss data/train exp/ivectors_train
fi

if [ $stage -le 4 ] ; then
    steps/make_mfcc.sh --mfcc-config conf/mfcc.conf data/test exp/make_mfcc $mfccdir
    sid/compute_vad_decision.sh --nj $nj --cmd "$train_cmd" data/test exp/make_vad $vaddir
    sid/extract_ivectors.sh --cmd "$train_cmd -l mem_free=6G,ram_free=6G" --nj $nj \
  exp/extractor_$num_gauss data/test exp/ivectors_test
fi
