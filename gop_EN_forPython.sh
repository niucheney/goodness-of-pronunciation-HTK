#!/bin/bash
 
bool_live=1

if [ "$#" -eq 1 ]; then
    input_file=$1
elif [ "$#" -eq 2 ]; then
    wav=$1
    input_file=$2
    bool_live=0
fi


scripts_dir=`pwd`

models_dir=$scripts_dir/EN_p2fa_16000

outdir=tmp.$$
mkdir -p $outdir
echo "Output in: $outdir/"
echo


sr=16000
# mode=posterior
# mode=likelihood

if [ "$bool_live" -gt 0 ]; then 

    raw=recorded.raw
    base=`basename $raw .raw`

    cd ../portaudio/bin

    ./paex_record_noPlayBack

    mv $raw $scripts_dir/
    cd $scripts_dir

    audio=${base}.wav
    sox -c 1 -r 16k -e floating-point -b 32 -L $raw -t wav  -r 16k -e signed -b 16 $outdir/$audio

    config=$models_dir/config

else

    base=`basename $wav .wav`
    audio=${base}.wav

    sox -t aiff $wav -t wav -r $sr -e signed-integer -b 16 $outdir/$audio pad 1 1

    config=$models_dir/config_padding

fi

# endTime="-1"
# echo "$audio 1 SpkID 0.0 $endTime <o,F1,unknown> $word" > $base.stm

cd $outdir
 
dic=dictionnary
labfile=$base.lab

# tr ' ' '\n' < $sentence_file | perl -n -e '{use utf8; use encoding "utf8"; $_=lc(); print;}' | awk '{if(NF>0){print}}' > $labfile
head -1 ../$input_file | tr ' ' '_' | awk '{if(NF>0){print}}' > $labfile

echo "SENT-START	[]	sil" > $dic
echo "SENT-END	[]	sil" >> $dic
verbose=1
head -1 ../$input_file | tr ' ' '_' | tr '\n' '\t' >> $dic
head -2 ../$input_file |  tail -1 >> $dic
echo ".	[]	sil" >> $dic
echo "silence	[]	sil" >> $dic

# generate phone level MLF file from the sentence lab file (one word per line)
mlf_phones=$base.phones.mlf

echo "." >> $labfile
HLEd -d $dic -i $mlf_phones $scripts_dir/mkphones0.led $labfile 
rm $mlf_phones

# forced alignment
mlf_input=input.mlf

echo "#!MLF!#" > $mlf_input
echo "${base}.lab" >> $mlf_input
cat $labfile >> $mlf_input

mlf_align=aligned.mlf

scp_input=input.scp
echo $audio > $scp_input


log_align=align.log

echo
echo "Force aligning..."

HVite -l '*' \
-C $config \
-T 1 \
-b silence \
-a \
-H $models_dir/hmmdefs \
-H $models_dir/macros \
-i $mlf_align \
-m \
-t 250.0 \
-I $mlf_input \
-S $scp_input \
$dic \
$models_dir/list 2>&1 | tee -a $log_align

# wavesurfer 
surfer_align=surfer_aligned.txt
awk '{if(NF>3){printf "%.2f %.2f %s\n", $1*(10**-7), $2*(10**-7), $3}}' aligned.mlf > $surfer_align

# free phone loop ASR

# Grammar parsing: free phone loop

# create network
# http://www.ee.columbia.edu/ln/LabROSA/doc/HTKBook21/node131.html

echo "(SENT-START <" > $models_dir/networkTMP
echo "sil" >> $models_dir/networkTMP
head -3 ../$input_file |  tail -1  >> $models_dir/networkTMP
echo "sil" >> $models_dir/networkTMP
echo "> SENT-END ) " >> $models_dir/networkTMP

HParse $models_dir/networkTMP $models_dir/networkTMP.htk

# Recognition
echo
echo "Free phone loop reco..."

mlf_reco=recognized.mlf
log_reco=reco.log

HVite \
-C $config \
-T 1 \
-b sil \
-w $models_dir/networkTMP.htk \
-H $models_dir/hmmdefs \
-H $models_dir/macros \
-t 250.0 150.0 2000.0 \
-l ./ \
-i $mlf_reco \
-S $scp_input \
$models_dir/dictionary \
$models_dir/list 2>&1 | tee -a  $log_reco


# infile=align_reco_optimal_per_frame.log
# paste $log_align $log_reco | awk '{print $2, $4, $5, $6, $7, $11, $14}' > $infile


# wavesurfer 
surfer_reco=surfer_recognized.txt
awk '{if(NF>3){printf "%.2f %.2f %s\n", $1*(10**-7), $2*(10**-7), $3}}' $mlf_reco > $surfer_reco

# infile=align_reco_optimal_per_frame.log
# paste $log_align $log_reco | awk '{print $2, $4, $5, $6, $7, $11, $14}' > $infile

infile=$mlf_align
infile2=$mlf_reco
info_outfile=../gop.txt

if [ -e $info_outfile ]; then rm $info_outfile; fi

first_word=true
unconstrained=0
unconstrained_phone=0
forced=0
forced_phone=0
dur_totale_mot=0
found=false

echo
echo
dir=/Users/cavaco/Work/MILLA/software/cerevoice_sdk_3.1.0_darwin_i386_python25_9536_academic
 echo "let's see how you did, please wait a minute" | $dir/examples/basictts/basictts $dir//voices/cerevoice_heather_3.0.8_22k.voice $dir/voices/cerevoice_heather_3.0.8_22k.license
 
while read line; do

  nb_fields=`echo $line | awk '{print NF}'`;
  if [ $nb_fields -lt 4 ]; then continue; fi;

  if [ $nb_fields -eq 5 ]; then 
    
    if [ "$first_word" = false ]; then
    
      if [ $word = "silence" ] || [ $word = "." ] ; then continue; fi;
      
      endSeconds=`echo "$startSeconds $dur_totale_mot" | awk '{printf "%.2f", $1+$2*(10**-2)}'`
      gop=`echo "$forced $dur_totale_mot $unconstrained" | awk '{printf "%.4f", $1*$2-$3}'`
      # echo "FORCED=$forced UNC=$unconstrained"
      
      # !!!! REVOIR LE CALCUL GOP_MOT pour l'instant c'est WROOOOOOOOOOOOOOONG!!!! 
#      echo "Word \"$word\" detected in file \"$audio\" (second $startSeconds to $endSeconds) gave an overall GOP measure of $gop"
#      echo
      
      unconstrained=0
      forced=0
      dur_totale_mot=0
      word=`echo $line | awk '{print $5}'`;
      startSeconds=`echo $line | awk '{printf "%.2f", $1*(10**-7)}'`;
      if [ $word = "silence" ] || [ $word = "." ] ; then continue; fi;
      # break
    else
      word=`echo $line | awk '{print $5}'`;
      if [ $word = "silence" ] || [ $word = "." ] ; then continue; fi;
      startSeconds=`echo $line | awk '{printf "%.2f", $1*(10**-7)}'`;
      first_word=false
    fi
  fi;
  
  phone=`echo $line | awk '{print $3}'`; 
  
  if [ $phone = "sp" ] || [ $phone = "sil" ]; then continue; fi;

  beg=`echo $line | awk '{printf "%d", $1}'`;
  end=`echo $line | awk '{printf "%d", $2}'`;
  sc=`echo $line | awk '{print $4}'`;
  startSeconds_phone=`echo "$beg" | awk '{printf "%.2f", $1*(10**-7)}'`
  endSeconds_phone=`echo "$end" | awk '{printf "%.2f", $1*(10**-7)}'`

  dur=`echo "$end $beg" | awk '{printf "%d", ($1-$2)*(10**-5)}'`
  dur_totale_mot=`echo "$dur_totale_mot $dur" | awk '{printf "%d", $1+$2}'`

#  forced_phone=`echo "$sc $dur" | awk '{printf $1/$2}'`
#  forced_phone=$sc/$dur
  forced_phone=$sc
  
  if [ $phone != "cl" ] && [ $phone != "vcl" ]; then 
    forced=`echo "$forced $forced_phone" | awk '{printf "%.4f", $1+$2}'`
  fi;

  unconstrained_phone=0
  
  info="W=$word $phone $dur "
  
  while read line2; do

    nb_fields2=`echo $line2 | awk '{print NF}'`;
    if [ $nb_fields2 -lt 4 ]; then continue; fi;

    phone2=`echo $line2 | awk '{print $3}'`;
    if [ $phone2 = "sp" ] || [ $phone2 = "sil" ]; then continue; fi;
		
    beg2=`echo $line2 | awk '{printf "%d", $1}'`;
    end2=`echo $line2 | awk '{printf "%d", $2}'`;
    sc2=`echo $line2 | awk '{printf "%.4f", $4}'`;

    dur_total_free_phone=`echo "$end2 $beg2" | awk '{printf "%d", ($1-$2)*(10**-5)}'`

    if [ $beg2 -ge $end ]; then
      break
    fi
    if [ $end2 -le $beg ]; then
      continue
    fi

    if [ $phone = $phone2 ]; then found=true; fi
    
    if [ $beg2 -le $beg ]; then
      if [ $end2 -le $end ]; then
	dur2=`echo "$beg $end2" | awk '{printf "%d", ($2-$1)*(10**-5)}'`
      else
	dur2=`echo "$beg $end" | awk '{printf "%d", ($2-$1)*(10**-5)}'`
      fi
    else
      if [ $end2 -le $end ]; then
	dur2=`echo "$beg2 $end2" | awk '{printf "%d", ($2-$1)*(10**-5)}'`
      else
	dur2=`echo "$beg2 $end" | awk '{printf "%d", ($2-$1)*(10**-5)}'`
      fi
    fi

#    if [ $dur2 -gt 1 ]; then
#      if [ $phone != "cl" ] && [ $phone != "vcl" ]; then 
	unconstrained=`echo "$unconstrained + $sc2*$dur2/$dur_total_free_phone" | bc -l`
#      fi
      # unconstrained_phone=`echo "$unconstrained_phone + $sc2*$dur2/$dur_total_free_phone" | bc -l`
      unconstrained_phone=`echo "$unconstrained_phone $sc2 $dur2 $dur_total_free_phone" | awk '{printf "%.4f", $1 + $2*$3/$4 }'`
#    fi
    
    # echo "         2.: PHONE: $phone2 $beg2 $end2 $dur2 $sc2 $unconstrained_phone"
    info="$info $phone2 $dur2 "

  done < $infile2

  gop_phone=`echo "$forced_phone $unconstrained_phone $dur" | awk '{printf "%.4f", ($1-$2)/$3}'`

  # valeur absolue:
  gop_phone=`echo "$gop_phone" | awk '{if($1<0){printf "%.4f", -$1} else{printf "%.4f", $1}}' | sed 's/-//g'`
  
  
  echo "	Phone \"$phone\" detected in file \"$audio\" (second $startSeconds_phone to $endSeconds_phone) gave an overall GOP measure of $gop_phone"
  
  if [ "$found" = true ]; then
    info="$gop_phone MATCHED $info"
  else
    info="$gop_phone NOT_MATCHED $info"
  fi
  
  echo $info >> $info_outfile

  found=false
#  break

done < $infile
