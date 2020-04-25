
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

%let nazwa_raportu_1=BINSIS-837;
%put &nazwa_raportu_1;

%let nazwa_raportu_2=BINSIS-959;
%put &nazwa_raportu_2;

%check_for_database(n=2,baza1=in03prd.policy, baza2=arc01prd.claim_request_data, nazwa_raportu=&nazwa_raportu_1);
%check_for_database(n=2,baza1=in03prd.policy, baza2=arc01prd.claim_request_data, nazwa_raportu=&nazwa_raportu_2);

/*******************************************************************************************************************************************************************/
/*******************************************************************************************************************************************************************/

/*proc sql;
create table claim_last_reserve as 
select claim_id, request_id, claim_state, cover_type, claim_obj_seq, initial_reserv_amnt, last_reserv_amnt, risk_type, gr.risk_name,
       case when injured_object_type = 1 then 'Insured'
	        when injured_object_type = 3 then 'Motor Vehicle'
			when injured_object_type = 4 then 'Property' end as object
  from in03prd.claim_objects co
       left join in03prd.hst_gen_risk gr on gr.id=co.risk_type
 order by claim_id, request_id, cover_type, claim_obj_seq
;
quit;*/

%biblioteki();

proc sql;
create table claim_last_reserve as 
select cr.claim_id, cr.request_id, cr.claim_obj_seq, co.claim_state, co.cover_type, object, co.risk_type, gr.risk_name,
       max(initial_reserv_amnt) as initial_reserv_amnt, sum(reserve_change_amnt) as last_reserv_amnt
  from in03prd.UGPL_CLAIM_RESERVES_HST_INDEM cr
	   left join (select unique claim_id, request_id, claim_obj_seq, claim_state, cover_type, risk_type, 
                                case when injured_object_type = 1 then 'Insured'
									 when injured_object_type = 3 then 'Motor Vehicle'
									 when injured_object_type = 4 then 'Property' end as object
                    from in03prd.claim_objects) co on co.claim_obj_seq=cr.claim_obj_seq
	   left join in03prd.hst_gen_risk gr on gr.id=co.risk_type
 group by cr.claim_id, cr.request_id, cr.claim_obj_seq, co.claim_state, co.cover_type, object, co.risk_type, gr.risk_name
 order by cr.claim_id, cr.request_id, cr.claim_obj_seq, co.claim_state, co.cover_type, object, co.risk_type, gr.risk_name
;quit;

/*******************************************************************************************************************************************************************/
/*******************************************************************************************************************************************************************/

proc sql;
create table claim_paid_indem as 
select claim_id, request_id, cover_type, claim_obj_seq, sum(indem_sum) as indem_sum
  from (select cpd.payment_id, cpd.claim_id, cpd.request_id, cover_type, cpd.claim_obj_seq, pay_sum as indem_sum
		  from in03prd.claim_payments_details cpd
		       left join (select distinct payment_id, doclad_id from in03prd.claim_payments) cp  on cp.payment_id=cpd.payment_id
               left join (select distinct doclad_id, doclad_date, confirm_date, doclad_state from in03prd.claim_doclad) cd on cd.doclad_id=cp.doclad_id
		 where doclad_state not in ('1', '4')
           and confirm_date <> .
           and pay_sum is not null)
 group by claim_id, request_id, cover_type, claim_obj_seq
 order by claim_id, request_id, cover_type, claim_obj_seq
;quit;

/*******************************************************************************************************************************************************************/
/*******************************************************************************************************************************************************************/

/* Ostatnia data confirm dla odszkodowaÒ */
proc sql;
create table claim_paid_time as 
select claim_id, request_id, max(confirm_date) as confirm_date_max
  from (select * 
		  from (select claim_id, request_id, payment_way, pay_sum, currency, indem_sum, expense_sum, 
		               pay_date, doclad_id, man_id, payment_id, case when expense_sum =. then 'RE' else 'CO' end as paid_type 
		          from in03prd.claim_payments 
                 where indem_sum is not null) cp
		               left join (select doclad_id, doclad_date, confirm_date, doclad_state from in03prd.claim_doclad) cd on cd.doclad_id = cp.doclad_id
				       left join (select id, name as doclad_state_desc from in03prd.hst_doclad_state) hds on hds.id=cd.doclad_state
		 where cd.doclad_state not in ('4','1')
	  )
 group by claim_id, request_id
 order by claim_id, request_id
;quit;

/*******************************************************************************************************************************************************************/
/*******************************************************************************************************************************************************************/

libname nadysk 'P:\DEP\Actuarial\05 REPORTS - OPERATIONAL\04 Claims\BINSIS-837 - Great Claims';

proc sql;
create table claim_last_reserve_big as 
select c.*, 
      case when claim_obj_seq in (select claim_obj_seq from nadysk.claim_last_reserve_big) then 'Y' else 'N' end as previous_report,
	   crd.likwidator_m, crd.likwidator_t, crd.registration_date_cr, confirm_date_max, reserve_request
  from claim_last_reserve c
       left join arc01prd.claim_request_data crd on crd.claim_id = c.claim_id and crd.request_id = c.request_id
	   left join claim_paid_time cpt on cpt.claim_id = c.claim_id and cpt.request_id = c.request_id
	   left join (select claim_id, request_id, sum(last_reserv_amnt) as reserve_request 
					from claim_last_reserve 
				   group by claim_id, request_id) agr on agr.claim_id = c.claim_id and agr.request_id = c.request_id
 where last_reserv_amnt > 20000
 order by object, cover_type, last_reserv_amnt desc, claim_id, request_id
;quit;
%change_datetime_format(claim_last_reserve_big,registration_date_cr);
%change_datetime_format(claim_last_reserve_big,confirm_date_max);
proc sort data=claim_last_reserve_big out=claim_last_reserve_big; by descending reserve_request claim_id request_id ; run;

proc sql;
create table nadysk.claim_last_reserve_big as 
select *
  from claim_last_reserve_big
 order by object, cover_type, last_reserv_amnt desc, claim_id, request_id
;quit;

/*******************************************************************************************************************************************************************/
/*******************************************************************************************************************************************************************/

proc sql;
create table report_OF as 
select  policy_id, insr_type, channel, claim_id, cover_type, c.registration_date, 
        round((reserve_claim + indem_claim) / 1000, 0.01) as claim_costs, 
        round(reserve_claim/1000, 0.01) as reserve_claim,
        round(indem_claim/1000, 0.01) as indem_claim,
        round((reserve_claim_cover + indem_claim_cover)/1000, 0.01) as  claim_costs_cover, 
        round(reserve_claim_cover/1000, 0.01) as reserve_claim_cover,
        round(indem_claim_cover/1000, 0.01) as indem_claim_cover,
        case when reserve_claim = 0 then 'CL' else 'OP' end as state
 from  (select c.policy_id, insr_type, channel, cr.claim_id, crc.cover_type, 
		        case when reserve_claim =. then 0 else reserve_claim end as reserve_claim,
		        case when indem_claim = . then 0 else indem_claim end as indem_claim,
		        case when reserve_claim_cover = . them 0 else reserve_claim_cover end as reserve_claim_cover,
		        case when indem_claim_cover = . then 0 else indem_claim_cover end as indem_claim_cover
		  from (select claim_id, sum(last_reserv_amnt) as reserve_claim 
		          from claim_last_reserve
		         group by claim_id) cr
		       left join (select claim_id, cover_type, sum(last_reserv_amnt) as reserve_claim_cover
		                    from claim_last_reserve 
		                   group by claim_id, cover_type) crc on crc.claim_id=cr.claim_id
			   left join (select claim_id, sum(indem_sum) as indem_claim
		                    from claim_paid_indem
		                   group by claim_id) cp on cp.claim_id=cr.claim_id
			   left join (select claim_id, cover_type, sum(indem_sum) as indem_claim_cover
		                    from claim_paid_indem 
		                   group by claim_id, cover_type) cpc on cpc.claim_id=cr.claim_id and cpc.cover_type=crc.cover_type
			   left join (select claim_id, policy_id, registration_date, insr_type from in03prd.claim) c on c.claim_id=cr.claim_id
			   left join (select policy_id, channel from arc01prd.sale_channels) sc on sc.policy_id=c.policy_id
			   )
/* where reserve_claim + indem_claim > 100000*/
;quit;
%change_datetime_format(report_OF,registration_date);

/*kategorie*/
/*cat_1 = > 500 tys. PLN*/
/*cat_2 = > 1 mln PLN*/
/*cat_3 = > 1.5 mln PLN*/

proc sql;
create table licznik as
select count(unique cat_1) as claim_cat_1, count(unique cat_2) as claim_cat_2, count(unique cat_3) as claim_cat_3, count(unique cat_4) as claim_cat_4,
       count(unique cat_5) as claim_cat_5, count(unique cat_6) as claim_cat_6, count(unique cat_7) as claim_cat_7, count(unique cat_8) as claim_cat_8
  from (select of.*,
               case when claim_costs >= 6000 then claim_id end as cat_8,
               case when claim_costs >= 5000 then claim_id end as cat_7,
               case when claim_costs >= 4000 then claim_id end as cat_6,
               case when claim_costs >= 3000 then claim_id end as cat_5,
               case when claim_costs >= 2000 then claim_id end as cat_4,
               case when claim_costs >= 1500 then claim_id end as cat_3,
	           case when claim_costs >= 1000 then claim_id end as cat_2,
			   case when claim_costs >= 500 then claim_id end as cat_1
          from report_OF of);
quit;

proc sql print; select distinct claim_cat_1 into:claim_cat_1 from licznik; quit;
%PUT &claim_cat_1;
proc sql print; select distinct claim_cat_2 into:claim_cat_2 from licznik; quit;
%PUT &claim_cat_2;
proc sql print; select distinct claim_cat_3 into:claim_cat_3 from licznik; quit;
%PUT &claim_cat_3;
proc sql print; select distinct claim_cat_4 into:claim_cat_4 from licznik; quit;
%PUT &claim_cat_4;
proc sql print; select distinct claim_cat_5 into:claim_cat_5 from licznik; quit;
%PUT &claim_cat_5;
proc sql print; select distinct claim_cat_6 into:claim_cat_6 from licznik; quit;
%PUT &claim_cat_6;
proc sql print; select distinct claim_cat_7 into:claim_cat_7 from licznik; quit;
%PUT &claim_cat_7;
proc sql print; select distinct claim_cat_8 into:claim_cat_8 from licznik; quit;
%PUT &claim_cat_8;

%biblioteki();

proc sql;
create table last_change_date as 
select claim_id, max(hist_change_date) as max_change_date
  from in03prd.ugpl_claim_reserves_hst_indem
 group by claim_id
;quit;
%change_datetime_format(last_change_date,max_change_date);

proc sql;
create table report_OF_1 as 
select unique policy_id, insr_type, channel, r.claim_id, state, claim_costs, reserve_claim, indem_claim, max_change_date, registration_date
  from report_OF r
       left join last_change_date ld on ld.claim_id=r.claim_id
 where reserve_claim + indem_claim > 375
 order by max_change_date desc
;quit;
proc sort data=report_OF_1 out=report_OF_1; by descending claim_costs claim_id; run;

proc sql;
create table report_OF_2 as 
select unique r.policy_id, r.insr_type, channel, r.claim_id, state, claim_costs, reserve_claim, indem_claim, max_change_date, r.registration_date
  from report_OF r
  	left join in03prd.claim c on c.claim_id=r.claim_id
	left join last_change_date ld on ld.claim_id=r.claim_id	
where (c.event_country <> 'PL' or r.cover_type = 'GREENCARD')
  and reserve_claim + indem_claim > 150
;quit;
proc sort data=report_OF_2 out=report_OF_2; by descending claim_costs claim_id; run;

proc sql;
create table reserves as
select catt(claim_id,'_', request_id) as claim, reserve_obj,
       max(max_date_obj,max_date_exp) as max_change_date format yymmdd10.
  from (
  select distinct cr.claim_id, cr.request_id,
	  	 round(case when cri.reserve_obj is null then 0 else cri.reserve_obj end, 0.01) as reserve_obj,
         round(case when cre.reserve_exp is null then 0 else cre.reserve_exp end, 0.01) as reserve_exp,
         max_date_obj, max_date_exp
   from in03prd.claim_request cr
   left join (select distinct claim_id, request_id, sum(reserve_change_amnt) as reserve_obj, max(datepart(hist_change_date)) as max_date_obj format=yymmdd10.
				from in03prd.ugpl_claim_reserves_hst_indem
			  group by claim_id, request_id) cri on cri.claim_id=cr.claim_id and cri.request_id=cr.request_id
   left join (select distinct claim_id, request_id, sum(clm_reserve_change) as reserve_exp, max(datepart(hist_change_date)) as max_date_exp format=yymmdd10.
  				from in03prd.ugpl_claim_reserves_hst_exp
			  group by claim_id, request_id) cre on cre.claim_id=cr.claim_id and cre.request_id=cr.request_id
 where cr.claim_state not in (10,11)
   and round(cri.reserve_obj,0.01)>0
   )
group by claim_id, request_id
order by claim_id, request_id;
quit;

%let claim_no=0;
proc sql;
select count(unique claim) as claim_no into: claim_no
  from reserves;
quit;
%let claim_no=%sysfunc(trim(&claim_no.));
%put &claim_no;

%let liczba_szkod=0;
proc sql;
select count(unique claim) as liczba_szkod into:liczba_szkod
  from (select * from reserves where (today()-max_change_date)>=180);
quit;
%let liczba_szkod=%sysfunc(trim(&liczba_szkod.));
%put &liczba_szkod;

%let procent=%sysfunc(putn(%sysfunc(round(%sysevalf(&liczba_szkod./&claim_no.),0.0001)),PERCENT10.2));
%put &procent;

/*proc sql;
create table test as 
select claim_id, sum(incured) as incured
  from (select claim_id, request_id, max(reserve_obj,0)+max(reserve_exp,0)+max(indem_confirm,0)+max(expense_confirm) as incured
          from dane_cr.claim_request_data
         group by claim_id, request_id)
 group by claim_id
;quit;
data test_2;
set test;
where incured > 100000;
run;

proc sql;
create table SZCZEGOLY_SZKODY as
select unique co.*, indemnity, r.id as risk_type, risk_name, last_reserv_amnt+max(0,indemnity) as total_cost
  from (select insr_type, claim_id, request_id, claim_obj_seq, cover_type, risk_type, initial_reserv_amnt, last_reserv_amnt
          from in03prd.claim_objects 
         where claim_id = '20700032254') co
       left join(select * from bourCOPY.HST_GEN_RISK where status = 'A') r on r.id=co.risk_type
/*       left join bourCOPY.cfg_claimgen_initial_reserve ir on ir.risk_type=r.id*/
/*       left join (select cover_type, insr_type, risk_type, risk_grp from bourCOPY.CFG_GEN_COVERS) c on c.risk_type=r.id*/
/*       left join bourCOPY.CFG_EVENT e on e.risk_type=r.id*/
/*	     left join (select * from bourCOPY.HT_EVENT_LIST where status = 'A') he on he.id=e.event_type  *//*
       left join (select claim_obj_seq, sum(pay_sum) as indemnity 
                    from in03prd.claim_payments_details 
				   where payment_id in (select payment_id 
                                          from in03prd.claim_payments 
                                         where doclad_id in (select doclad_id 
   															   from in03prd.claim_doclad
															  where doclad_state in ('2','3')))
                   group by claim_obj_seq) in on in.claim_obj_seq=co.claim_obj_seq
 where co.insr_type in (1001,3001)
 order by co.claim_obj_seq, co.insr_type, co.cover_type, r.id
;quit;

/*******************************************************************************************************************************************************************/
/*******************************************************************************************************************************************************************/

proc sql print ;
select count(unique claim_id) as ile into:ile
from report_OF_1;
quit;
%PUT &ile;
/**/
/*libname stl 'P:\DEP\Actuarial\05 REPORTS - OPERATIONAL\04 Claims\BINSIS-837 - Great Claims' ;*/
/*ods path stl.TEMPLAT(UPDATE)*/
/*SASHELP.TMPLMST(READ);*/
/**/
/*proc template;*/
/*define style styles.meadow;*/
/*parent=MeadowPrinter;*/
/*class header / borderwidth=0;*/
/*end;*/
/*run;*/

/***************************************************************************************************************************************************************************/
/* EKSPORT DO MS EXCEL */
/***************************************************************************************************************************************************************************/

%MACRO num_obs(_dsn_, num_obs) ;
%GLOBAL _numobs_ ;
DATA _NULL_ ;
IF 0 THEN SET &_dsn_ NOBS=how_many ;
CALL SYMPUT("_numobs_", LEFT(PUT(how_many,10.))) ;
STOP ;
RUN ;
%IF %EVAL(&_numobs_) EQ 0 %THEN %DO ;
proc sql ;
alter table &_dsn_
add num_obs char(20);
insert into &_dsn_
set num_obs = "No observations" ;
select * from &_dsn_;
run;
%END ;
%MEND num_obs ;
%num_obs (claim_last_reserve_big, num_obs);
%num_obs (report_OF_1, num_obs);
%num_obs (report_OF_2, num_obs);    

ODS LISTING CLOSE;
ODS tagsets.excelxp FILE = "P:\DEP\Actuarial\05 REPORTS - OPERATIONAL\04 Claims\BINSIS-837 - Great Claims\RAPORTY\C3_BINSIS-837 - Great Claims &today..xls"
                   	STYLE = MeadowPrinter 
                   	options(embedded_titles = 'yes' embedded_footnotes = 'yes' sheet_label = ' '  sheet_name = 'Great Claims' 
					frozen_headers='6'
/*					frozen_rowheaders='2' */
					sheet_interval = 'bygroup' autofilter = 'all')
;
ODS ESCAPECHAR = '^';


PROC REPORT DATA=claim_last_reserve_big nowd headline headskip split='*'
style(header) = { font_weight = bold color = green fontstyle = roman font_size = 2.5 background = #EBF2E6 };
title1 j=c bold color=green height=13pt font=Arial bcolor=white 'BINSIS-837 - Claims Report' ;
title2 j=c bold color=orange height=13pt font=Arial bcolor=white 'Claims with reserve greater than 20.000 PLN';
title3 j=c bold color=black height=12pt font=Arial bcolor=white 'Report Date:' %sysfunc(date(),DDMMYY10.);

column ('CLAIM' claim_id request_id claim_state object cover_type risk_type risk_name)
       ('RESERVES' initial_reserv_amnt last_reserv_amnt)
       ('ADDITIONAL INFO' previous_report likwidator_m likwidator_t)
       ('DATES' registration_date_cr confirm_date_max) ; 

define claim_id      /display 'Claim ID' style(column)={cellwidth=1.0in} center;
define request_id    /display 'Request ID' style(column)={cellwidth=1.0in} center;
define claim_state   /display 'Claim*State' format=numx10.0  style(column)={cellwidth=0.75in} center;
define object        /display 'Object' style(column)={cellwidth=1.0in} center;
define cover_type    /display 'Cover*Type' style(column)={cellwidth=0.75in} center;
define risk_type     /display 'Risk Type' style(column)={cellwidth=1.0in} center;
define risk_name     /display 'Risk Name' style(column)={cellwidth=4.0in} center;
define likwidator_m	 /display 'Likwidator*merytoryczny' style(column)={cellwidth=1.25in} center;
define likwidator_t  /display 'Likwidator*techniczny' style(column)={cellwidth=1.25in} center;
define registration_date_cr    /display 'Data rejestracji*szkody' style(column)={cellwidth=1.25in} center;
define initial_reserv_amnt  /analysis 'Initial Reserve' sum format=20.2  style(column)={cellwidth=1.25in just=right} center;
define last_reserv_amnt     /analysis 'Last Reserve   ' sum format=20.2  style(column)={cellwidth=1.25in just=right} center;
define previous_report      /display 'In Previous*Report' style(column)={cellwidth=0.75in} center;
define confirm_date_max     /display 'Max Confirm*Date' style(column)={cellwidth=1.25in} center;

rbreak after/summarize dol dul style=[font_weight=bold color=green fontstyle=roman font_size=2 background=#EBF2E6] ;
COMPUTE claim_id; IF _break_='_RBREAK_' THEN CALL DEFINE('Claim_ID','style','style=[pretext="Sum" font_size=2.5]'); ENDCOMP;

RUN;

PROC REPORT DATA=report_OF_1 nowd headline headskip split='*' 
style(header) = { font_weight = bold color = green fontstyle = roman font_size = 2.5 background = #EBF2E6 };
title1 j=c bold color=green height=13pt font=Arial bcolor=white 'BINSIS-959 - Claims Report' ;
title2 j=c bold color=orange height=13pt font=Arial bcolor=white 'Claims with total indemnity cost above 375.000 PLN';
title3 j=c bold color=black height=12pt font=Arial bcolor=white 'Report Date:' %sysfunc(date(),DDMMYY10.);
title4 j=c bold color=black height=12pt font=Arial bcolor=white 'Values presented in thousands PLN';

column ( 'POLICY' insr_type policy_id channel)  
       ( 'CLAIM' claim_id state claim_costs reserve_claim indem_claim)
       ( 'DATES' max_change_date registration_date);

define insr_type     /display 'Insr Type' style(column)={cellwidth=1.0in} center;
define policy_id     /display 'Policy ID' style={tagattr="format:######" cellwidth=1.5in} center;
define channel       /display 'Channel' style(column)={cellwidth=1.25in}  center;
define claim_id      /display 'Claim ID' style(column)={cellwidth=1.0in}  center;
define state         /display 'Claim*State' style(column)={cellwidth=1.0in} center;
define claim_costs          /analysis sum 'Total Costs' format=20.2  style(column)={cellwidth=1.25in just=right} center;
define reserve_claim        /analysis sum 'Reserves' format=20.2  style(column)={cellwidth=1.25in just=right} center;
define indem_claim          /analysis sum 'Indemnity' format=20.2  style(column)={cellwidth=1.25in just=right} center;
define max_change_date      /display 'Last Change*Date' style(column)={cellwidth=1.5in} center;
define registration_date    /display 'Registration*Date' style(column)={cellwidth=1.5in} center;


rbreak before/summarize dol dul style=[font_weight=bold color=green fontstyle=roman font_size=2 background=#EBF2E6] ;
COMPUTE claim_id; IF _break_='_RBREAK_' THEN CALL DEFINE('Claim_ID','style','style=[pretext="Sum" font_size=2.5]'); ENDCOMP;
COMPUTE state; IF _break_='_RBREAK_' THEN CALL DEFINE('State','style','style=[pretext="&ile." font_size=2.5]'); ENDCOMP;

RUN;

PROC REPORT DATA=report_OF_2 nowd headline headskip split='*' 
style(header) = { font_weight = bold color = green fontstyle = roman font_size = 2.5 background = #EBF2E6 };
title1 j=c bold color=green height=13pt font=Arial bcolor=white 'BINSIS-959 - Claims Report' ;
title2 j=c bold color=orange height=13pt font=Arial bcolor=white 'Claims with total indemnity cost above 150.000 PLN and (event_country<>PL or cover_type=GREENCARD)';
title3 j=c bold color=black height=12pt font=Arial bcolor=white 'Report Date:' %sysfunc(date(),DDMMYY10.);
title4 j=c bold color=black height=12pt font=Arial bcolor=white 'Values presented in thousands PLN';

column ( 'POLICY' insr_type policy_id channel)  
       ( 'CLAIM' claim_id state claim_costs reserve_claim indem_claim)
       ( 'DATES' max_change_date registration_date);

define insr_type     /display 'Insr Type' style(column)={cellwidth=1.0in} center;
define policy_id     /display 'Policy ID' style={tagattr="format:######" cellwidth=1.5in} center;
define channel       /display 'Channel' style(column)={cellwidth=1.25in}  center;
define claim_id      /display 'Claim ID' style(column)={cellwidth=1.0in}  center;
define state         /display 'Claim*State' style(column)={cellwidth=1.0in} center;
define claim_costs          /analysis sum 'Total Costs' format=20.2  style(column)={cellwidth=1.25in just=right} center;
define reserve_claim        /analysis sum 'Reserves' format=20.2  style(column)={cellwidth=1.25in just=right} center;
define indem_claim          /analysis sum 'Indemnity' format=20.2  style(column)={cellwidth=1.25in just=right} center;
define max_change_date      /display 'Last Change*Date' style(column)={cellwidth=1.5in} center;
define registration_date    /display 'Registration*Date' style(column)={cellwidth=1.5in} center;

rbreak after/summarize dol dul style=[font_weight=bold color=green fontstyle=roman font_size=2 background=#EBF2E6] ;
COMPUTE claim_id; IF _break_='_RBREAK_' THEN CALL DEFINE('Claim_ID','style','style=[pretext="Sum" font_size=2.5]'); ENDCOMP;

RUN;

ODS tagsets.excelxp CLOSE;
ODS LISTING;

/***************************************************************************************************************************************************************************/
/* ZIP */
/***************************************************************************************************************************************************************************/

DATA _null_;
x %str(%'C:\Program Files\7-Zip\7z.EXE%' u -tzip 								
"P:\DEP\Actuarial\05 REPORTS - OPERATIONAL\04 Claims\BINSIS-837 - Great Claims\RAPORTY\C3_BINSIS-837 - Great Claims &today..zip"	
"P:\DEP\Actuarial\05 REPORTS - OPERATIONAL\04 Claims\BINSIS-837 - Great Claims\RAPORTY\C3_BINSIS-837 - Great Claims &today..xls" -r );
RUN; 

FILENAME MyFile "P:\DEP\Actuarial\05 REPORTS - OPERATIONAL\04 Claims\BINSIS-837 - Great Claims\RAPORTY\C3_BINSIS-837 - Great Claims &today..xls";	
  DATA _NULL_ ;																																	
    rc = FDELETE('MyFile') ;
  RUN ;
FILENAME MyFile CLEAR ;

/***************************************************************************************************************************************************************************/
/*EKSPORT DO HTML */
/***************************************************************************************************************************************************************************/

goptions reset=all;
ods html body="P:\DEP\Actuarial\05 REPORTS - OPERATIONAL\04 Claims\BINSIS-837 - Great Claims\RAPORTY\C3_BINSIS-837 - Great Claims &today..html"
RS=NONE style=MeadowPrinter;

PROC REPORT DATA=claim_last_reserve_big nowd headline headskip split='*'
style(header) = { font_weight = bold color = green fontstyle = roman font_size = 2.5 background = #EBF2E6 };
title1 j=c bold color=green height=13pt font=Arial bcolor=white 'BINSIS-837 - Claims Report' ;
title2 j=c bold color=orange height=13pt font=Arial bcolor=white 'Claims with reserve greater than 20.000 PLN';
title3 j=c bold color=black height=12pt font=Arial bcolor=white 'Report Date:' %sysfunc(date(),DDMMYY10.);
column ('CLAIM' claim_id request_id claim_state object cover_type risk_type risk_name)
       ('RESERVES' initial_reserv_amnt last_reserv_amnt)
       ('ADDITIONAL INFO' previous_report likwidator_m likwidator_t)
       ('DATES' registration_date_cr confirm_date_max) ; 
define claim_id      /display 'Claim ID' style(column)={cellwidth=1.0in} center;
define request_id    /display 'Request ID' style(column)={cellwidth=1.0in} center;
define claim_state   /display 'Claim*State' format=numx10.0  style(column)={cellwidth=0.75in} center;
define object        /display 'Object' style(column)={cellwidth=1.0in} center;
define cover_type    /display 'Cover*Type' style(column)={cellwidth=0.75in} center;
define risk_type     /display 'Risk Type' style(column)={cellwidth=1.0in} center;
define risk_name     /display 'Risk Name' style(column)={cellwidth=4.0in} center;
define likwidator_m	 /display 'Likwidator*merytoryczny' style(column)={cellwidth=1.25in} center;
define likwidator_t  /display 'Likwidator*techniczny' style(column)={cellwidth=1.25in} center;
define registration_date_cr    /display 'Data rejestracji*szkody' style(column)={cellwidth=1.25in} center;
define initial_reserv_amnt  /analysis 'Initial Reserve' sum format=nlnum20.2  style(column)={cellwidth=1.25in just=right} center;
define last_reserv_amnt     /analysis 'Last Reserve   ' sum format=nlnum20.2  style(column)={cellwidth=1.25in just=right} center;
define previous_report      /display 'In Previous*Report' style(column)={cellwidth=0.75in} center;
define confirm_date_max     /display 'Max Confirm*Date' style(column)={cellwidth=1.25in} center;

rbreak after/summarize dol dul style=[font_weight=bold color=green fontstyle=roman font_size=2 background=#EBF2E6] ;

COMPUTE claim_id; IF _break_='_RBREAK_' THEN CALL DEFINE('Claim_ID','style','style=[pretext="Sum" font_size=2.5]'); ENDCOMP;

RUN;

ODS HTML CLOSE;

goptions reset=all;
ods html body="P:\DEP\Actuarial\05 REPORTS - OPERATIONAL\04 Claims\BINSIS-837 - Great Claims\RAPORTY\C3_BINSIS-837 - Great Claims (OF) &today..html"
RS=NONE style=MeadowPrinter;

PROC REPORT DATA=report_OF_1 nowd headline headskip split='*' 
style(header) = { font_weight = bold color = green fontstyle = roman font_size = 2.5 background = #EBF2E6 };
title1 j=c bold color=green height=13pt font=Arial bcolor=white 'BINSIS-959 - Claims Report' ;
title2 j=c bold color=orange height=13pt font=Arial bcolor=white 'Claims with total indemnity cost above 375.000 PLN';
title3 j=c bold color=black height=12pt font=Arial bcolor=white 'Report Date:' %sysfunc(date(),DDMMYY10.);
title4 j=c bold color=black height=12pt font=Arial bcolor=white 'Values presented in thousands PLN';
column ( 'POLICY' insr_type policy_id channel)  
       ( 'CLAIM' claim_id state claim_costs reserve_claim indem_claim)
       ( 'DATES' max_change_date registration_date);

define insr_type     /display 'Insr Type' style(column)={cellwidth=1.0in} center;
define policy_id     /display 'Policy ID' style={tagattr="format:######" cellwidth=1.5in} center;
define channel       /display 'Channel' style(column)={cellwidth=1.0in}  center;
define claim_id      /display 'Claim ID' style(column)={cellwidth=1.0in}  center;
define state         /display 'Claim*State' style(column)={cellwidth=1.0in} center;
define claim_costs          /analysis sum 'Total Costs' format=nlnum20.2  style(column)={cellwidth=1.25in just=right} center;
define reserve_claim        /analysis sum 'Reserves' format=nlnum20.2  style(column)={cellwidth=1.25in just=right} center;
define indem_claim          /analysis sum 'Indemnity' format=nlnum20.2  style(column)={cellwidth=1.25in just=right} center;
define max_change_date      /display 'Last Change*Date' style(column)={cellwidth=1.5in} center;
define registration_date    /display 'Registration*Date' style(column)={cellwidth=1.5in} center;

rbreak after/summarize dol dul style=[font_weight=bold color=green fontstyle=roman font_size=2 background=#EBF2E6] ;
COMPUTE claim_id; IF _break_='_RBREAK_' THEN CALL DEFINE('Claim_ID','style','style=[pretext="Sum" font_size=2.5]'); ENDCOMP;

RUN;

PROC REPORT DATA=report_OF_2 nowd headline headskip split='*' 
style(header) = { font_weight = bold color = green fontstyle = roman font_size = 2.5 background = #EBF2E6 };
title1 j=c bold color=green height=13pt font=Arial bcolor=white 'BINSIS-959 - Claims Report' ;
title2 j=c bold color=orange height=13pt font=Arial bcolor=white 'Claims with total indemnity cost above 150.000 PLN and (event_country<>PL or cover_type=GREENCARD)';
title3 j=c bold color=black height=12pt font=Arial bcolor=white 'Report Date:' %sysfunc(date(),DDMMYY10.);
title4 j=c bold color=black height=12pt font=Arial bcolor=white 'Values presented in thousands PLN';
column ( 'POLICY' insr_type policy_id channel)  
       ( 'CLAIM' claim_id state claim_costs reserve_claim indem_claim)
       ( 'DATES' max_change_date registration_date);

define insr_type     /display 'Insr Type' style(column)={cellwidth=1.0in} center;
define policy_id     /display 'Policy ID' style={tagattr="format:######" cellwidth=1.5in} center;
define channel       /display 'Channel' style(column)={cellwidth=1.0in}  center;
define claim_id      /display 'Claim ID' style(column)={cellwidth=1.0in}  center;
define state         /display 'Claim*State' style(column)={cellwidth=1.0in} center;
define claim_costs          /analysis sum 'Total Costs' format=nlnum20.2  style(column)={cellwidth=1.25in just=right} center;
define reserve_claim        /analysis sum 'Reserves' format=nlnum20.2  style(column)={cellwidth=1.25in just=right} center;
define indem_claim          /analysis sum 'Indemnity' format=nlnum20.2  style(column)={cellwidth=1.25in just=right} center;
define max_change_date      /display 'Last Change*Date' style(column)={cellwidth=1.5in} center;
define registration_date    /display 'Registration*Date' style(column)={cellwidth=1.5in} center;

rbreak after/summarize dol dul style=[font_weight=bold color=green fontstyle=roman font_size=2 background=#EBF2E6] ;
COMPUTE claim_id; IF _break_='_RBREAK_' THEN CALL DEFINE('Claim_ID','style','style=[pretext="Sum" font_size=2.5]'); ENDCOMP;

RUN;

ODS HTML CLOSE;

/***************************************************************************************************************************************************************************/
/*WYS£ANIE NA EMAIL*/
/***************************************************************************************************************************************************************************/

x 'cd P:\DEP\Actuarial\05 REPORTS - OPERATIONAL\16 SAS - Macro';
%inc "MIS - email - tekst - MIS.sas";

/* */

%let row_num=0;
proc sql noprint;
select count(*) as row_num into: row_num
from claim_last_reserve_big;
quit;
%put &row_num;

/*%dodaj_odbiorce(837,1,'jacek.kaminski@proama.pl');*/
/*%dodaj_odbiorce(837,1,'dariusz.radaczynski@proama.pl');*/
/*%dodaj_odbiorce(837,1,'beata.krzyszczak@proama.pl');*/
/*%dodaj_odbiorce(837,1,'jaroslaw.bogusz@proama.pl');*/
/*%dodaj_odbiorce(837,2,'mariusz.kozlowski@proama.pl');*/
/*%dodaj_odbiorce(837,3,'joanna.wojcik@proama.pl');*/
/*%dodaj_odbiorce(837,3,'ewelina.cichocka@proama.pl');*/
/*%dodaj_odbiorce(837,3,'barbara.bielesz@proama.pl');*/

%odbiorcy(837);
%put &odbiorca1;
%put &odbiorca2;
%put &odbiorca3;

%macro wyslij_error();
%if &row_num. <= 10 %then %do;

%runtime(&nazwa_raportu_1,1);

options emailsys=smtp emailhost=email4app.groupama.local emailport=587; 
filename mymail email (&odbiorca1.)
    type = 'text/html' 
 subject = "ERROR - BINSIS-837 - Claims - Great Claims &today." 
    from = "Zespol Analiz i Raportowania <ZespolAnalizIRaportowania@proama.pl>"
 replyto = "ZespolAnalizIRaportowania@proama.pl"
      cc = ("ZespolAnalizIRaportowania@proama.pl" "ewelina.cichocka@proama.pl" "barbara.bielesz@proama.pl")
 ;

%let stopka1=" ";
%let stopka2="Raport BINSIS-837 - Claims - Great Claims - wystπpi≥ b≥πd podczas generowania raportu.";
%let stopka3="Skontaktuj siÍ z Zespo≥em Analiz i Raportowania (ZespolAnalizIRaportowania@proama.pl).";

%email_tekst_MIS (&stopka1., &stopka2., &stopka3.);

%end;
%mend; 

%wyslij_error();

/***************************************************************************************************************************************************************************/

%macro wyslij();
%if &row_num. > 10 %then %do;

%runtime(&nazwa_raportu_1,0);

x 'cd P:\DEP\Actuarial\05 REPORTS - OPERATIONAL\04 Claims\BINSIS-837 - Great Claims\Reports';
filename tabela "P:\DEP\Actuarial\05 REPORTS - OPERATIONAL\04 Claims\BINSIS-837 - Great Claims\RAPORTY\C3_BINSIS-837 - Great Claims &today..html";

options emailsys=smtp emailhost=email4app.groupama.local emailport=587 sortseq=Polish; 
filename mymail email (&odbiorca1. &odbiorca2.)
content_type="text/html" 
 subject = "C3_BINSIS-837 - Claims - Great Claims &today." 
    from = "Zespol Analiz i Raportowania <ZespolAnalizIRaportowania@proama.pl>"
 replyto = "ZespolAnalizIRaportowania@proama.pl"
      cc = ("ZespolAnalizIRaportowania@proama.pl" &odbiorca3.)
  attach = ("P:\DEP\Actuarial\05 REPORTS - OPERATIONAL\04 Claims\BINSIS-837 - Great Claims\RAPORTY\C3_BINSIS-837 - Great Claims &today..zip")
;

data _null_;
infile tabela end=last;
file mymail;
if _N_=1 then put "Hello, <br><br> Below please find a list of claims with reserve over 20.000 PLN (as at &today.). <br>"
"Please verify that the value is not overestimated. <br><br>
The number of open claims for which reserve has not been changed for 180 days or more:<b> &liczba_szkod. (&procent. of all claims)</b> <br><br>";
input;
put _infile_; 
if last then put "<br><br>This report was generated automatically.<br>
In case of any questions, remarks, comments please contact me.<br><br>
Pozdrawiam/Best regards,<br>
___________________________________ <br>
ZespÛ≥ Analiz i Raportowania<br>
Proama<br>
Ul. PostÍpu 15B,<br>
02-676 Warszawa<br>
Email: ZespolAnalizIRaportowania@proama.pl<br>
___________________________________<br>
Powyøsze informacje sπ przeznaczone wy≥πcznie do uøytku osÛb lub podmiotÛw, do ktÛrych sπ adresowane.<br>;
Jeúli nie jesteú adresatem tej wiadomoúci, niniejszym informujemy, øe rozprowadzanie, jakakolwiek zmiana, dystrybucja oraz kopiowanie tego dokumentu sπ zabronione.<br>
»esk· pojiöùovna S.A. Oddzia≥ w Polsce, w≥aúciciel marki Proama, nie gwarantuje integralnoúci tej wiadomoúci w Internecie oraz w øaden sposÛb nie ponosi odpowiedzialnoúci za jej treúÊ.<br>
Jeúli nie jesteú w≥aúciwym adresatem tej wiadomoúci usuÒ jπ i powiadom o tym nadawcÍ.<br>
<br>
»esk· pojiöùovna S.A. Oddzia≥ w Polsce (czÍúÊ Generali PPF Holding) z siedzibπ w Warszawie, ul. PostÍpu 15B, <br>
wpisana do Krajowego Rejestru Sπdowego prowadzonego przez Sπd Rejonowy dla m. st. Warszawy w Warszawie,<br>
XIII Wydzia≥ Gospodarczy Krajowego Rejestru Sπdowego, pod numerem KRS 0000430690, NIP 1080013493, VAT 1080013642, REGON 146267490"; 
run;

%end;
%mend; 

%wyslij();

/***************************************************************************************************************************************************************************/
/***************************************************************************************************************************************************************************/

%let row_num=0;
proc sql noprint;
select count(*) as row_num into: row_num
from report_of_1;
quit;
%put &row_num;

/*%dodaj_odbiorce(959,1,'olivier.faucher@proama.pl');*/
/*%dodaj_odbiorce(959,1,'agata.kariozen@proama.pl');*/
/*%dodaj_odbiorce(959,2,'ewelina.cichocka@proama.pl');*/
/*%dodaj_odbiorce(959,2,'barbara.bielesz@proama.pl');*/

%odbiorcy(959);
%put &odbiorca1;
%put &odbiorca2;

%macro wyslij_error();
%if &row_num. <= 5 %then %do;

%runtime(&nazwa_raportu_2,1);

options emailsys=smtp emailhost=email4app.groupama.local emailport=587; 
filename mymail email (&odbiorca1.)
    type = 'text/html' 
 subject = "ERROR - BINSIS-959 - Claims - Great Claims &today." 
    from = "Zespol Analiz i Raportowania <ZespolAnalizIRaportowania@proama.pl>"
 replyto = "ZespolAnalizIRaportowania@proama.pl"
      cc = ("ZespolAnalizIRaportowania@proama.pl" "barbara.bielesz@proama.pl")
;

%let stopka1=" ";
%let stopka2="Raport BINSIS-959 - Claims - Great Claims - wystπpi≥ b≥πd podczas generowania raportu.";
%let stopka3="Skontaktuj siÍ z Zespo≥em Analiz i Raportowania (ZespolAnalizIRaportowania@proama.pl).";

%email_tekst_MIS (&stopka1., &stopka2., &stopka3.);

%end;
%mend; 

%wyslij_error();

/***************************************************************************************************************************************************************************/

%macro wyslij();
%if &row_num. > 5 %then %do;

%runtime(&nazwa_raportu_2,0);

x 'cd P:\DEP\Actuarial\05 REPORTS - OPERATIONAL\04 Claims\BINSIS-837 - Great Claims\Reports';
filename tabela "P:\DEP\Actuarial\05 REPORTS - OPERATIONAL\04 Claims\BINSIS-837 - Great Claims\RAPORTY\C3_BINSIS-837 - Great Claims (OF) &today..html";

options emailsys=smtp emailhost=email4app.groupama.local emailport=587 sortseq=Polish; 
filename mymail email (&odbiorca1.)
content_type="text/html" 
 subject = "C3_BINSIS-959 - Claims - Great Claims &today." 
    from = "Zespol Analiz i Raportowania <ZespolAnalizIRaportowania@proama.pl>"
 replyto = "ZespolAnalizIRaportowania@proama.pl"
      cc = ("ZespolAnalizIRaportowania@proama.pl" &odbiorca2.)
  attach = ("P:\DEP\Actuarial\05 REPORTS - OPERATIONAL\04 Claims\BINSIS-837 - Great Claims\RAPORTY\C3_BINSIS-837 - Great Claims &today..zip")
  ;

data _null_;
infile tabela end=last;
file mymail;
if _N_=1 then put "Olivier, <br><br> Below please find a list of claims with total costs above 375.000 PLN (as at &today.). <br>"
"Total costs = last case reserve for indemnity + indemnity (in state confirm or paid). <br><br>

Number of claims with total cost above <b>6.0 mln PLN</b> is <b>&claim_cat_8.</b> <br>
Number of claims with total cost above <b>5.0 mln PLN</b> is <b>&claim_cat_7.</b> <br>
Number of claims with total cost above <b>4.0 mln PLN</b> is <b>&claim_cat_6.</b> <br>
Number of claims with total cost above <b>3.0 mln PLN</b> is <b>&claim_cat_5.</b> <br>
Number of claims with total cost above <b>2.0 mln PLN</b> is <b>&claim_cat_4.</b> <br>
Number of claims with total cost above <b>1.5 mln PLN</b> is <b>&claim_cat_3.</b> <br>
Number of claims with total cost above <b>1.0 mln PLN</b> is <b>&claim_cat_2.</b> <br>
Number of claims with total cost above <b>0.5 mln PLN</b> is <b>&claim_cat_1.</b> <br><br>

The number of open claims for which reserve has not been changed for 180 days or more:<b> &liczba_szkod. (&procent. of all open claims)</b> <br><br>";
input;
put _infile_; 
if last then put "<br><br>This report was generated automatically.<br>
In case of any questions, remarks, comments please contact me.<br><br>
Pozdrawiam/Best regards,<br>
___________________________________ <br>
ZespÛ≥ Analiz i Raportowania<br>
Proama<br>
Ul. PostÍpu 15B,<br>
02-676 Warszawa<br>
Email: ZespolAnalizIRaportowania@proama.pl<br>
___________________________________<br>
Powyøsze informacje sπ przeznaczone wy≥πcznie do uøytku osÛb lub podmiotÛw, do ktÛrych sπ adresowane.<br>;
Jeúli nie jesteú adresatem tej wiadomoúci, niniejszym informujemy, øe rozprowadzanie, jakakolwiek zmiana, dystrybucja oraz kopiowanie tego dokumentu sπ zabronione.<br>
»esk· pojiöùovna S.A. Oddzia≥ w Polsce, w≥aúciciel marki Proama, nie gwarantuje integralnoúci tej wiadomoúci w Internecie oraz w øaden sposÛb nie ponosi odpowiedzialnoúci za jej treúÊ.<br>
Jeúli nie jesteú w≥aúciwym adresatem tej wiadomoúci usuÒ jπ i powiadom o tym nadawcÍ.<br>
<br>
»esk· pojiöùovna S.A. Oddzia≥ w Polsce (czÍúÊ Generali PPF Holding) z siedzibπ w Warszawie, ul. PostÍpu 15B, <br>
wpisana do Krajowego Rejestru Sπdowego prowadzonego przez Sπd Rejonowy dla m. st. Warszawy w Warszawie,<br>
XIII Wydzia≥ Gospodarczy Krajowego Rejestru Sπdowego, pod numerem KRS 0000430690, NIP 1080013493, VAT 1080013642, REGON 146267490"; 
run;

%end;
%mend; 

%wyslij();

