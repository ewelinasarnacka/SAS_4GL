
/*Ewelina Sarnacka*/
/*2015-12-28*/
/*opis raportu 238*/


options ls=150 pagesize=30;
%let today = %sysfunc(date(),yymmdd10.);

%macro change_datetime_format(table,variable);
data &table;
set &table;
&variable=datepart(&variable);
format &variable yymmdd10.;
run;
%mend;

%let nazwa_raportu=RAPORT_01;
%put &nazwa_raportu;

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
/* Raport na bazie tabeli pomocniczej CRD */
/***************************************************************************************************************************************************************/

data claim_request;
set baza.claim_request;
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
;quit;

/***************************************************************************************************************************************************************************/
/*EKSPORT DO MS EXCEL*/
/***************************************************************************************************************************************************************************/

libname zapis 'sciezka_do_raportu\raport';
data zapis.dane_238;
set claim_request_export;
run;

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
	put '[open("ścieżka\raport_FORMAT.xlsm")]';
run;

data _null_;
file sas2xls;
	put '[error(false)]';
	put '[RUN("Odswiez")]';
run; 


data _null_;
file sas2xls;
	put '[error(false)]';
	put %unquote(%bquote('[save.as("sciezka_do_raportu\raport_ &date_end..xlsm")]'));
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
"sciezka_do_raportu\raport_&date_end..zip" 
"sciezka_do_raportu\raport_&date_end..xlsm" -r );
run; 
data _null_;
x=sleep(15);
run;

FILENAME MyFile "sicezka_do_raportu\report &date_end..xlsm" ;
  DATA _NULL_ ;
    rc = FDELETE('MyFile') ;
  RUN ;
FILENAME MyFile CLEAR ;


/***************************************************************************************************************************************************************************/
/*WYS£ANIE NA EMAIL*/
/***************************************************************************************************************************************************************************/

x 'cd sciezka\Macro';
%inc "Email - tekst.sas";

%let row_num=0;
proc sql noprint;
select count(*) as row_num into: row_num
from claim_request;
quit;
%put &row_num;

%odbiorcy(238);

%macro wyslij_error();
%if &row_num. <= 100 %then %do;

%runtime(&nazwa_raportu,1);

options emailsys=smtp emailhost=xxx emailport=111; 
filename mymail email (&odbiorca1. &odbiorca2.)
    type = 'text/html' 
 subject = "ERROR - Raport &today." 
    from = "zzz <zzz@ppp.pl>"
 replyto = "zzz@ppp.pl"
      cc = ("zzz@ppp.pl");

%let stopka1=" ";
%let stopka2="Raport - wystąpił błąd podczas generowania raportu";
%let stopka3="Skontaktuj się z zzz (zzz@ppp.pl)";

%email_tekst_MIS (&stopka1., &stopka2., &stopka3.);

%end;
%mend; 

%wyslij_error();

/***************************************************************************************************************************************************************************/

%macro wyslij();
%if &row_num. > 100 %then %do;

%runtime(&nazwa_raportu,0);

options emailsys=smtp emailhost=xxx emailport=111; 

filename mymail email (&odbiorca1. &odbiorca2.)
    type = 'text/html' 
 subject = "Raport &report_date." 
    from = "zzz <zzz@ppp.pl>"
 replyto = "zzz@ppp.pl"
      cc = ("zzz@ppp.pl");
  attach = ("sciezka/raport &date_end..zip");

%let stopka1='Witam,';
%let stopka2="W załączeniu przesyłam raport..., stan na &report_date..";
%let stopka3=' ';

%email_tekst_MIS (&stopka1., &stopka2., &stopka3.);
%end;
%mend; 

%wyslij();
