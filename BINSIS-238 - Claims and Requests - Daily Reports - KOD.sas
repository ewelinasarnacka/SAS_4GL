
/*Ewelina Cichocka*/
/*2012-12-28*/

options ls=150 pagesize=30;
%let today = %sysfunc(date(),yymmdd10.);

%macro change_datetime_format(table,variable);
data &table;
set &table;
	&variable=datepart(&variable);
	format &variable yymmdd10.;
run;
%mend;

%let nazwa_raportu=BINSIS-238;
%put &nazwa_raportu;

%check_for_database(n=2,baza1=in03prd.policy, baza2=arc01prd.claim_request_data, nazwa_raportu=&nazwa_raportu);

data daty;
	 format date_start yymmdd10. date_end yymmdd10. date_last yymmdd10.;
	 date_start = intnx('year',today(),-1,'begin');
     date_end =intnx('day',today(),-1,'end');
	 date_last = intnx('month',today(),0,'end');
run;

proc sql print ;
select distinct date_end into:date_end
from daty;
quit;
%PUT &date_end;
proc sql print ;
select distinct year(date_end) as rok into:rok
from daty;
quit;
%PUT &rok;
proc sql print ;
select distinct month(date_end) as miesiac into:miesiac
from daty;
quit;
%PUT &miesiac;
proc sql print ;
select distinct day(date_end) as dzien into:dzien
from daty;
quit;
%PUT &dzien;

proc sql print ;
select distinct day(date_last) into:date_last
from daty;
quit;
%PUT &date_last;

proc sql print ;
select distinct day(today()) into:date_dzis
from daty;
quit;
%PUT &date_dzis;


/***************************************************************************************************************************************************************/
/* Raport na bazie tabeli pomocniczej CLAIM_REQUEST_DATA */
/***************************************************************************************************************************************************************/

data claim_request;
set arc01prd.claim_request_data;
run;
%change_datetime_format(claim_request,pay_date_min);
%change_datetime_format(claim_request,min_restore_date);
%change_datetime_format(claim_request,min_regresses_date);
%change_datetime_format(claim_request,registration_date_c);
%change_datetime_format(claim_request,last_change_date);
%change_datetime_format(claim_request,confirm_date_min);
%change_datetime_format(claim_request,event_date);
%change_datetime_format(claim_request,registration_date_cr);
%change_datetime_format(claim_request,refuse_date);
%change_datetime_format(claim_request,first_evaluation_date);
%change_datetime_format(claim_request,report_date);

%biblioteki();

data  claim_request;
set claim_request;
if LIKWIDACJA_BEZPO_REDNIA = . then LIKWIDACJA_BEZPO_REDNIA=0;
if s_d=. then s_d=0;
registration_month = catt(year(registration_date_cr), '/', month(registration_date_cr));
confirm_month = catt(year(confirm_date_min), '/', month(confirm_date_min));
pay_month = catt(year(pay_date_min), '/', month(pay_date_min));
run;


proc sql print ;
select distinct report_date into:report_date
from claim_request;
quit;
%PUT &report_date;

proc sql;
create table injured_object_type as 
select unique catt(claim_id,'_',request_id) as claim, count(unique injured_object_type) as ile
  from in03prd.claim_objects
 group by catt(claim_id, request_id)
having count(unique injured_object_type) = 1
 order by catt(claim_id,'_',request_id)
;quit;
proc sql;
create table claim_request as 
select cp.* ,min_reserve_obj, object_name as injured_object_type,
case when icp.request_id_ref is null then 0 else 1 end as czy_kontynuowana,
case when cp.claim_state=10 then cp.refuse_date else cp.confirm_date_min end as TARGET_TIME format yymmdd10.,
case when cp.cover_type='MTPL' and time_to_confirm<=20 then 1
     when cp.insr_type=3001 and time_to_confirm<=17 then 1
     when cp.cover_type like 'CSC%' and time_to_confirm<=10 then 1 
	when  (cp.cover_type='PA_MOTOR' or cp.cover_type='PA') and time_to_confirm<=14 then 1
		else 0 end as IN_TARGET_TIME,
		case when cob.claim_id is not null then 1 else 0 end as czy_obiekt_Reserv_inic
  from claim_request cp
	   left join (select unique claim_id, request_id, injured_object_type 
                    from in03prd.claim_objects
                   where catt(claim_id,'_',request_id) in (select claim from injured_object_type)) co on co.claim_id=cp.claim_id and co.request_id=cp.request_id 
	   left join in03prd.CFG_GENCLAIM_INJURED_OBJECTS ho on ho.object_type=co.injured_object_type and ho.insr_type = cp.insr_type
	   left join in03prd.ugpl_insur_claim_params icp on icp.claim_id=cp.claim_id and icp.request_id=cp.request_id
	   left join (select distinct claim_id, request_id from arc01prd.claim_object_data where expert_id = . )as cob on cob.claim_id=cp.claim_id and  cob.request_id=cp.request_id
	   left join (select distinct claim_id, request_id, min(reserve_obj) as min_reserve_obj from arc01prd.claim_object_data group by claim_id, request_id )as cob2 on cob2.claim_id=cp.claim_id and  cob2.request_id=cp.request_id
order by claim_id, request_id
;quit;
/*data claim_request;*/
/*set claim_request;*/
/*format rok_do_eksportu 10.;*/
/*if &date_dzis. = 1 or &date_dzis. = &date_last. then rok_do_eksportu = 2011;*/
/*else rok_do_eksportu = year(today());*/
/*run;*/
data claim_request; 
format for_analysis 2.;
set claim_request;
if target_time=. or claim_state=11  then FOR_ANALYSIS=0;
else if cover_type in ('ASS_MINI','ASS_MED','ASS_PREM') then FOR_ANALYSIS=0;
else if czy_kontynuowana=1 or solve_way_desc='Complaint' then FOR_ANALYSIS=0; 
else if S_D=1 then FOR_ANALYSIS=0;
else if cover_type in ('CSC_THT_P','CSC_THT_T') then FOR_ANALYSIS=0;
else if zagraniczna=1 then FOR_ANALYSIS=0;
else if LIKWIDACJA_BEZPO_REDNIA=1 then FOR_ANALYSIS=0;
else if BI=1 then FOR_ANALYSIS=0;
else FOR_ANALYSIS=1;
where registration_date_cr >= intnx('year', today()-1 , -1, 's');
run;

/*proc sql;*/
/*create table test as*/
/*select max(registration_date_cr) fromat yymmdd10.*/
/*  from claim_request2;*/
/*quit;*/

proc sql;
create table claim_request_export as 
select case when cover_type like 'CSC%' then 'CASCO' 
			when insr_type=3001 then 'HOME' 
		else cover_type end as cover_type2, catt(claim_id,'_',request_id) as claim_no,
		case when insr_type=1001 then 'MOTOR'
			 when insr_type =3001 then 'HOME'
			 when insr_type =4001 then 'SME'
			 when insr_type =1201 then 'KOMIS'
			 when insr_type =2101 then 'NNW' end as insr_type_desc,
substr(put(pay_date_min,yymmdd10.),1,10) as pay_date_min,
substr(put(min_restore_date,yymmdd10.),1,10) as min_restore_date,
substr(put(min_regresses_date,yymmdd10.),1,10) as min_regresses_date,
substr(put(registration_date_c,yymmdd10.),1,10) as registration_date_c,
substr(put(last_change_date,yymmdd10.),1,10) as last_change_date,
substr(put(confirm_date_min,yymmdd10.),1,10) as confirm_date_min,
substr(put(event_date,yymmdd10.),1,10) as event_date,
substr(put(registration_date_cr,yymmdd10.),1,10) as registration_date_cr,
substr(put(refuse_date,yymmdd10.),1,10) as refuse_date,
substr(put(first_evaluation_date,yymmdd10.),1,10) as first_evaluation_date,
substr(put(report_date,yymmdd10.),1,10) as report_date,
floor(reserve_obj)+1 as reserve_obj_zaokr, 
/*substr(*/put(target_time,yymmd.)/*,1,10)*/ as targent_month,
substr(put(target_time,yymmdd10.),1,10) as target_time,

c.*
from claim_request c
;
quit;
/***************************************************************************************************************************************************************************/
/*Dane - obiekt*/
/***************************************************************************************************************************************************************************/




/***************************************************************************************************************************************************************************/
libname zapis 'P:\DEP\Actuarial\05 REPORTS - OPERATIONAL\04 Claims\BINSIS-238 - Daily Reports';
data zapis.dane_238;
set claim_request_export;
run;
/***************************************************************************************************************************************************************************/
/*EKSPORT DO MS EXCEL*/
/***************************************************************************************************************************************************************************/
options noxsync noxwait xmin;
filename sas2xls dde 'excel|system';

%macro otworz_excela(plik);
            data _null_;
            length fid rc start stop time 8;
            fid=fopen("&plik",'s');
            if (fid le 0) then 
            do;
                  rc=system('start excel');
                  start=datetime();
                  stop=start+10;
                  do while (fid le 0);
                        fid=fopen("&plik",'s');
                        time=datetime();
                        if (time ge stop) then fid=1;
                  end;
            end;
            rc=fclose(fid);
      run;      
%mend;
%otworz_excela();
data _null_;
file sas2xls;
	put '[close("Zeszyt1")]';
	put '[open("P:\DEP\actuarial\05 REPORTS - OPERATIONAL\04 Claims\BINSIS-238 - Daily Reports\BINSIS_238_daily_reports_FORMAT.xlsm")]';
run;

data _null_;
file sas2xls;
	put '[error(false)]';
	put '[RUN("Odswiez")]';
run; 


data _null_;
file sas2xls;
	put '[error(false)]';
	put %unquote(%bquote('[save.as("P:\DEP\actuarial\05 REPORTS - OPERATIONAL\04 Claims\BINSIS-238 - Daily Reports\RAPORTY\C3_BINSIS-238 - CLAIMS - Daily Report &date_end..xlsm")]'));
run;

data _null_;
file sas2xls;
	put '[quit()]';
run;
data _null_;
x=sleep(15);
run;
data _null_;
x %str(%'C:\Program Files\7-Zip\7z.EXE%' u -tzip 
"P:\DEP\actuarial\05 REPORTS - OPERATIONAL\04 Claims\BINSIS-238 - Daily Reports\RAPORTY\C3_BINSIS-238 - CLAIMS - Daily Report &date_end..zip" 
"P:\DEP\actuarial\05 REPORTS - OPERATIONAL\04 Claims\BINSIS-238 - Daily Reports\RAPORTY\C3_BINSIS-238 - CLAIMS - Daily Report &date_end..xlsm" -r );
run; 
data _null_;
x=sleep(15);
run;

FILENAME MyFile "P:\DEP\actuarial\05 REPORTS - OPERATIONAL\04 Claims\BINSIS-238 - Daily Reports\RAPORTY\C3_BINSIS-238 - CLAIMS - Daily Report &date_end..xlsm" ;
  DATA _NULL_ ;
    rc = FDELETE('MyFile') ;
  RUN ;
FILENAME MyFile CLEAR ;






/***************************************************************************************************************************************************************************/
/*END EKSPORT DO MS EXCEL*/
/***************************************************************************************************************************************************************************/



/**/
/**/
/*PROC FORMAT;*/
/*VALUE open_time_OC*/
/*. = "orange"*/
/*LOW - 7 = "#EBF2E6"*/
/*8 - 15 = "orange"*/
/*16- HIGH = "lightRED";*/
/*RUN;*/
/*PROC FORMAT;*/
/*VALUE open_time_AC*/
/*. = "orange"*/
/*LOW - 4 = "#EBF2E6"*/
/*5 - 8 = "orange"*/
/*9 - HIGH = "lightRED";*/
/*RUN;*/
/**/
/*%MACRO num_obs(_dsn_, num_obs) ;*/
/*%GLOBAL _numobs_ ;*/
/*DATA _NULL_ ;*/
/*IF 0 THEN SET &_dsn_ NOBS=how_many ;*/
/*CALL SYMPUT("_numobs_", LEFT(PUT(how_many,10.))) ;*/
/*STOP ;*/
/*RUN ;*/
/*%IF %EVAL(&_numobs_) EQ 0 %THEN %DO ;*/
/*proc sql ;*/
/*alter table &_dsn_*/
/*add num_obs char(20);*/
/*insert into &_dsn_*/
/*set num_obs = "No observations" ;*/
/*select * from &_dsn_;*/
/*run;*/
/*%END ;*/
/*%MEND num_obs ;*/
/*%num_obs (claim_request, num_obs);*/
/**/
/*ods listing close;*/
/*ODS tagsets.excelxp file="P:\DEP\Actuarial\05 REPORTS - OPERATIONAL\04 Claims\BINSIS-238 - Daily Reports\Reports\BINSIS-238 - Claims & Requests - Daily Reports &today..xls"*/
/*                   style=MeadowPrinter */
/*                   options(embedded_titles='yes' embedded_footnotes='yes' sheet_label=' '  sheet_name='Claim Request Report' frozen_headers='7'*/
/*                           frozen_rowheaders='2' sheet_interval='bygroup' autofilter='all'  )*/
/*;*/
/*ods escapechar='^';*/
/*PROC REPORT DATA=claim_request nowd headline headskip split='*' style(header)={cellheight=.5in};*/
/*column ( ' ' insr_type policy_id)*/
/*       ( 'CLAIM' claim_id claim_type event_date registration_date_c)*/
/*       ( 'REQUEST' request_id claim_state claim_type_cr cover_type injured_object_type notyfikator likwidator_m likwidator_t solve_way_desc ufg LIKWIDACJA_BEZPO_REDNIA S_D)*/
/*       ( 'REQUESTS - DATES' registration_date_cr registration_month refuse_date last_change_date confirm_date_min confirm_month pay_date_min pay_month)*/
/*       ( 'REQUESTS - RESERVES' reserve_obj reserve_exp )*/
/*	   ( 'REQUESTS - PAYMENTS' indem_confirm expense_confirm )*/
/*       ( 'REQUESTS - TIMES' time  time_to_pay)*/
/*       ( 'REQUESTS - STATUS' state state_confirm state_paid);*/
/*where request_id <> .;*/
/*define insr_tpe         /display 'Insr Type'  style(column)={cellwidth=1.0in};*/
/*define policy_id        /display 'Policy ID' style={tagattr="format:######"} width=2;*/
/*define claim_id         /display 'Claim ID'  style(column)={cellwidth=1.0in};*/
/*define claim_type       /display 'Claim Type'  style(column)={cellwidth=1.5in};*/
/*define event_date       /display 'Event Date'  style(column)={cellwidth=1.5in};*/
/*define registration_date_c  /display 'Registration Date*claim'  style(column)={cellwidth=1.5in};*/
/*define request_id           /display 'Request ID'  style(column)={cellwidth=1.0in};*/
/*define claim_state          /display 'Claim State'  style(column)={cellwidth=1.5in};*/
/*define claim_type_cr        /display 'Claim Type'  style(column)={cellwidth=1.5in};*/
/*define cover_type           /display 'Cover Type'  style(column)={cellwidth=1.0in};*/
/*define injured_object_type  /display 'Injured*Object Type'  style(column)={cellwidth=1.0in};*/
/*define notyfikator       /display 'Registrants'  style(column)={cellwidth=1.5in};*/
/*define likwidator_m      /display 'Handler'  style(column)={cellwidth=1.5in};*/
/*define likwidator_t      /display 'Technical Handler'  style(column)={cellwidth=1.5in};*/
/*define solve_way_desc    /display 'Solve Way'  style(column)={cellwidth=1.5in};*/
/*define ufg               /display 'UFG'  style(column)={cellwidth=1.0in};*/
/*define S_D			     /display 'S¹d'  style(column)={cellwidth=1.0in};*/
/*define LIKWIDACJA_BEZPO_REDNIA      /display 'BLS'  style(column)={cellwidth=1.0in};*/
/*define registration_date_cr  /display 'Registration date*request'  style(column)={cellwidth=1.5in};*/
/*define registration_month    /display 'Registration month*request'  style(column)={cellwidth=1.5in};*/
/*define refuse_date       /display 'Refuse Date'  style(column)={cellwidth=1.5in};*/
/*define last_change_date  /display 'Last Change Date'  style(column)={cellwidth=1.0in};*/
/*define confirm_date_min  /display 'First Confirm Date*(for indemnity)'  style(column)={cellwidth=1.5in};*/
/*define confirm_month     /display 'First Confirm Month*(for indemnity)'  style(column)={cellwidth=1.5in};*/
/*define pay_date_min      /display 'First Paid Date*(for indemnity)'  style(column)={cellwidth=1.5in};*/
/*define pay_month         /display 'First Paid Month*(for indemnity)'  style(column)={cellwidth=1.5in};*/
/*define reserve_obj       /analysis sum format=10.2   'Reserve OBJ'   style(column)={cellwidth=1.0in};*/
/*define reserve_exp       /analysis sum format=10.2   'Reserve EXP'  style(column)={cellwidth=1.0in};*/
/*define indem_confirm     /analysis sum format=10.2   'Indemnity*Confirm'   style(column)={cellwidth=1.5in};*/
/*define expense_confirm   /analysis sum format=10.2   'Expenses*Confirm'  style(column)={cellwidth=1.5in};*/
/*define time              /display format=10.2  'Open Time' style(column)={cellwidth=1.5in};*/
/*define time_to_pay       /analysis mean format=10.2  'Time to first paid*(for indemnity)'  style(column)={cellwidth=1.5in};*/
/*define state             /display 'State'  style(column)={cellwidth=1.5in};*/
/*define state_confirm     /display 'Confirm State*(for indemnity)'  style(column)={cellwidth=1.5in};*/
/*define state_paid        /display 'Paid State*(for indemnity)'  style(column)={cellwidth=1.5in};*/
/*rbreak after/summarize dol dul style=[font_weight=bold color=green fontstyle=roman font_size=2 background=#EBF2E6] ;*/
/*COMPUTE policy_id;IF _break_='_RBREAK_' THEN CALL DEFINE('Policy_ID','style','style=[pretext="Sum"]'); ENDCOMP;*/
/*compute time; if cover_type = 'MTPL' then call define ('time','style','style=[BACKGROUND=open_time_oc.]');*/
/*         else if cover_type = 'CSC_ACC_V' or  cover_type = 'CSC_FLX_V' or cover_type = 'CSC_THT_P' or cover_type = 'CSC_THT_T' */
/*              or cover_type = 'CSC_ACC_RB' or cover_type = 'CSC_FLX_RB' or cover_type = 'CSC_ACC_RN' or cover_type = 'CSC_FLX_RN'*/
/*                                     then call define ('time','style','style=[BACKGROUND=open_time_ac.]'); ; endcomp; */
/*title1 j=c bold color=black  height=12pt font=Arial bcolor=white '   ';*/
/*title2 j=c bold color=green  height=13pt font=Arial bcolor=white 'BINSIS-238 - Claims & Requests - Daily Reports';*/
/*title3 j=c bold color=orange height=13pt font=Arial bcolor=white 'All Requests';*/
/*title4 j=c bold color=black  height=12pt font=Arial bcolor=white 'Report Date:' %sysfunc(date(),DDMMYY10.);*/
/*RUN;*/
/*ods tagsets.excelxp close;*/
/*ods listing;*/

/*options noxsync noxwait xmin;
filename sas2xls dde 'excel|system';
%macro otworz_excela(plik);
            data _null_;
            length fid rc start stop time 8;
            fid=fopen("&plik",'s');
            if (fid le 0) then do;
                  rc=system('start excel');
                  start=datetime();
                  stop=start+10;
                  do while (fid le 0);
                        fid=fopen("&plik",'s');
                        time=datetime();
                        if (time ge stop) then fid=1;
                  end;
            end;
            rc=fclose(fid);
      run;      
%mend;
%otworz_excela();

data _null_;
file sas2xls;
      put '[close("Zeszyt1")]';
      put '[error(false)]';
      put %unquote(%bquote('[open("P:\DEP\Actuarial\05 REPORTS - OPERATIONAL\04 Claims\BINSIS-238 - Daily Reports\MIS - Claims & Requests - Daily Reports &today..xls")]'));
      put %unquote(%bquote('[save.as("P:\DEP\Actuarial\05 REPORTS - OPERATIONAL\04 Claims\BINSIS-238 - Daily Reports\MIS - Claims & Requests - Daily Reports &today..xlsx",51)]'));
      put '[close("P:\DEP\Actuarial\05 REPORTS - OPERATIONAL\04 Claims\BINSIS-238 - Daily Reports\MIS - Claims & Requests - Daily Reports &today..xlsx")]';
run;*/

/*FILENAME MyFile "P:\DEP\Actuarial\05 REPORTS - OPERATIONAL\04 Claims\BINSIS-238 - Daily Reports\MIS - Claims & Requests - Daily Reports &today..xlsx";
  DATA _NULL_ ;
    rc = FDELETE('MyFile') ;
  RUN ;
FILENAME MyFile CLEAR ;*/

/***************************************************************************************************************************************************************************/
/*WYS£ANIE NA EMAIL*/
/***************************************************************************************************************************************************************************/

x 'cd P:\DEP\Actuarial\05 REPORTS - OPERATIONAL\16 SAS - Macro';
%inc "MIS - email - tekst - MIS.sas";

/* */

%let row_num=0;
proc sql noprint;
select count(*) as row_num into: row_num
from claim_request;
quit;
%put &row_num;
/*%dodaj_odbiorce(238,1,'joanna.wojcik@proama.pl');*/
/*%dodaj_odbiorce(238,1,'dariusz.radaczynski@proama.pl');*/
/*%dodaj_odbiorce(238,1,'jacek.kaminski@proama.pl');*/
/*%dodaj_odbiorce(238,1,'tomasz.kuropatnicki@proama.pl');*/
/*%dodaj_odbiorce(238,1,'miroslaw.orzel@proama.pl');*/
/*%dodaj_odbiorce(238,2,'beata.krzyszczak@proama.pl');*/
/*%dodaj_odbiorce(238,2,'pawel.rokosz@proama.pl');*/
/*%dodaj_odbiorce(238,2,'anna.byba@proama.pl');*/
/*%dodaj_odbiorce(238,2,'dorota.gajewska@proama.pl');*/
/*%dodaj_odbiorce(238,2,'ewa.kosior@proama.pl');*/
/*%dodaj_odbiorce(238,2,'grzegorz.sikora@proama.pl');*/
/*%dodaj_odbiorce(238,2,'katarzyna.flis@proama.pl'); */
/*%dodaj_odbiorce(238,2,'maciej.nosowski@proama.pl');*/
/*%dodaj_odbiorce(238,1,'grzegorz.luczak@proama.pl');*/


%odbiorcy(238);

%macro wyslij_error();
%if &row_num. <= 100 %then %do;

%runtime(&nazwa_raportu,1);

options emailsys=smtp emailhost=email4app.groupama.local emailport=587; 
filename mymail email (&odbiorca1. &odbiorca2.)
    type = 'text/html' 
 subject = "ERROR - BINSIS-238 - Claims & Requests - Daily reports &today." 
    from = "Zespol Analiz i Raportowania <ZespolAnalizIRaportowania@proama.pl>"
 replyto = "ZespolAnalizIRaportowania@proama.pl"
      cc = ("ZespolAnalizIRaportowania@proama.pl" "luiza.smargol@proama.pl");

%let stopka1=" ";
%let stopka2="Raport BINSIS-238 - Claims & Requests - wyst¹pi³ b³¹d podczas generowania raportu";
%let stopka3="Skontaktuj siê z Zespo³em Analiz i Raportowania (ZespolAnalizIRaportowania@proama.pl)";

%email_tekst_MIS (&stopka1., &stopka2., &stopka3.);

%end;
%mend; 

%wyslij_error();

/***************************************************************************************************************************************************************************/

%macro wyslij();
%if &row_num. > 100 %then %do;

%runtime(&nazwa_raportu,0);

options emailsys=smtp emailhost=email4app.groupama.local emailport=587; 

filename mymail email (&odbiorca1. &odbiorca2.)
    type = 'text/html' 
 subject = "C3_BINSIS-238 - Claims & Requests - Daily reports &report_date." 
    from = "Zespol Analiz i Raportowania <ZespolAnalizIRaportowania@proama.pl>"
 replyto = "ZespolAnalizIRaportowania@proama.pl"
      cc = ("ZespolAnalizIRaportowania@proama.pl")
  attach = ("P:\DEP\actuarial\05 REPORTS - OPERATIONAL\04 Claims\BINSIS-238 - Daily Reports\RAPORTY\C3_BINSIS-238 - CLAIMS - Daily Report &date_end..zip");

%let stopka1='Witam,';
%let stopka2="W za³¹czeniu przesy³am Dzienny Raport Szkodowy, stan na &report_date..";
%let stopka3=' ';

%email_tekst_MIS (&stopka1., &stopka2., &stopka3.);
%end;
%mend; 

%wyslij();
