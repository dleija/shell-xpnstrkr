#!/bin/sh
# Name: XpnsTrkr.sh
#######################################################################
#       DESCRIPTION
#       20161001 - DATE CREATED
#       20161001 - V1.0 - Depends on XpenseTracker (currently at v9.90) 
#                         by Silverware SW running on an iPhone with 
#                         Dropbox. Exported data is formatted for input
#                         into my Google SS Budget in the following 
#                         format : 
#                         Proprietor :: Date - Process - TransactionID\\ 
#                         :: Category - Description  :: Credit :: Debit
#                         In order for this script to extract relevant
#                         data, XpenseTracker app must be signed into
#                         Dropbox under All Logs >> Prefs >> EXPORT
#                         SERVICES - Check App for details. 
#                         ./XpnsTrkr.sh PATHTOXPORT reporttype (general|specific) \\
#                         The output format :
#                         Proprietor :: Date - Process - TransactionID\\ 
#                         :: Category - Description  :: Credit :: Debit
#                         The output will be divided into the following 
#                         3 sections:
#                         PAYCHECKS-INCOME
#                         DEBIT(from Bofa Visa Checking)
#                         CREDIT(from CitiBank MC Credit)
#       20161013 - V1.1 - Added full debit dollar count total. 
#       20161022 - V1.2 - Consolidated redundant extraction routines
#                         into dedicated function xtraction
#       20161102 - V1.3 - Added functions thismonth and lastmonth
#       20170105 - V1.4 - Addressed issue of CSV file containing fields with commas
#                         within fields. Account for Income correctly
#       20170310 - V1.5 - Added transaction summerization functionality with options 
#                         of summerizing all, open or closed transactions. At this
#                         time this only works for the current - this month.
#       20170311 - V1.6 - Added input controll allowing usder to specify the location
#                         of a specific report by including the report date in the 
#                         command in the format of YYYY.MM.Mmm.
#       20170320 - V1.7 - Changed conditional syntax from '=='(bash only) to '='(sh)
#                         as appropriate for the /bin/sh shell. Also changed the variable
#                         used from $filter to $catagory narrowing comparison operations.
#       20170401 - V1.8 - Implemented balance calculation and data filtering - Balance 
#                         calulation of income vs expense within the given period and
#                         inquiry type. Data filtering , it is now possible to parse 
#                         out filter for categories, institutions or any string found 
#                         in a transaction - all matching transactions are calculated 
#                         and printed.
#       20170610 - V1.9 - Added func_cleanup to remove temp files. Added input validation to 
#                         func_main - checks for existence of baseexportdir/desiredDate. 
#                         Exits with info on error or proceeds if successfull.
#       20170623 - V2.0 - Instead of fixing the first record of data at line 7, added 
#                         logic to find the line containing field names "^Date,Description",
#                         then begin processing records starting on the next/following line.
#                         This prevents processing errors caused by varying header line numbers
#                         usually caused when reports include notes or 're' fields. 
#       20170707 - V2.0 - Changed location of working raw files from individual extract folders
#                         to the baseextract/working. Simplifies multi-month and cleanup. See
#                         issue 08 for multi-month.
#
#       YYYYMMDD - VN.N - 
#
#       ISSUE - 01 - XpensTracker puts commas inside $ amount fields > 999. Those 
#                    fields are opened and closed with quotations. Neither quotes
#                    or commas WITHIN (only between) fields are handled correctly
#                    at this time.
#                  - STATUS : RESOLVED 20170105 
#       ISSUE - 02 - 2 word cities result in failure to add up charges and 
#                    <(standard_in) 1: syntax error> in to output 
#                  - STATUS : RESOLVED 20170105 
#       ISSUE - 03 - After adding summerization and attempting to allow specification                         
#                    of input transaction files, lost the ability to run previous
#                    months transactions, open, closed or all. 
#                  - STATUS : RESOLVED 20170311 
#       ISSUE - 04 - Found that if the comment field, used to mark a transaction as
#                    closed via string 'SSed', contains text with spaces the xtraction
#                    function fails calculations. At the moment under_scores and 
#                    comment-dashes can prevent this effect
#                  - STATUS : OPEN - but compensated
#       ISSUE - 05 - Modifying the 'Details' section of a log can affect the exported csv
#                    file, including header size. The script begins ingesting data at line 7, 
#                    a header of 6 or less will bypass valid transaction data, 8 or more 
#                    header lines will present non-transactional data resulting in faulty
#                    calculations.
#                  - STATUS : RESOLVED with version 2.0 
#       ISSUE - 06 - Since V1.8, unable to submit -sa|--summerize-all for period -tm|--this-month
#                  - STATUS : RESOLVED 20170402 - Swapped the parameter variable of subquery fr $3 
#                    to $4 and inqtype from $4 to $3
#       ISSUE - 07 - V1.9 cleans up temp files, however root password required. 
#                  - STATUS : OPEN minor - compensated - just preceed each run w/sudo
#       ISSUE - 08 - Multi-month
#                    Processes multiple months, but individually, not in an aggragated manner.
#                  - STATUS : Pending 20170707 
#
#       ISSUE - NN - Narrative
#                    Narrative
#                  - STATUS : RESOLVED YYYYMMDDG 
#  
#  ##############################################################                  
#                         
#   Function/Addon Ideas                          
#                         
#       Summerization - Summerize a processed/submitted report                             
#                     - Function added in v1.5
#      Data Filtering - Allow for any transactional data to be                         
#                         explicitly quieried, ie Institution, Date, Category,
#                         or PmntMthd.
#                     - Function added in v1.8
#             Balance 
#         Calculation - Display current balance based only on closed
#                         transactions through current date and projected
#                         balance based on current balance but inclusive
#                         of pending expenses and income.
#                     - Function added in v1.8
#      Flexible Input - Specify an input file other than this or last month
#                     - Function added in v1.6
#                         
#   Muli-period/month - Pending - see issue 08
#           reporting             
#                         
#######################################################################
###########################
# Script Variables Section
###########################
#    Binaries
###########################
which=/usr/bin/which
rm=`$which rm`
ls=`$which ls`
cut=`$which cut`
echo=`$which echo`
sudo=`$which sudo`
###########################
#    Script
###########################
procdate=`date +%Y%m%d`
baseextractpath=$1
period=$2
logfile=$baseextractpath/xpnstrkr.log

#### FUNCTION SECTION

func_inqfilterset ()
{
	case $inqtype in
		-sa |--summerizeall)
			inqtypefilter=","
			;;
		-so|--summerizeopen)
			inqtypefilter="-v SSed"  
			;;
		-sc|--summerizeclosed)
			inqtypefilter="SSed"  
			;;
		*)
			inqtypefilter="-v SSed"  
			;;
	esac
}

func_thismonth ()
{
	func_inqfilterset
	extractdate=`date +%Y.%m`.`date | awk '{print $2}'`      ## This format is better for ordered records
        func_main
	printf "\n"
	func_tmusage
	printf "\n"
	func_noteusage
	printf "\n"
}

func_lastmonth ()
{
        inqtype='-sa'
        func_inqfilterset
	extractdate=`date --date=-1month +%Y.%m`.`date --date=-1month | awk '{print $2}'`      ## This format is better for ordered records
        func_main
        printf "\n"
        func_lmusage
        printf "\n"
        func_noteusage
        printf "\n"
}

func_othermonth () {
	inqtype='-sa'
	func_inqfilterset
	if [ ! $extractdate ] ; then
		printf "\n"
		func_omusage
		printf "\n"
		exit 1
	else
        	func_main
		printf "\n"
		func_omusage
		printf "\n"
		func_noteusage
		printf "\n"
	fi
}

func_monthset () {
#	echo $year.$Nmon.$Amon
	Nmon=$(expr $Nmon + 1)
	Nmon=$(printf %02d $Nmon)
	case $Nmon in 
		01) Amon="Jan" ;;
		02) Amon="Feb" ;;
		03) Amon="Mar" ;;
		04) Amon="Apr" ;;
		05) Amon="May" ;;
		06) Amon="Jun" ;;
		07) Amon="Jul" ;;
		08) Amon="Aug" ;;
		09) Amon="Sep" ;;
		10) Amon="Oct" ;;
		11) Amon="Nov" ;;
		12) Amon="Dec" ;;
		esac
}

func_multimonth () {

#date --date=-1year+1month +%Y.%m.%b
#2016.07.Jul

#date +%Y.%m
#2017.06

	inqtype='-sa'
	func_inqfilterset

	if [ ! $fextractdate ] ; then
		printf "\n"
		func_mmusage
		printf "\n"
		exit 1
	else
		iyear=`$echo $iextractdate | $cut -d. -f1`
		iNmon=`$echo $iextractdate | $cut -d. -f2`
		iAmon=`$echo $iextractdate | $cut -d. -f3`

		year=$iyear
		Nmon=$iNmon
		Amon=$iAmon

		extractdate=$iyear.$Nmon.$Amon

		fyear=`$echo $fextractdate | $cut -d. -f1`
		fNmon=`$echo $fextractdate | $cut -d. -f2`
		fAmon=`$echo $fextractdate | $cut -d. -f3`

		if [ $year -lt $fyear ] ; then 
			while [ $Nmon -le 12  ] ; do
 			 	extractdate=$year.$Nmon.$Amon
				func_monthset
 				func_main
			done 
			year=$(expr $year + 1)
			Nmon=01
			while [ $Nmon -le $fNmon  ] ; do
 			 	extractdate=$year.$Nmon.$Amon
				func_monthset
 				func_main
			done 
		else
			while [ $Nmon -le $fNmon  ] ; do
 			 	extractdate=$year.$Nmon.$Amon
				func_monthset
 				func_main
			done 
		fi
	fi
}

func_main ()
{
	if [ -d $baseextractpath/$extractdate ] ; then
	 	extractpath=$baseextractpath/$extractdate
		xport=`ls $extractpath/*.csv | tail -n1`
		echo ""
		echo "Extracting from $extractdate"
		if [ $subqueury ] ; then
			func_subqueury
		else
			func_defqueury
		fi
	else
		message="$procdate - $baseextractpath/$extractdate not found !! Check your paths and try again"
		echo ""
		func_report
		echo ""
		func_defusage	
	fi

# 	balance=$(echo "scale=2;$inctotal-$exptotal" |bc)
#	func_summary

#       Debugging Section Start
#	echo BastExtractPath $baseextractpath
#	echo Period $period
#	echo SubQueury $subqueury
#	echo InqType $inqtype
#       Debugging Section End

}

func_subqueury ()
{
	filter=$subqueury
	filterd=$filter
	echo ""
	echo "Transactions for $filter : "
	echo ""
	func_xtraction
	summaryelement1=$filterd 
	summaryelement2=$extractdate 
	summaryelement3=$transactioncount
	summaryelement4=$subtotal
	echo " ---------------------------------------------------------------------------------"
	echo "|     Summary of $summaryelement1 ($summaryelement3 transactions) for $summaryelement2 "
	echo "| "
	echo "|                                                : \$$summaryelement4" 
	echo "|                                                : ==============================="                                          
	echo "|                                                : ==============================="                                          
	echo " ----------------------------------------------------------------------------------"
	echo ""
	echo ""
	func_cleanup
}

func_defqueury ()
{
	filter=BofA.Debit
	filterd=$filter
	echo ""
	echo "$filter - charges from BofA Visa Debit : "
	echo ""
	func_xtraction

	filter=BofA.Online
	filterd=$filter
	echo ""
	echo "$filter - charges from BofA Visa Online : "
	echo ""
	func_xtraction

	filter=CBMC.Credit
	filterd=$filter
	echo ""
	echo "$filter - charges from CitiBank MC Credit  : "
	echo ""
	func_xtraction
	
	filter=CBMC.Online
	filterd=$filter
	echo ""
	echo "$filter - charges from CitiBank MC Online  : "
	echo ""
	func_xtraction

	filter=Bills
	filterd=$filter
	echo ""
	echo "$filter - paid from BofA or CBMC : "
	echo ""
	func_xtraction
	
	filter=' -v Income '
	filterd='AllExpenses '
	echo ""
	echo "All Expenses : "
	echo ""
	func_xtraction
 	exptotal=$subtotal
 	exptranscount=$transactioncount

	filter=Income
	filterd=$filter
	echo ""
	echo "$filter - deposit(s) to BofA Checking : "
	echo ""
	func_xtraction
 	inctotal=$subtotal
 	inctranscount=$transactioncount

	totaltransactioncount=$(echo "scale=2;$exptranscount+$inctranscount" |bc)
	summaryelement1=ALL 
	summaryelement2=$extractdate 
	summaryelement3=$totaltransactioncount
	
 	balance=$(echo "scale=2;$inctotal-$exptotal" |bc)

	echo " ----------------------------------------------------------------------------------"
	echo "|     Summary of $summaryelement1 ($summaryelement3) transaction(s) reconciled for $summaryelement2"
	echo "| "
	echo "|                                                :  Income  - Expenses =  Balance "
	echo "|                                                :"                                          
	echo "|                                                : \$$inctotal - \$$exptotal = \$$balance" 
	echo "|                                                : ==============================="                                          
	echo "|                                                : ==============================="                                          
	echo " ----------------------------------------------------------------------------------"
	echo ""
	echo ""

	func_cleanup
}

func_xtraction ()
{
	transactioncount=0
	subtotal=0
	fieldname=`grep -n "^Date,Descr" $xport | cut -d: -f1`     # Issue 08 - Resolved V2.0 - Flexibly find the first line of interesting data vs fixing 
	firstrecord=$(echo "scale=1;$fieldname+1" |bc)             #   it to a specific line number which can change based on various export parameters

	# Need to pre-process the Xpens output which includes commas inside feilds - the following 3 lines clean that junk up
 	tail -n +$firstrecord $xport | grep -v "\"" | sed -e 's/-//g' | sed -e 's/ //g' > $baseextractpath/working/$procdate.raw
 	tail -n +$firstrecord $xport | grep '\"' | awk 'BEGIN {FS="\""} ; {print $1" "$3}' > $baseextractpath/working/$procdate-0-1-3.raw
 	tail -n +$firstrecord $xport | grep '\"' | awk 'BEGIN {FS="\""} ; {print $2}' | sed -e 's/,//g' > $baseextractpath/working/$procdate-0-2.raw
        awk 'FNR==NR { a[FNR""] = $0; next } { print a[FNR""],  $0 }' $baseextractpath/working/$procdate-0-1-3.raw $baseextractpath/working/$procdate-0-2.raw | awk '{print $1" "$3" "$2}' >> $baseextractpath/working/$procdate.raw
 	extract=$baseextractpath/working/$procdate.raw

	printf "%5s\t%10s\t%23s\t%2s\t%8s\t%8s\n" Institution Date Category Credit Cost/Debit PmntMthd
	for line in `cat $extract | grep $filter | grep $inqtypefilter | grep -v '^$' | sed -e 's/ //g' | sed -e 's/-//g'` ; do 
		transactioncount=$(expr $transactioncount + 1)
		merchant=`echo $line | cut -d',' -s -f6 `
		pmntmthd=`echo $line | cut -d',' -s -f5 `
		category=`echo $line | cut -d',' -s -f4 `
		xdate=`   echo $line | cut -d',' -s -f1 `
		# Recognise and process Income as addition vs subtraction
		if [ $category != Income ] ; then
			xcredit='0'
			debit=`   echo $line | cut -d',' -s -f3 `
			subtotal=$(echo "scale=2;$debit+$subtotal" |bc)
		else
			debit='0'
			xcredit=` echo $line | cut -d',' -s -f3 `
			subtotal=$(echo "scale=2;$xcredit+$subtotal" |bc)
		fi
		printf "%5s\t%10s\t%23s\t%2s\t%8s\t%8s\n" $merchant $xdate $category $xcredit $debit $pmntmthd
	done
	echo ""
	message="$procdate - $filterd transactions processed : $transactioncount from $xport for $extractdate totaling \$ $subtotal "
	func_report
        printf "\n"
}

func_cleanup ()
{
# 	cleaned=`$rm -v $baseextractpath/working/$procdate.raw`
 	message="$procdate - $cleaned"
 	func_report
# 	cleaned=`$rm -v $baseextractpath/working/$procdate-0-2.raw`
 	message="$procdate - $cleaned"
 	func_report
# 	cleaned=`$rm -v $baseextractpath/working/$procdate-0-1-3.raw`
 	message="$procdate - $cleaned"
	func_report
	cleaned=''
}

func_function04 ()
{
	echo function04
	message=$input4
	func_report
}

func_report ()
{
        echo $message 
        echo $message >> $logfile
}

func_usage ()
{
	printf "\n"
	printf "XPenseTrackerApp  : DO NOT put SPACES in the 'Notes' comment area. Spaces interfere with record parsing and \n"
        printf "                           result in catagory calculation errors. Replace spaces with underscores, dashes or \n"
        printf "                           avoid additional commentary\n"
	printf "                    Be careful in the Details section of each log. Currently we expect the 7th line in the csv\n"
	printf "                           export to be the first transaction. Adjusting Detail fields may alter this and result\n"
	printf "                           in faulty output\n"
	printf "\n"
	printf "\n"
	func_defusage
	printf "\n"
	func_omusage
	printf "\n"
	func_mmusage
	printf "\n"
	func_lmusage
	printf "\n"
	printf "\n"
	func_tmusage
	printf "\n"
	func_subqueuryusage 
	printf "\n"
	func_noteusage
	printf "\n"
	printf "\n"
}

func_defusage ()
{
	printf "  Default Usage   : XpnsTrkr.sh baseexportdir period[--thismonth|-tm(default) subqueury inqtype[--summerizeopen|-so(default)]\n"
	printf "                    The default queuery returns the following XpensTracker categories: \n"
	printf "                         BofA.Debit, BofA.Online, CBMC.Credit, CBMC.Online, \n"
	printf "                         Bills, ' -v Income ' (all expenses) and Income\n"
	printf "                     To restrict the data returned to a specific item, enter the string after the period\n"
}

func_lmusage ()
{
	printf "Last Month Usage  : XpnsTrkr.sh baseexportdir period[--lastmonth|-lm] (optional - subquery)\n"
	printf "         example  :  XpensTrkr.sh /home/dleija/Dropbox/Apps/XpenseTracker -lm (CitiBank) \n"
}

func_tmusage ()
{
	printf "This Month Usage  : XpnsTrkr.sh baseexportdir period[--thismonth|-tm (optional - subquery) inqtype[(-sa|--summerizeall)|(-so|summerizeopen(DEFAULT))|(-sc|--summerizeclosed)]\n"
        printf "         example  :  XpensTrkr.sh /home/dleija/Dropbox/Apps/XpenseTracker --thismonth --summerizeall ATT\n"
        printf "         example  :  XpensTrkr.sh /home/dleija/Dropbox/Apps/XpenseTracker -tm -sa Bills\n"
        printf "         example  :  XpensTrkr.sh /home/dleija/Dropbox/Apps/XpenseTracker -tm (defaults to summerizeopen if blank)\n"
}

func_mmusage ()
{
	printf "Multi Month Usage : XpnsTrkr.sh baseexportdir period[--multimonth|-mm] periodRange(initialDesiredDate finalDesiredDate(both inform YYYY.DD.Mmm) (Optional - Subquery)\n"
        printf "          example :  XpensTrkr.sh /home/dleija/Dropbox/Apps/XpenseTracker -mm 2017.01.Jan 2017.03.Mar (Income)\n"
}

func_omusage ()
{
	printf "Other Month Usage : XpnsTrkr.sh baseexportdir period[--othermonth|-om] desiredDate(inform YYYY.DD.Mmm) (Optional - Subquery)\n"
        printf "          example :  XpensTrkr.sh /home/dleija/Dropbox/Apps/XpenseTracker -om 2017.03.Mar \n"
}

func_subqueuryusage ()
{
	printf "Sub queury Usage  : XpnsTrkr.sh baseexportdir period (if om - desiredDate (inqtype - if period = tm)) subquery \n"
        printf "          example :  XpensTrkr.sh /home/dleija/Dropbox/Apps/XpenseTracker -om 2017.03.Mar GreenMountain\n"
        printf "          example :  XpensTrkr.sh /home/dleija/Dropbox/Apps/XpenseTracker -tm -sc Meals\n"
        printf "          example :  XpensTrkr.sh /home/dleija/Dropbox/Apps/XpenseTracker -lm Fuel\n"
}

func_noteusage ()
{
	printf "           Note   : Optional -inqtype- available only for --thismonth period - \n"
	printf "                              for periods --lastmonth and --othermonth the inqtype \n"
	printf "                              is fixed at --summerizeall -sa \n"
}


if [ $period ] ; then 
	case $period in 
	        --thismonth|-tm)
			subqueury=$4
			inqtype=$3
	                func_thismonth
	                exit 0
	        ;;
	        --lastmonth|-lm)
			subqueury=$3
	                func_lastmonth
	                exit 0
	        ;;
	        --othermonth|-om)
			extractdate=$3
			subqueury=$4
	                func_othermonth
	                exit 0
	        ;;
	        --multimonth|-mm)
			iextractdate=$3
			fextractdate=$4
			subqueury=$5
	                func_multimonth
	                exit 0
	        ;;
	        --function04|-f4)
	                func_function04
	                exit 0
	        ;;
	        *)
	                func_usage
	                exit 1
	        ;;
	esac
else 
                func_usage
                exit 1
fi
