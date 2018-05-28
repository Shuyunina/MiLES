#!/bin/bash
set -eu
################################################
#------- MidLatitude Evaluation System --------#
#------------------MiLES v0.6------------------#
#----------May 2018, P. Davini, ISAC-CNR-------#
#
#
#
#
################################################
#- ------user configurations variables---------#
################################################

#config name: create your own config file for your machine.
machine=adamsberg

#control flags to check which sections should be run
doeof=false #EOFs section
doblock=false #Blocking section 
doregime=false #Regimes section
domeand=true #Meandering section
dofigs=true #Do you want figures?

#control flag for re-run of MiLES if files already exists (not recommendend)
doforce=false

# exp identificator: it is important for the folder structure.
# if you have more than one runs (i.e. ensemble members) or experiments of the same model use
# this variable to distinguish them
# set also years 
year1_exp=1951
year2_exp=2005
dataset_exp="MPI-ESM-P"
#ens_list=$(seq -f e"%02g" 1 4 )
ens_list="r1"

# std_clim flag: this is used to choose which climatology compare with results
# or with a user specified one: standard climatology is ERAINTERIM 1979-2014
# if std_clim=1 ERAINTERIM 1979-2014 is used
# if std_clim=0 a MiLES-generated different climatology can be specified
std_clim=1

# only valid if std_clim=0
dataset_ref="NCEP"
ens_ref="NO"
year1_ref=1982
year2_ref=2016

# please specify one or more of the 4 standard seasons using 3 characters. 
# std_clim is supported for these 4 seasons only. 
# To analyse the whole year use "ALL"
# Beta: now you can define your own season putting together 3-character string for each consecutive month you 
# want to include, for example "Jan_Feb_Mar".
#seasons="DJF MAM SON JJA"
seasons="DJF"

# select which teleconnection pattern EOFs you want to compute
# "NAO": the 4 first  EOFs of North Atlantic, i.e. North Atlantic Oscillation as EOF1
# "AO" : the 4 first EOFs of Northern Hemispiere, i.e. Arctic Oscillation as EOF1 
# "lon1_lon2_lat1_lat2" : custom regions for EOFs: beware that std_clim will be set to 0!
teles="NAO"
#tele="-50_20_10_80"

# output file type for figures (pdf, png, eps)
# pdf are set by default
#output_file_type="pdf"

# map projection that is used for plotting
# "no": standard lon-lat plotting (fastest)
# "azequalarea": polar plot with equal area
# these are suggested: any other polar plot by "mapproj" R package are supported
# "azequalarea" set by default
#map_projection="azequalarea"

###############################################
#-------------Configuration scripts------------#
################################################

# machine dependent script (set above)
dataset=""; ens=""; expected_input_name="" #declared to avoid problems with set -u
. config/config_${machine}.sh

# this script controls some of the graphical parameters
# as plot resolutions and palettes
CFGSCRIPT=$PROGDIR/config/R_config.R

# select how many clusters for k-means over the North Atlantic
# NB: only 4 clusters supported so far.  
nclusters=4


################################################
##NO NEED TO TOUCHE BELOW THIS LINE#############
################################################

#check if you can compare run with std_clim=1
if  [ $std_clim -eq 1 ] ; then

	for tele in $teles ; do
        	if ! { [ "$tele" = NAO ] || [ "$tele" = AO ]; } ; then
        	        echo "Error: you cannot use non-standard EOFs region with std_clim=1"
                exit
        	fi
	done
	
	for season in $seasons ; do
        	if ! { [ "$season" = DJF ] || [ "$season" = MAM ] || [ "$season" = SON ] || [ "$season" = JJA ]; } ; then 
                	echo "Error: you cannot use non-standard seasons with std_clim=1"
                	exit
        	fi        
	done

fi

# if we are using standard climatology
if [[ ${std_clim} -eq 1 ]] ; then
	dataset_ref="ERAI_clim"
	year1_ref=1979
	year2_ref=2017
	REFDIR=$PROGDIR/clim
	exps=$dataset_exp
	ens_ref="NO"
else
        REFDIR=$FILESDIR
        exps=$(echo ${dataset_exp} ${dataset_ref})
fi


################################################
#-------------Computation----------------------#
################################################

#ensemble loop
for ens_exp in ${ens_list} ; do

# loop to produce data: on experiment and - if needed - reference
for exp in $exps ; do

	# select for experiment
	if [[ $exp == $dataset_exp ]] ; then
		year1=${year1_exp}; year2=${year2_exp}; ens=${ens_exp}
	fi

	# select for reference
	if [[ $exp == $dataset_ref ]] ; then
		if [ "${ens_ref}" == "mean" ] ; then continue ; fi
		if [ ${std_clim} -eq 1 ] ; then
 			echo "skip!"
		else
	        	year1=${year1_ref}; year2=${year2_ref}; ens=${ens_ref}
		fi
	fi
	
	echo $exp $year1 $year2

	#definition of the fullfile name
	ZDIR=$OUTPUTDIR/Z500/$exp
	mkdir -p $ZDIR
	if [ "$ens" == "NO" ] ; then
		z500filename=$ZDIR/Z500_${exp}_fullfile.nc
	else
		z500filename=$ZDIR/${ens}/Z500_${exp}_${ens}_fullfile.nc
	fi
	echo $z500filename

	#fullfile prepare
	time . $PROGDIR/script/z500_prepare.sh $exp $ens $year1 $year2 $z500filename $machine $doforce

	for season in $seasons ; do
		echo $season
        	
		# Rbased EOFs
		if $doeof ; then
			for tele in $teles ; do
        			time $Rscript "$PROGDIR/script/Rbased_eof_fast.R" $exp $ens $year1 $year2 $season $tele $z500filename $FILESDIR $PROGDIR $doforce
			done
		fi
		# blocking
		if $doblock ; then
			time $Rscript "$PROGDIR/script/block_fast.R" $exp $ens $year1 $year2 $season $z500filename $FILESDIR $PROGDIR $doforce
		fi

		# regimes
		if [[ $doregime == "true" ]] && [[ $season == DJF ]] ; then
			time $Rscript "$PROGDIR/script/regimes_fast.R" $exp $ens $year1 $year2 $season $z500filename $FILESDIR $PROGDIR $nclusters $doforce
		fi

		# meandering index
                if $domeand ; then
                        time $Rscript "$PROGDIR/script/meandering_fast.R" $exp $ens $year1 $year2 $season $z500filename $FILESDIR $PROGDIR $doforce
                fi
	done

done
################################################
#-----------------Figures----------------------#
################################################

if $dofigs ; then 
for season in $seasons ; do
	echo $season

	# EOFs figures
	if $doeof ; then
		for tele in $teles ; do
    			time $Rscript "$PROGDIR/script/Rbased_eof_figures.R" $dataset_exp $ens_exp $year1_exp $year2_exp $dataset_ref $ens_ref $year1_ref $year2_ref $season $FIGDIR $FILESDIR $REFDIR $CFGSCRIPT $PROGDIR $tele
		done
	fi

	# blocking figures
	if $doblock ; then
		time $Rscript "$PROGDIR/script/block_figures.R" $dataset_exp $ens_exp $year1_exp $year2_exp $dataset_ref $ens_ref $year1_ref $year2_ref $season $FIGDIR $FILESDIR $REFDIR $CFGSCRIPT $PROGDIR
	fi

	# regimes figures
	if [[ $doregime == "true" ]] && [[ $season == DJF ]] ; then
		time $Rscript "$PROGDIR/script/regimes_figures.R" $dataset_exp $ens_exp $year1_exp $year2_exp $dataset_ref $ens_ref $year1_ref $year2_ref $season $FIGDIR $FILESDIR $REFDIR $CFGSCRIPT $PROGDIR $nclusters
	fi
done
fi

done

################################################
#--------------Ensemble mean-------------------#
################################################

#check how many ensemble you have
aens=($ens_list); nens=${!ens[@]}
echo "Ensemble members are $ens_list"

#For blocking only
if [[ "${ens_list}" == "NO" ]] || [[ ${nens} -eq 0 ]] ; then
	echo "Only one ensemble member, exiting..."
else
	echo "Create ensemble mean... "
	#create loop using flags
	kinds=${kinds:-}
	[[ $doblock == true ]] && kinds="$kinds Block"   
	#[[ $doeof == true ]] && kinds="$kinds EOF" 
	#[[ $doregime == true ]] && kinds="$kinds Regimes" 
	echo $kinds

	for kind in $kinds ; do

		for season in ${seasons} ; do
		
			#case for file names
			case $kind in 
				Block) 	 
					MEANFILE=$FILESDIR/${dataset_exp}/mean/${kind}/${year1}_${year2}/$season/BlockClim_${dataset_exp}_mean_${year1}_${year2}_${season}.nc
					INFILES='$FILESDIR/${dataset_exp}/*/${kind}/${year1}_${year2}/$season/BlockClim_${dataset_exp}_*.nc'
					ARGS="$dataset_exp mean $year1_exp $year2_exp $dataset_ref $ens_ref $year1_ref $year2_ref $season $FIGDIR $FILESDIR $REFDIR $CFGSCRIPT $PROGDIR"
					SCRIPT=$PROGDIR/script/block_figures.R
				;;	
				#Regimes)
				#        MEANFILE=$FILESDIR/${dataset_exp}/mean/${kind}/${year1}_${year2}/$season/RegimesPattern_${dataset_exp}_mean_${year1}_${year2}_${season}.nc
				#        INFILES='$FILESDIR/${dataset_exp}/*/${kind}/${year1}_${year2}/$season/RegimesPattern_${dataset_exp}_*.nc'
				#        ARGS="$dataset_exp mean $year1_exp $year2_exp $dataset_ref $ens_ref $year1_ref $year2_ref $season $FIGDIR $FILESDIR $REFDIR $CFGSCRIPT $PROGDIR $nclusters"
				#        SCRIPT=$PROGDIR/script/regimes_figures.R
				#	;;
			esac
	
			#mean and plot
			MEANDIR=$(dirname $MEANFILE)
			rm -rf $MEANDIR; mkdir -p $MEANDIR
			$cdo4 timmean -cat $(eval echo $INFILES) $MEANFILE
			time $Rscript "$SCRIPT" $ARGS		
			
		done
	done
fi

rm -f $PROGDIR/Rplots.pdf #remove sporious file creation by R	

