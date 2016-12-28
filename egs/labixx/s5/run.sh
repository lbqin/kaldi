source cmd.sh
source path.sh
H=`pwd`  #exp home
n=8
thchs=/home/sooda/data/thchs30-openslr
#sample_rate=16000
sample_rate=48000
FRAMESHIFT=0.005
#featdir=/home/sooda/data/features/
#corpus_dir=/home/sooda/data/tts/labixx1000_44k/
featdir=/home/sooda/data/features/
corpus_dir=/home/sooda/data/tts/rmm_48k/
test_dir=/home/sooda/data/tts/test/
#cppmary_base=/home/sooda/speech/cppmary_release/
cppmary_base=/home/sooda/speech/cppmary/
cppmary_bin=$cppmary_base/build/
mix_mlsa=$cppmary_bin/mlsaSynWithFilenames
expa=exp-align
train=data/full
lang=data/lang_phone
dict=data/dict_phone
phoneset=64

exp=exp_dnn
expdurdir=$exp/tts_dnn_dur_3_delta_quin5
dnndir=$exp/tts_dnn_train_3_deltasc2_quin5
#config
#0 not run; 1 run; 2 run and exit
DATA_PREP_MARY=1
LANG_PREP_PHONE=1
EXTRACT_FEAT=0
EXTRACT_FEAT_MARY=0
ALIGNMENT_PHONE=1
GENERATE_LABLE=1
GENERATE_STATE=1
EXTRACT_MERLIN_FEATURE=2
EXTRACT_TXT_FEATURE=0
CONVERT_FEATURE=1
TRAIN_DNN=1
PACKAGE_DNN=1
VOCODER_TEST=0
spk="lbx"
audio_dir=$corpus_dir/wav 
prompt_lab=prompt_labels
state_lab=states
lab=labels
acoustic_textfeat=$corpus_dir/ali
duration_textfeat=$corpus_dir/ali_dur
acdir=data
lbldir=lbldata
durdir=durdata
lbldurdir=lbldurdata

echo "##### Step 0: data preparation #####"
if [ $DATA_PREP_MARY -gt 0 ]; then
    rm -rf data/{train,dev,full}
    rm -rf $exp $expa
    #rm -rf $featdir
    mkdir -p data/{train,dev,full}

    makeid="xargs -i basename {} .wav"

    find $audio_dir -name "*.wav" | sort | $makeid | awk -v audiodir=$audio_dir '{line=$1" "audiodir"/"$1".wav"; print line}' >> data/full/wav.scp
    cat data/full/wav.scp | awk -v spk=$spk '{print $1, spk}' >> data/full/utt2spk
    utils/utt2spk_to_spk2utt.pl data/full/utt2spk > data/full/spk2utt

    utils/subset_data_dir_tr_cv.sh data/full data/train data/dev 

    if [ $DATA_PREP_MARY -eq 2 ]; then
        echo "exit in data prepare"
        exit
    fi
fi


echo "make phonset"
if [ $LANG_PREP_PHONE -gt 0 ]; then
  rm -rf $dict $lang data/local/lang_phone
  cd $H; mkdir -p $dict $lang && \
  cp local/dict$phoneset/{extra_questions.txt,nonsilence_phones.txt,optional_silence.txt,silence_phones.txt} $dict  && \
  cat local/dict$phoneset/lexicon.txt | grep -v '<eps>' | sort -u > $dict/lexicon.txt  && \
  echo "<SIL> sil " >> $dict/lexicon.txt  || exit 1;
  utils/prepare_lang.sh --num-nonsil-states 5 --share-silence-phones true --position_dependent_phones false $dict "<SIL>" data/local/lang_phone $lang || exit 1;
  if [ $LANG_PREP_PHONE -eq 2 ]; then
      echo "exit in language"
      exit
  fi
fi

#############################################
###### Step 1: acoustic data generation #####
#############################################
echo "##### Step 1: acoustic data generation #####"

if [ $EXTRACT_FEAT -gt 0 ]; then
    for step in train dev; do
        rm -f data/$step/feats.scp
        # Generate f0 features
        local/make_pitch.sh --pitch-config conf/pitch.conf data/$step exp/make_pitch/$step $featdir;
        cp data/$step/pitch_feats.scp data/$step/feats.scp
        # Compute CMVN on pitch features, to estimate min_f0 (set as mean_f0 - 2*std_F0)
        steps/compute_cmvn_stats.sh data/$step exp/compute_cmvn_pitch/$step $featdir;
        # For bndap / mcep extraction to be successful, the frame-length must be adjusted
        # in relation to the minimum pitch frequency.
        # We therefore do something speaker specific using the mean / std deviation from
        # the pitch for each speaker.
        min_f0=`copy-feats scp:"awk -v spk=$spk '(\\$1 == spk){print}' data/$step/cmvn.scp |" ark,t:- \
        | awk '(NR == 2){n = \$NF; m = \$2 / n}(NR == 3){std = sqrt(\$2/n - m * m)}END{print m - 2*std}'`
        echo $min_f0
        # Rule of thumb recipe; probably try with other window sizes?
        bndapflen=`awk -v f0=$min_f0 'BEGIN{printf "%d", 4.6 * 1000.0 / f0 + 0.5}'`
        mcepflen=`awk -v f0=$min_f0 'BEGIN{printf "%d", 2.3 * 1000.0 / f0 + 0.5}'`
        f0flen=`awk -v f0=$min_f0 'BEGIN{printf "%d", 2.3 * 1000.0 / f0 + 0.5}'`
        echo "using wsizes: $f0flen $bndapflen $mcepflen"
        # Generate Band Aperiodicity feature
        local/make_bndap.sh --bndap-config conf/bndap.conf --frame_length $bndapflen data/$step exp/make_bndap/$step $featdir
        # Regenerate pitch with more appropriate window
        local/make_pitch.sh --pitch-config conf/pitch.conf --frame_length $f0flen data/$step exp/make_pitch/$step $featdir;
        # Generate Mel Cepstral features
        #steps/make_mcep.sh  --sample-frequency $sample_rate --frame_length $mcepflen  data/${step}_$spk exp/make_mcep/${step}_$spk   $featdir	
        local/make_mcep.sh --sample-frequency $sample_rate data/$step exp/make_mcep/$step $featdir
        # Merge features
        # Have to set the length tolerance to 1, as mcep files are a bit longer than the others for some reason
        paste-feats --length-tolerance=1 scp:data/$step/pitch_feats.scp scp:data/$step/mcep_feats.scp scp:data/$step/bndap_feats.scp ark,scp:$featdir/${step}_cmp_feats.ark,data/$step/feats.scp
        # Compute CMVN on whole feature set
        steps/compute_cmvn_stats.sh data/$step exp/compute_cmvn/$step data/$step
    done

    if [ $EXTRACT_FEAT -eq 2 ]; then
        echo "exit in extract feature"
        exit
    fi
fi

if [ $EXTRACT_FEAT_MARY -gt 0 ]; then
    for step in train dev; do
		if [ "$sample_rate" == "16000" ]; then
			local/make_pitch.sh --pitch-config conf/pitch.conf data/$step exp/make_pitch/$step $featdir || exit 1
		elif [ "$sample_rate" == "44100" ]; then
			local/make_pitch.sh --pitch-config conf/pitch-44k.conf data/$step exp/make_pitch/$step $featdir || exit 1
        elif [ "$sample_rate" == "48000" ]; then
			local/make_pitch.sh --pitch-config conf/pitch-48k.conf data/$step exp/make_pitch/$step $featdir || exit 1
		fi

        #local/make_lf0.sh --sample-frequency $sample_rate data/$step exp/make_lf0/$step $featdir || exit 1
        local/make_mgc.sh --sample-frequency $sample_rate data/$step exp/make_mgc/$step $featdir || exit 1
        local/make_str.sh --sample-frequency $sample_rate data/$step exp/make_str/$step $featdir || exit 1
        paste-feats --length-tolerance=1 scp:data/$step/pitch_feats.scp scp:data/$step/mgc_feats.scp scp:data/$step/str_feats.scp ark,scp:$featdir/${step}_cmp_feats.ark,data/$step/feats.scp || exit 1
        steps/compute_cmvn_stats.sh data/$step exp/compute_cmvn/$step data/$step || exit 1
    done

    if [ $EXTRACT_FEAT_MARY -eq 2 ]; then
        echo "done and exit in extract mary feature"
        exit
    fi
fi


#######################################
## 3a: create kaldi forced alignment ##
#######################################

echo "##### Step 3: forced alignment #####"
utils/fix_data_dir.sh data/full
utils/validate_lang.pl $lang

if [ $ALIGNMENT_PHONE -gt 0 ]; then
    #generate alignment transcript with cppmary: phones.txt
    cd $cppmary_base
    $cppmary_bin/genTrainPhones "data/labixx$phoneset.conf" $corpus_dir
    cd $H
    cat $corpus_dir/phones.txt | sort > data/full/text

    if [ "$sample_rate" == "16000" ]; then
        steps/make_mfcc.sh --mfcc-config conf/mfcc.conf data/full exp/make_mfcc/full $featdir
    elif [ "$sample_rate" == "44100" ]; then
        steps/make_mfcc.sh --mfcc-config conf/mfcc-44k.conf data/full exp/make_mfcc/full $featdir
    elif [ "$sample_rate" == "48000" ]; then
        steps/make_mfcc.sh --mfcc-config conf/mfcc-48k.conf data/full exp/make_mfcc/full $featdir
    fi
    steps/compute_cmvn_stats.sh data/full exp/make_mfcc/full $featdir || exit 1

    # Now running the normal kaldi recipe for forced alignment
    steps/train_mono.sh --boost-silence 0.25 --nj $n --cmd "$train_cmd" \
                  $train $lang $expa/mono
    steps/align_si.sh --boost-silence 0.25 --nj $n --cmd "$train_cmd" \
                $train $lang $expa/mono $expa/mono_ali
    steps/train_deltas.sh  --boost-silence 0.25 --cmd "$train_cmd" \
                 500 5000 $train $lang $expa/mono_ali $expa/tri1

    steps/align_si.sh  --nj $n --cmd "$train_cmd" \
                $train $lang $expa/tri1 $expa/tri1_ali
    steps/train_deltas.sh --cmd "$train_cmd" \
                 500 5000 $train $lang $expa/tri1_ali $expa/tri2

    # Create alignments
    steps/align_si.sh  --nj $n --cmd "$train_cmd" \
        $train $lang $expa/tri2 $expa/tri2_ali_full

    steps/train_deltas.sh --cmd "$train_cmd" \
        --context-opts "--context-width=5 --central-position=2" \
        500 5000 $train $lang $expa/tri2_ali_full $expa/quin

    # Create alignments
    steps/align_si.sh --nj $n --cmd "$train_cmd" \
      $train $lang $expa/quin $expa/quin_ali_full || exit 1

    ali=$expa/quin_ali_full
    # Extract phone alignment
    ali-to-phones --per-frame $ali/final.mdl ark:"gunzip -c $ali/ali.*.gz|" ark,t:- \
      | utils/int2sym.pl -f 2- $lang/phones.txt > $ali/phones.txt || exit 1

    ali-to-hmmstate $ali/final.mdl ark:"gunzip -c $ali/ali.*.gz|" ark,t:$ali/states.tra || exit 1

    if [ $ALIGNMENT_PHONE -eq 2 ]; then
        echo "exit after phone alignment"
        exit
    fi
fi

if [ $GENERATE_LABLE -gt 0 ]; then
    mkdir -p $prompt_lab
    rm $prompt_lab/*.lab
    cat $expa/quin_ali_full/phones.txt | awk -v frameshift=$FRAMESHIFT -v labeldir=$prompt_lab '
    {
        lasttime = 0;
        lasttoken="";
        currenttime=0;
    }
    {
        outfile = labeldir"/"$1".lab";
        for(i=2;i<=NF;i++) {
            if (lasttoken != "" && lasttoken != $i) {
                print lasttoken, lasttime, currenttime >> outfile
                lasttime = currenttime
            }
            lasttoken = $i; 
            currenttime = currenttime + frameshift;
        }
        print lasttoken, lasttime, currenttime >> outfile
    }'

    if [ $GENERATE_LABLE -eq 2 ]; then
        echo "exit after phone alignment"
        exit
    fi
fi

if [ $GENERATE_STATE -gt 0 ]; then
    mkdir -p $state_lab
    rm $state_lab/*.sta
    cat $expa/quin_ali_full/states.tra | awk -v statedir=$state_lab '
    {
        laststate = -1;
        counter = 0;
    }
    {
        outfile = statedir"/"$1".sta";
        for(i=2;i<=NF;i++) {
            if (laststate != $i && laststate != -1) {
                printf "%d %d ", laststate, counter > outfile
                if ($i == "0") printf("\n") >> outfile
                counter = 0
            }
            counter = counter + 1
            laststate = $i
        }
        printf "%d %d ", laststate, counter > outfile

    }'

    # paste the phone alignment and state aliment
    mkdir -p $lab
    rm -rf $lab/*.lab
    for nn in `find $prompt_lab/*.lab | sort -u | xargs -n 1 basename | sed 's/\.lab//g' `; do
        statename=$state_lab/$nn.sta
        labelname=$prompt_lab/$nn.lab
        mergelab=$lab/$nn.lab
        paste $labelname $statename -d '|' | sed 's/\t/ /g' > $mergelab
    done

    if [ $GENERATE_STATE -eq 2 ]; then
        echo "exit after state alignment"
        exit
    fi
fi

if [ $EXTRACT_MERLIN_FEATURE -gt 0 ]; then
    cd $cppmary_base
    rm $corpus_dir/lab/*.lab
    mkdir -p $corpus_dir/lab
    echo "$cppmary_bin/genMerlinFeat "data/labixx.conf" $corpus_dir $H/$lab/ $corpus_dir/lab"
    $cppmary_bin/genMerlinFeat "data/labixx.conf" $corpus_dir $H/$lab/ $corpus_dir/lab
    cd $corpus_dir/lab
    ls $corpus_dir/lab | xargs -i basename {} .lab > $corpus_dir/basename.scp
    cd $H
    if [ $EXTRACT_MERLIN_FEATURE -eq 2 ]; then
        echo "exit after merlin feature"
        exit
    fi
fi

if [ $EXTRACT_TXT_FEATURE -gt 0 ]; then
    cd $cppmary_base
    echo "$cppmary_bin/genTextFeatureWithLab $cppmary_base/data/labixx.conf $corpus_dir $H/$lab/ $acoustic_textfeat $duration_textfeat"
    $cppmary_bin/genTextFeatureWithLab "data/labixx.conf" $corpus_dir $H/$lab/ $acoustic_textfeat $duration_textfeat
    cd $H
    if [ $EXTRACT_TXT_FEATURE -eq 2 ]; then
        echo "exit after text feature"
        exit
    fi
fi


if [ $CONVERT_FEATURE -gt 0 ]; then
    copy-feats ark:$acoustic_textfeat ark,t,scp:$featdir/in_feats_full.ark,$featdir/in_feats_full.scp

    duration_feats="ark:$duration_textfeat"
    nfeats=$(feat-to-dim "$duration_feats" -)

    # Input
    select-feats 0-$(( $nfeats - 3 )) "$duration_feats" ark,scp:$featdir/in_durfeats_full.ark,$featdir/in_durfeats_full.scp
    # Output: duration of phone and state are assumed to be the 2 last features
    select-feats $(( $nfeats - 2 ))-$(( $nfeats - 1 )) "$duration_feats" ark,scp:$featdir/out_durfeats_full.ark,$featdir/out_durfeats_full.scp

    for step in train dev; do
      dir=$lbldir/$step
      mkdir -p $dir
      utils/filter_scp.pl data/$step/utt2spk $featdir/in_feats_full.scp > $dir/feats.scp
      cat data/$step/utt2spk | awk -v lst=$dir/feats.scp 'BEGIN{ while (getline < lst) n[$1] = 1}{if (n[$1]) print}' > $dir/utt2spk
      utils/utt2spk_to_spk2utt.pl < $dir/utt2spk > $dir/spk2utt
      steps/compute_cmvn_stats.sh $dir $dir $dir
    done


    # Same for duration
    for step in train dev; do
      dir=$lbldurdir/$step
      mkdir -p $dir
      utils/filter_scp.pl data/$step/utt2spk $featdir/in_durfeats_full.scp > $dir/feats.scp
      cat data/$step/utt2spk | awk -v lst=$dir/feats.scp 'BEGIN{ while (getline < lst) n[$1] = 1}{if (n[$1]) print}' > $dir/utt2spk
      utils/utt2spk_to_spk2utt.pl < $dir/utt2spk > $dir/spk2utt
      steps/compute_cmvn_stats.sh $dir $dir $dir

      dir=$durdir/$step
      mkdir -p $dir
      utils/filter_scp.pl data/$step/utt2spk $featdir/out_durfeats_full.scp > $dir/feats.scp
      cat data/$step/utt2spk | awk -v lst=$dir/feats.scp 'BEGIN{ while (getline < lst) n[$1] = 1}{if (n[$1]) print}' > $dir/utt2spk
      utils/utt2spk_to_spk2utt.pl < $dir/utt2spk > $dir/spk2utt
      steps/compute_cmvn_stats.sh $dir $dir $dir
    done

    #ensure consistency in lists
    for class in train dev; do
      cp $lbldir/$class/feats.scp $lbldir/$class/feats_full.scp
      cp $acdir/$class/feats.scp $acdir/$class/feats_full.scp
      cat $acdir/$class/feats_full.scp | awk -v lst=$lbldir/$class/feats_full.scp 'BEGIN{ while (getline < lst) n[$1] = 1}{if (n[$1]) print}' > $acdir/$class/feats.scp
      cat $lbldir/$class/feats_full.scp | awk -v lst=$acdir/$class/feats_full.scp 'BEGIN{ while (getline < lst) n[$1] = 1}{if (n[$1]) print}' > $lbldir/$class/feats.scp
    done
    if [ $CONVERT_FEATURE -eq 2 ]; then
        echo "exit after convert feature"
        exit
    fi
fi


if [ -s $acdir/train/feats.scp ]; then
    echo "file $acdir/train/feats.scp not empty, continue to train"
else
    echo "file $acdir/train/feats.scp empty, there must be somethin wrong"
    exit
fi


##############################
## 4. Train DNN
##############################

if [ $TRAIN_DNN -gt 0 ]; then
    echo "##### Step 4: training DNNs #####"

    mkdir -p $exp
    # A. Small one for duration modelling
    echo " ### Step 4a: duration model DNN ###"
    rm -rf $expdurdir
    # duration not need delta order?
    $train_cmd $expdurdir/log/train_nnet.log local/train_nnet_basic.sh --delta_order 2 --config conf/5-layer-nn-splice5.conf --learn_rate 0.02 --momentum 0.3 --halving-factor 0.8 --min_iters 15 --max_iters 50 --randomize true --cache_size 50000 --bunch_size 200 --mlpOption " " --hid-dim 512 $lbldurdir/train $lbldurdir/dev $durdir/train $durdir/dev $expdurdir || exit 1

    # B. Larger DNN for acoustic features
    echo " ### Step 4b: acoustic model DNN ###"

    rm -rf $dnndir
    $train_cmd $dnndir/log/train_nnet.log local/train_nnet_basic.sh --delta_order 2 --config conf/5-layer-nn-splice5.conf --learn_rate 0.04 --momentum 0.3 --halving-factor 0.8 --min_iters 15 --randomize true --cache_size 50000 --bunch_size 200 --mlpOption " " --hid-dim 512 $lbldir/train $lbldir/dev $acdir/train $acdir/dev $dnndir || exit 1

    if [ $TRAIN_DNN -eq 2 ]; then
        echo "exit after train dnn"
        exit
    fi
fi

##############################
## 5. Synthesis
##############################

if [ "$sample_rate" == "16000" ]; then
  order=39
  alpha=0.42
  fftlen=1024
  bndap_order=21
  filter_file=$cppmary_base/data/mix_excitation_5filters_99taps_16Kz.txt
elif [ "$sample_rate" == "48000" ]; then
  order=60
  alpha=0.55
  fftlen=4096
  bndap_order=25
  filter_file=$cppmary_base/data/mix_excitation_5filters_199taps_48Kz.txt
elif [ "$sample_rate" == "44100" ]; then
  order=60
  alpha=0.53
  fftlen=4096
  bndap_order=25
  filter_file=$cppmary_base/data/mix_excitation_5filters_199taps_48Kz.txt
fi

echo "##### Step 5: synthesis #####"

if [ $VOCODER_TEST -gt 0 ]; then
    # Original samples:
    echo "Synthesizing vocoded training samples"
    rm -rf exp_dnn/orig2
    mkdir -p exp_dnn/orig2/cmp exp_dnn/orig2/wav
    copy-feats scp:data/dev/feats.scp ark,t:- | awk -v dir=exp_dnn/orig2/cmp/ '($2 == "["){if (out) close(out); out=dir $1 ".cmp";}($2 != "["){if ($NF == "]") $NF=""; print $0 > out}'
    for cmp in exp_dnn/orig2/cmp/*.cmp; do
      local/mix_excitation_mlsa_mlpg.sh --syn_cmd $mix_mlsa --sample-frequency $sample_rate --filter_file $filter_file $cmp exp_dnn/orig2/wav/`basename $cmp .cmp`.wav
    done
    if [ $VOCODER_TEST -eq 2 ]; then
        echo "exit vocoder test"
        exit
    fi
fi

# Variant with mlpg: requires mean / variance from coefficients
copy-feats scp:data/train/feats.scp ark:- \
| add-deltas --delta-order=2 ark:- ark:- \
| compute-cmvn-stats --binary=false ark:- - \
| awk '
(NR==2){count=$NF; for (i=1; i < NF; i++) mean[i] = $i / count}
(NR==3){if ($NF == "]") NF -= 1; for (i=1; i < NF; i++) var[i] = $i / count - mean[i] * mean[i]; nv = NF-1}
END{for (i = 1; i <= nv; i++) print mean[i], var[i]}' \
> data/train/var_cmp.txt

echo "  ###  5b: labixx samples synthesis ###"
mkdir -p data/eval

durIn=$test_dir/durali

cd $cppmary_base
$cppmary_bin/genDurInFeat "data/labixx$phoneset.conf" $test_dir $durIn
cd $H


# Generate input feature for duration modelling
copy-feats ark:$durIn ark,scp:$featdir/in_durfeats_eval.ark,$featdir/in_durfeats_eval.scp

# Duration based test set
dir=lbldurdata/eval
mkdir -p $dir
cp $featdir/in_durfeats_eval.scp $dir/feats.scp
cut -d ' ' -f 1 $dir/feats.scp | awk -v spk=$spk '{print $1, spk}' > $dir/utt2spk
utils/utt2spk_to_spk2utt.pl $dir/utt2spk > $dir/spk2utt
steps/compute_cmvn_stats.sh $dir $dir $dir

# Generate label with DNN-generated duration
echo "Synthesizing MLPG eval samples"
#  1. forward pass through duration DNN
local/make_forward_fmllr.sh $expdurdir $lbldurdir/eval $expdurdir/tst_forward/ ""

testAlignDir=test_labels
mkdir -p $testAlignDir
rm -rf $testAlignDir/*.lab

#  2. make the duration consistent, generate labels with duration information added
for cmp in $expdurdir/tst_forward/cmp/*.cmp; do
  cat $cmp | awk -v outdir=$testAlignDir -v nstate=5 -v id=`basename $cmp .cmp` '
  BEGIN{
    print "\"" id ".lab\""; 
    outfile = outdir"/"id".lab"
    tstart = 0 
  }
  {
    pd += $2;
    sd[NR % nstate] = $1
  }
  (NR % nstate == 0){
    mpd = pd / nstate;
    smpd = 0;
    for (i = 1; i <= nstate; i++) smpd += sd[i % nstate];
    rmpd = int((smpd + mpd) / 2 + 0.5);
    for (i = 1; i <= nstate; i++) {
      sd[i % nstate] = int(sd[i % nstate] / smpd * rmpd + 0.5);
    }
    if (sd[0] <= 0) sd[0] = 1;
    if (sd[1] <= 0) sd[1] = 1;
    smpd = 0;
    for (i = 1; i <= nstate; i++) smpd += sd[i % nstate];
    tend = tstart + smpd * 0.005
    printf "%f %f | ", tstart, tend > outfile
    for (i = 1; i <= nstate; i++) {
      if (sd[i % nstate] > 0) {
        printf "%d %d ", i-1, sd[i%nstate] >> outfile
      }
    }
    printf "\n" >> outfile
    tstart = tend;
    pd = 0;
  }'
done

dnnIn=$test_dir/dnnali

#call cppmary to generate dnnInput
cd $cppmary_base
echo "$cppmary_bin/genDnnInFeat "data/labixx$phoneset.conf" $test_dir $H/$testAlignDir/ $dnnIn"
$cppmary_bin/genDnnInFeat "data/labixx$phoneset.conf" $test_dir $H/$testAlignDir/ $dnnIn
cd $H


# 3. Turn them into DNN input labels (i.e. one sample per frame)
copy-feats ark:$dnnIn ark,t,scp:$featdir/in_feats_eval.ark,$featdir/in_feats_eval.scp
dir=lbldata/eval
mkdir -p $dir
cp $featdir/in_feats_eval.scp $dir/feats.scp
cut -d ' ' -f 1 $dir/feats.scp | awk -v spk=$spk '{print $1, spk}' > $dir/utt2spk
utils/utt2spk_to_spk2utt.pl $dir/utt2spk > $dir/spk2utt
steps/compute_cmvn_stats.sh $dir $dir $dir

# 4. Forward pass through big DNN
local/make_forward_fmllr.sh $dnndir $lbldir/eval $dnndir/tst_forward/ ""

# 5. Vocoding
rm -rf $dnndir/tst_forward/wav_mlpg
mkdir -p $dnndir/tst_forward/wav_mlpg/; 
for cmp in $dnndir/tst_forward/cmp/*.cmp; do
  local/mix_excitation_mlsa_mlpg.sh --voice_thresh 0.4 --smooth 1 --syn_cmd $mix_mlsa --sample-frequency $sample_rate --filter_file $filter_file --delta_order 2 $cmp $dnndir/tst_forward/wav_mlpg/`basename $cmp .cmp`.wav data/train/var_cmp.txt
done

if [ $PACKAGE_DNN -gt 0 ]; then
    echo "#### Step 6: packaging DNN voice ####"

    local/make_dnn_voice.sh --spk $spk --sample_rate $sample_rate --mcep_order $order --bndap_order $bndap_order --alpha $alpha --fftlen $fftlen

    echo "Voice packaged successfully. Portable models have been stored in ${spk}_mdl."
    echo "Synthesis can be performed using:
    echo \"This is a demo of D N N synthesis\" | utils/synthesis_voice.sh ${spk}_mdl <outdir>"
fi
