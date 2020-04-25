
/*%biblioteki();*/

%let today = %sysfunc(date(),yymmdd10.);
%let nazwa_raportu=BINSIS-2703;
%put &nazwa_raportu;

%check_for_database(n=2,baza1=in03prd.claim, baza2=arc05tst.claim_request_data, nazwa_raportu=&nazwa_raportu);

data daty;
	 format date_start yymmdd10. date_end yymmdd10.;
	 date_start = intnx('year',today(),-3,'begin');
     date_end =intnx('month',today(),-1,'end');
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

/******************************************************************************************************************************************************************/
/******************************************************************************************************************************************************************/
/* PAID */
/******************************************************************************************************************************************************************/
/******************************************************************************************************************************************************************/

proc sql;
create table gl_insis2gl_pay as 
select *
 from in03prd.gl_insis2gl
where gltrans_type in ('CLAIMPAY', 'CLAIMEXP', 'REVERSE', 'REGRESRQ', 'REGRES')
/*  and insr_type = 1001*/
;quit;
%change_datetime_format(gl_insis2gl_pay,account_date);

proc sql;
create table regresses_obj as 
select *
  from in03prd.claim_regresses_restore
 where status <> '2' and expense_id = .
;quit;

proc sql;
create table paid_obj as 
select gl.*, c.event_date, case when regresses <> 0 then 'REG_OBJ' else 'OBJ' end as type
  from (select reference_id, gltrans_id, reversed_gltrans_id, gltrans_type, insr_type, fract_type, cover_type, claim_number,
               year(account_date) as calendar_year, month(account_date) as calendar_month, account_date,
               case when dt_account like '%REGRES%' then amount else 0 end as regresses,
               case when dt_account like '%REGRES%' then 0 else amount end as payments,
			   amount
		  from gl_insis2gl_pay
		 where (gltrans_type in ('REVERSE') 
		        and reversed_gltrans_id in (select gltrans_id 
		                                 from (select gltrans_id, gltrans_type 
		                                         from gl_insis2gl_pay
		                                        where gltrans_type in ('CLAIMPAY')
												      or (gltrans_type in ('REGRESRQ') and reference_id in (select regress_sum_id as reference_id from regresses_obj ))
													  or (gltrans_type in ('REGRES') and reference_id in (select restore_id as reference_id from regresses_obj ))
		                                       )
									   )
				) or gltrans_type in ('CLAIMPAY')
				  or (gltrans_type in ('REGRESRQ') and reference_id in (select regress_sum_id as reference_id from regresses_obj ))
				  or (gltrans_type in ('REGRES') and reference_id in (select restore_id as reference_id from regresses_obj ))		) gl
		left join in03prd.claim c on c.claim_id=gl.claim_number
;quit;

proc sql;
create table regresses_exp as 
select *
  from in03prd.claim_regresses_restore
 where status <> '2' and expense_id <> .
;quit;

proc sql;
create table paid_exp as 
select gl.*, c.event_date, case when regresses <> 0 then 'REG_EXP' else 'EXP' end as type
  from (select reference_id, gltrans_id, reversed_gltrans_id, gltrans_type, insr_type, fract_type, cover_type, claim_number,
               year(account_date) as calendar_year, month(account_date) as calendar_month, account_date, 
               case when dt_account like '%REGRES%' then amount else 0 end as regresses,
               case when dt_account like '%REGRES%' then 0 else amount end as payments, 
               amount
		  from gl_insis2gl_pay
		 where (gltrans_type in ('REVERSE') 
		        and reversed_gltrans_id in (select gltrans_id 
		                                 from (select gltrans_id, gltrans_type 
		                                         from gl_insis2gl_pay
		                                        where gltrans_type in ('CLAIMEXP')
												      or (gltrans_type in ('REGRESRQ') and reference_id in (select regress_sum_id as reference_id from regresses_exp ))
													  or (gltrans_type in ('REGRES') and reference_id in (select restore_id as reference_id from regresses_exp ))
		                                       )
									   )
				) or gltrans_type in ('CLAIMEXP')
				  or (gltrans_type in ('REGRESRQ') and reference_id in (select regress_sum_id as reference_id from regresses_exp ))
				  or (gltrans_type in ('REGRES') and reference_id in (select restore_id as reference_id from regresses_exp ))
		) gl
		left join in03prd.claim c on c.claim_id=gl.claim_number
;quit;

data paid_hist_all;
set paid_obj paid_exp;
run;

/******************************************************************************************************************************************************************/

proc sql;
create table paid_hist_all as 
select ph.*,
       case when cpd.claim_id is not null  then cpd.claim_id 
	        when cpdr.claim_id is not null then cpdr.claim_id 
			when cr.claim_id is not null   then cr.claim_id 
            when ce.claim_id is not null   then ce.claim_id  
            when reg.claim_id is not null  then reg.claim_id end as claim_id_no,
       case when cpd.request_id is not null  then cpd.request_id 
	        when cpdr.request_id is not null then cpdr.request_id 
			when cr.request_id is not null   then cr.request_id 
            when ce.request_id is not null   then ce.request_id 
            when reg.request_id is not null  then reg.request_id end as request_id,
	   case when upper(risk_name) like '%RENTA%' then 'Annuity' else '' end as Annuity_ugpl
  from paid_hist_all ph
       left join (select detail_id, claim_id, request_id, risk_type from in03prd.claim_payments_details) cpd on cpd.detail_id=ph.reference_id
	   left join (select reference_id, gltrans_id from in03prd.gl_insis2gl) glr on glr.gltrans_id=ph.reversed_gltrans_id
	   left join (select detail_id, claim_id, request_id from in03prd.claim_payments_details) cpdr on cpdr.detail_id=glr.reference_id
	   left join (select regress_sum_id, claim_id, request_id from in03prd.claim_regresses_sum) cr on cr.regress_sum_id=ph.reference_id
	   left join (select claim_exp_seq, claim_id, request_id from in03prd.claim_expenses) ce on ce.claim_exp_seq=ph.reference_id	   
	   left join (select restore_id, claim_id, request_id from in03prd.claim_regresses_restore) reg on reg.restore_id=ph.reference_id
       left join in03prd.hst_gen_risk gr on gr.id=cpd.risk_type
;quit;

proc sql;
create table paid_hist as 
select ph.*, policy_id, szkoda_osobowa, annuity, registration_date, 
       intnx('month',datepart(event_date),-0,'end') as event_date_my format yymmdd10., 
	   intnx('month',datepart(registration_date),-0,'end') as registration_date_my format yymmdd10.,
	   intnx('month',account_date,-0,'end') as hist_change_date_my format yymmdd10.
  from paid_hist_all ph
	   left join (select unique claim_id, request_id, registration_date
                    from in03prd.claim_request) cr on cr.claim_id=ph.claim_number and cr.request_id=ph.request_id
	   left join (select unique policy_id, claim_id, request_id, bi as szkoda_osobowa, annuity
                    from arc05tst.claim_request_data) crd on crd.claim_id=ph.claim_number and crd.request_id=ph.request_id
;quit;
data paid_hist;
set paid_hist;
claim_id = input(claim_id_no, 12.);
drop detail_id reference_id regress_sum_id claim_exp_seq reversed_gltrans_id;
run;
%change_datetime_format(paid_hist,event_date);
%change_datetime_format(paid_hist,registration_date);

/*proc sql;
create table test as
select *  from paid_hist where claim_id = .
;quit;

proc sql;
create table test as 
select *  from paid_hist_all where Annuity_ugpl is not null;
;quit;

/******************************************************************************************************************************************************************/
/******************************************************************************************************************************************************************/
/* RESERVE */
/******************************************************************************************************************************************************************/
/******************************************************************************************************************************************************************/

%biblioteki();

proc sql;
create table claim_reserve_obj_hist as 
select insr_type, policy_id, 
       event_type,
       cr.claim_id, claim_type, 
       request_id, claim_type_cr, 
       claim_state, claim_state_desc, solve_way_desc,
       cover_type, risk_type, risk_name, claim_obj_seq, initial_reserv_amnt, 
       last_reserv_amnt as  hist_reserve,
       reserve_change_amnt as diff_reserve, 
       hist_change_date, hist_change_by, history_id,
	   case when upper(risk_name) like '%RENTA%' then 'Annuity' else '' end as Annuity_ugpl
  from in03prd.ugpl_claim_reserves_hst_indem cr
  		left join (select state_id, name as claim_state_desc from in03prd.hst_claim_state where status='A') chss on chss.state_id=cr.claim_state
		left join (select id, name as solve_way_desc from in03prd.ht_claim_solve_way) hcs on hcs.id=cr.solve_way
        left join (select id, risk_name from in03prd.hst_gen_risk where status='A') chs on chs.id=cr.risk_type
        inner join (select claim_id, insr_type from in03prd.claim) c on c.claim_id=cr.claim_id
;quit;

proc sql;
create table claim_reserve_exp_hist as 
select insr_type, policy_id, 
       event_type,
       cr.claim_id, claim_type, 
       request_id, claim_type_cr, 
       claim_state, claim_state_desc, solve_way_desc, 
       cover_type, risk_type, risk_name, claim_obj_seq, claim_exp_seq, expense_id, 
       clm_expense_sum as hist_reserve, 
       clm_reserve_change as diff_reserve, 
       hist_change_date, hist_change_by, history_id,
	   '' as Annuity_ugpl
  from in03prd.ugpl_claim_reserves_hst_exp cr
  		left join (select state_id, name as claim_state_desc from in03prd.hst_claim_state where status='A') chss on chss.state_id=cr.claim_state
		left join (select id, name as solve_way_desc from in03prd.ht_claim_solve_way) hcs on hcs.id=cr.solve_way
        left join (select id, risk_name from in03prd.hst_gen_risk where status='A') chs on chs.id=cr.risk_type
        inner join (select claim_id, insr_type from in03prd.claim) c on c.claim_id=cr.claim_id
;quit;

proc sql;
create table claim_req_max as
select claim_id, request_id, catt('obj',max(history_id)) as hist_event
  from claim_reserve_obj_hist
 where (year(datepart(hist_change_date)) < &rok. ) or (year(datepart(hist_change_date)) = &rok. and month(datepart(hist_change_date)) <= &miesiac.) 
 group by claim_id, request_id
 order by claim_id, request_id
;quit;

proc sql;
create table claim_hist as
select *
  from (select insr_type, policy_id, claim_id, claim_type, event_type, request_id, claim_type_cr, claim_state, 
               0 as claim_exp_seq, 0 as expense_id, claim_obj_seq, risk_type, risk_name,  
               hist_reserve, diff_reserve, hist_change_date, hist_change_by, catt('obj', history_id) as hist_event, Annuity_ugpl
          from claim_reserve_obj_hist)
 union all
		  (select insr_type, policy_id, claim_id, claim_type, event_type, request_id, claim_type_cr, claim_state, 
                  claim_exp_seq, expense_id, claim_obj_seq, risk_type, risk_name, 
                  hist_reserve, diff_reserve,hist_change_date, hist_change_by, catt('exp', history_id) as hist_event, Annuity_ugpl
             from claim_reserve_exp_hist)
order by policy_id, claim_id, request_id, claim_obj_seq, claim_exp_seq, expense_id, hist_change_date
;quit;
proc sql;
create table claim_hist as 
select ch.*, c.event_date, cr.registration_date,
	   intnx('month',datepart(c.event_date),-0,'end') as event_date_my format yymmdd10., 
	   intnx('month',datepart(cr.registration_date),-0,'end') as registration_date_my format yymmdd10.,
	   intnx('month',datepart(hist_change_date),-0,'end') as hist_change_date_my format yymmdd10.,
       case when com.cover_type=' ' then co.cover_type else com.cover_type end as cover_type, crd.bi as szkoda_osobowa, crd.annuity
 from claim_hist ch
       left join (select claim_id, request_id,  history_id, cover_type
   					from claim_reserve_obj_hist 
				   where catt('obj', history_id) in (select hist_event from claim_req_max)) com on com.claim_id=ch.claim_id and com.request_id=ch.request_id
	   left join in03prd.claim_objects co on co.claim_obj_seq=ch.claim_obj_seq
	   left join (select unique * from arc05tst.claim_request_data) crd on crd.claim_id=ch.claim_id and crd.request_id=ch.request_id
	   left join (select unique * from in03prd.claim_request) cr on cr.claim_id=ch.claim_id and cr.request_id=ch.request_id
	   left join (select unique * from in03prd.claim) c on c.claim_id=ch.claim_id 
;quit;
%change_datetime_format(claim_hist,event_date);
%change_datetime_format(claim_hist,registration_date);
%change_datetime_format(claim_hist,hist_change_date);

/******************************************************************************************************************************************************************/
/******************************************************************************************************************************************************************/
/* Wyp³aty i rezerwy razem */
/******************************************************************************************************************************************************************/
/******************************************************************************************************************************************************************/

/*
%biblioteki();

proc sql;
create table premium_casco as
select policy_id, cover_type, round(sum(premium), 0.01) as premium_gl
  from (select insr_type, policy_id, cover_type, case when ct_account like 'DP%' then amount else 0 end as premium
          from in03prd.gl_insis2gl
         where insr_type in (1001, 1101, 1201)
      	   and cover_type like 'CSC%')
 group by policy_id, cover_type
having round(sum(premium), 0.01) <> 0
;quit;*/

proc sql;
create table Database_ResQ as
select *
  from (
select *
  from (select insr_type, policy_id, claim_id, request_id, cover_type, szkoda_osobowa, annuity, annuity_ugpl,
               event_date_my, registration_date_my, hist_change_date_my, diff_reserve as amount, 'RESERVE' as type,
			   case when claim_exp_seq = 0 then 'RESERVE OBJ' else 'RESERVE EXP' end as sub_type,
               event_date, registration_date, hist_change_date
          from claim_hist)
 union all
	   (select insr_type, policy_id, claim_id_no as claim_id, request_id, cover_type, szkoda_osobowa, annuity, annuity_ugpl,
               event_date_my, registration_date_my, hist_change_date_my, amount, 'PAYMENT' as type,
			   case when type like '%EXP%' then 'PAYMENT EXP' else 'PAYMENT OBJ' end as sub_type,
               event_date, registration_date, account_date as hist_change_date
          from paid_hist 
         where type not like 'REG%')
 union all
	   (select insr_type, policy_id, claim_id_no as claim_id, request_id, cover_type, szkoda_osobowa, annuity, annuity_ugpl,
               event_date_my, registration_date_my, hist_change_date_my, amount, 'REGRES' as type,
			   case when type like '%EXP%' then 'REGRES EXP' else 'REGRES OBJ' end as sub_type,
               event_date, registration_date, account_date as hist_change_date
          from paid_hist 
         where type like 'REG%')
        )
order by insr_type, claim_id, request_id, event_date_my, registration_date_my, hist_change_date_my
;quit;

proc sql;
create table Database_ResQ as
select d.*, channel, sub_channel, insr_duration, insurance_group, tagetik_lob, macro_lob,
       case when reserve_class = '1001 MTPL' and szkoda_osobowa <> 'BI'                         then '1001 MTPL Property'
            when reserve_class = '1001 MTPL' and szkoda_osobowa = 'BI' and annuity <> 'Annuity' then '1001 MTPL BI wo A'
            when reserve_class = '1001 MTPL' and szkoda_osobowa = 'BI' and annuity =  'Annuity' then '1001 MTPL Annuity'
            when reserve_class = '1001 CASCO' and d.cover_type = 'CSC_THT_T' then '1001 CASCO' /*'1001 CASCO Theft'*/
            when reserve_class = '1001 CASCO'                                then '1001 CASCO' /*'1001 CASCO Damage'*/
            when reserve_class = '3001 HOME' and insr_duration = 1 then '3001 HOME' /*'3001 HOME DR1'*/
            when reserve_class = '3001 HOME' and insr_duration = 3 then '3001 HOME' /*'3001 HOME DR3'*/
            else reserve_class end as reserve_class
			/*case when d.insr_type in (1001, 1101,1201) then 1001 else d.insr_type end as produkt,			
			case when d.insr_type in (1001, 1101,1201) and insurance_group ='NA0101' and szkoda_osobowa <> 'BI' 						then catt(1001,"/",insurance_group, '_Property') 
			     when d.insr_type in (1001, 1101,1201) and insurance_group ='NA0101' and szkoda_osobowa = 'BI' and annuity <> 'Annuity' then catt(1001,"/",insurance_group, '_BIwoA') 
			     when d.insr_type in (1001, 1101,1201) and insurance_group ='NA0101' and szkoda_osobowa = 'BI' and annuity = 'Annuity'  then catt(1001,"/",insurance_group, '_Annuity') 
			     when d.insr_type in (1001, 1101,1201) then catt(1001,"/",insurance_group) 
													   else catt(d.insr_type,"/",insurance_group) end as reserve_class*/
  from Database_ResQ d
       left join (select policy_id, channel, sub_channel from arc05tst.sale_channels) sc on sc.policy_id = d.policy_id
       left join (select policy_id, insr_duration from in03prd.policy) p on p.policy_id = d.policy_id
	   left join (select unique insr_type, cover_type, insurance_group, reserve_class, tagetik_lob, macro_lob from arc05tst.cover_lob_knf) k on k.insr_type=d.insr_type and k.cover_type=d.cover_type
;quit;

/* ZMIANY WYMAGANE DO DOSTOSOWANIA SIÊ DO DEFINICJI GENERALI */
/*
		proc sql;
		create table Database_ResQ_1 as 
		select * 
          from Database_ResQ 
         where reserve_class <> '1001 MTPL Annuity';
		;quit;

        proc sql;
		create table Database_ResQ_2 as 
		select * 
          from Database_ResQ 
         where reserve_class = '1001 MTPL Annuity' and Annuity_ugpl is null;
		;quit;
		data Database_ResQ_2;
		set Database_ResQ_2 (drop=reserve_class);
		reserve_class = '1001 MTPL BI wo A';
		run;

        proc sql;
		create table Database_ResQ_3 as 
		select * 
          from Database_ResQ 
         where reserve_class = '1001 MTPL Annuity' and Annuity_ugpl is not null;
		;quit;

		data Database_ResQ;
		set Database_ResQ_1 Database_ResQ_2 Database_ResQ_3;
		run;


/*proc sql;
create table test as
select sub_type, rok, sum(amount)
  from (select d.*, year(hist_change_date_my) as rok 
		  from Database_ResQ d 
		 where (resrerve_class not like '%Ass%' and resrerve_class not like '1001 MTPL Annuity'
            or (reserve_class = '1001 MTPL Annuity' and Annuity_ugpl is null) )
 group by sub_type , rok
;quit;

/*proc sql;
create table Database_ResQ as 
select d.*,
       case when insr_type in (1001, 1101, 1201) and cover_type in ('ASS_PREM_D')     then 'NB0950' 
	        when insr_type in (1001, 1101, 1201) and cover_type in ('CSC_THT_P')      then 'NA0201'
			when insr_type = 3001 and cover_type in ('TPL_LESSEE')                    then 'NB0300'
			when insr_type = 4001 and cover_type in ('CAS_ROB_PL') 			          then 'NC0600'
            else insurance_group end as insurance_group2        
 from nadysk.Database_ResQ d
;quit;
data Database_ResQ;
set Database_ResQ (drop=insurance_group);
insurance_group=insurance_group2;
drop insurance_group2;
run;

/*
proc sql;
create table Database_ResQ as
select d.*, case when insurance_group is null then 'NA0101' else insurance_group end as insurance_group_new
  from Database_ResQ d
 where claim_id is not null
;quit;
data Database_ResQ;
set Database_ResQ;
drop insurance_group;
run;
data Database_ResQ;
set Database_ResQ;
insurance_group= insurance_group_new;
drop insurance_group_new;
run;

proc sql;
select reserve_class, count(*)
  from Database_ResQ
 group by reserve_class 
 order by reserve_class
;quit;
proc sql;
select insurance_group, count(*)
  from Database_ResQ
 group by insurance_group
 order by insurance_group
;quit;
proc sql;
select insurance_group, reserve_class, count(unique claim_id) as ile_claim_id
  from Database_ResQ
 group by insurance_group, reserve_class
 order by insurance_group, reserve_class
;quit;

proc sql;
create table test as
select tagetik_lob, insurance_group, reserve_class, cover_fract_type, count(*) as ile_claim_id
  from arc05tst.cover_lob_knf
 group by tagetik_lob, insurance_group, reserve_class, cover_fract_type
 order by tagetik_lob, insurance_group, reserve_class, cover_fract_type
;quit;

proc sql;
select *
  from Database_ResQ
 where insurance_group = 'OTHER'
;quit;
proc sql;
create table test as 
select *
  from arc05tst.claim_request_data
 where claim_id is null
;quit;

/******************************************************************************************************************************************************************/
/******************************************************************************************************************************************************************/
/* Number of Claims */
/******************************************************************************************************************************************************************/
/******************************************************************************************************************************************************************/

proc sql;
create table claims_reported as 
select insr_type, channel, sub_channel, claim_id, reserve_class, event_date, event_date_my,
       min(registration_date) as registration_date format yymmdd10., 
       min(registration_date_my) as registration_date_my format yymmdd10.
  from (select *
          from Database_ResQ
         where catt(claim_id,'/',request_id) not in (select catt(claim_id,'/',request_id) as lacznik from arc05tst.claim_request_data where claim_state = 11))
 group by insr_type, channel, sub_channel, claim_id, reserve_class, event_date, event_date_my
 order by insr_type, channel, sub_channel, claim_id, reserve_class, event_date, event_date_my
;quit;

/******************************************************************************************************************************************************************/

proc sort data=Database_ResQ out=Database; by policy_id claim_id reserve_class event_date hist_change_date; run;
data Database;
set Database;
where sub_type = 'RESERVE OBJ';
run;
data Database;
set Database;
retain amount_cumulative 0;
by policy_id claim_id reserve_class;
if first.reserve_class then do 
amount_cumulative = amount;
end;
else do; 
amount_cumulative = amount_cumulative + amount;
end;
run;

proc sql;
create table claims_closed as 
select insr_type, channel, sub_channel, claim_id, reserve_class, event_date_my, hist_change_date_my, round(amount_cumulative, 0.01) as suma_rezerwy
  from (select *
          from Database
         where catt(claim_id,'/',request_id) not in (select catt(claim_id,'/',request_id) as lacznik
													   from arc05tst.claim_request_data 
													  where claim_state = 11)  )
 where round(amount_cumulative, 0.01) = 0
 order by insr_type, channel, sub_channel, claim_id, reserve_class, event_date_my, hist_change_date_my
;quit;
proc sql;
create table claims_closed as 
select insr_type, channel, sub_channel, claim_id, reserve_class, event_date_my, min(hist_change_date_my) as hist_change_date_my format yymmdd10.
  from claims_closed
 group by insr_type, channel, sub_channel, claim_id, reserve_class, event_date_my
 order by insr_type, channel, sub_channel, claim_id, reserve_class, event_date_my
;quit;

/******************************************************************************************************************************************************************/
/*
proc sql;
create table claims_closed as 
select insr_type, claim_id, reserve_class, event_date_my, hist_change_date_my, round(sum(amount), 0.01) as suma_rezerwy
  from (select *
          from Database_ResQ
         where catt(claim_id,'/',request_id) not in (select catt(claim_id,'/',request_id) as lacznik from dane_cr.claim_request_data where claim_state = 11))
 where sub_type = 'RESERVE OBJ' and claim_id = '20700025771'
 group by insr_type, claim_id, reserve_class, event_date_my, hist_change_date_my
 order by insr_type, claim_id, reserve_class, event_date_my, hist_change_date_my
;quit;

data test_1;
set claims_open;
where claim_id = '20700003912';
run;

data test_1;
set claims_closed;
where claim_id = '20700003912';
run;

data test_1;
set Database;
where claim_id = '20700003912';
run;

/******************************************************************************************************************************************************************/

proc sql print ;
select distinct year(max(event_date)) as max_year_acc into:max_year_acc
from claims_reported;
quit;
%PUT &max_year_acc;
Data development;
lacznik=1;
format acc_period yymmdd10. dev_period yymmdd10.;
do j=2012 to &max_year_acc by 1;
   do i=1 to 12 by 1;
       do k=i to 12 by 1;
	        ACC_PERIOD=intnx('month',mdy(i,1,j),-0,'end');
	        DEV_PERIOD=intnx('month',mdy(k,1,j),-0,'end');
			DEVELOPMENT=k-i;
	      output;
	  end;
   end;
end;
do j=2012 to &max_year_acc by 1;
   do i=1 to 12 by 1;
       do k=j+1 to year(today()) by 1;
	      do m=1 to 12 by 1;
		  	ACC_PERIOD=intnx('month',mdy(i,1,j),-0,'end');
	        DEV_PERIOD=intnx('month',mdy(m,1,k),-0,'end');
			DEVELOPMENT= (12-i)+(k-j-1)*12+m;
	      output;
		  end;
	  end;
   end;
end;
drop i j k m;
run;
proc sort data=development out=development; by acc_period; run;

proc sql;
create table claims_open as 
select distinct d.insr_type, d.channel, d.sub_channel, d.claim_id, d.reserve_class, d.event_date_my, dev.*,
       case when cc.hist_change_date_my > intnx('quarter',dev_period,-0,'end') or cc.hist_change_date_my is null then 1 else 0 end as amount, cr.registration_date
  from (select *
          from Database_ResQ d
         where catt(claim_id,'/',request_id) not in (select catt(claim_id,'/',request_id) as lacznik from arc05tst.claim_request_data where claim_state = 11))
       left join claims_closed cc on cc.claim_id=d.claim_id and cc.reserve_class=d.reserve_class
       left join claims_reported cr on cr.claim_id=d.claim_id and cr.reserve_class=d.reserve_class
       left join development dev on dev.acc_period=d.event_date_my
 where cr.registration_date_my <= dev_period 
/*   and d.claim_id = '20700022088'*/
 order by d.insr_type, d.channel, d.sub_channel, cc.claim_id, cc.reserve_class, cc.event_date_my, dev_period
;quit;

/******************************************************************************************************************************************************************/
/******************************************************************************************************************************************************************/
/* Eksport */
/******************************************************************************************************************************************************************/
/******************************************************************************************************************************************************************/

		proc sql;
		create table Claims_Big as
		select claim_id, reserve_class, round(sum(amount), 0.01) as incurred
		   from (select * from Database_ResQ where year(hist_change_date_my) <= 2014) d
		 group by claim_id, reserve_class
		having round(sum(amount), 0.01) > 1000000 /* Do DD Reserve - wed³ug Generali*/
		;quit;

		proc sql;
		create table Claims_Big as
		select *
		  from Claims_Big
		 where (reserve_class like '%MTPL%'  and incurred > 500000)
		    or (reserve_class like '%MTPL Property%' and incurred > 100000)
		    or (reserve_class like '%CASCO%' and incurred > 100000)
		    or (reserve_class like '%PA%'    and incurred >  50000)
		    or (reserve_class like '%HOME%'  and incurred > 100000) /* Tak jak w Generali z Deep Dive */
		    or (reserve_class like '%SME%'   and incurred > 100000) 
		 order by reserve_class, incurred desc
		;quit;

options dlcreatedir;
libname nadysk "P:\DEP\actuarial\05 REPORTS - OPERATIONAL\07 Actuary\10 ResQ\Database\Database_&date_end";

proc sql;
create table nadysk.ResQ_Reserves_and_Payments  as 
select insr_type, channel, sub_channel, insurance_group, reserve_class, sub_reserve_class, type, 
       event_date_my, registration_date_my, hist_change_date_my, sum(amount) as amount
  from (
		select insr_type, channel, sub_channel, insurance_group, amount, type, 
			   case when sub_type like '%EXP%' then 'EXP'
			        when sub_type like '%OBJ%' then 'OBJ'
			        when sub_type like '%REG%' then 'REG' else 'Other' end as sub_reserve_class, reserve_class,
/*			   case when reserve_class = '1001 MTPL Annuity' then '1001 MTPL BI wo A' else reserve_class end as reserve_class,*/
		       event_date_my, registration_date_my, hist_change_date_my
		  from Database_ResQ
		 where ((year(hist_change_date) < &rok. ) 
                or (year(hist_change_date) = &rok. and month(hist_change_date) <= &miesiac.)) 
/*		   and catt(claim_id, reserve_class) not in (select catt(claim_id, reserve_class) from Claims_Big)*/
       )
 group by insr_type, channel, sub_channel, insurance_group, reserve_class, sub_reserve_class, type, event_date_my, registration_date_my, hist_change_date_my
 order by insr_type, channel, sub_channel, insurance_group, reserve_class, sub_reserve_class, type, event_date_my, registration_date_my, hist_change_date_my
;quit;

			/*proc sql;
			create table do_pilku as
			select unique reserve_class, account_date_qy, sum(amount) as GWP
			  from (select g.*, intnx('quarter',account_date,-0,'end') as account_date_qy format yymmdd10.,
			               case when insr_type in (1001, 1101,1201) then 1001 else insr_type end as produkt, reserve_class
			          from gl_insis2gl_gwp g)
			 group by reserve_class account_date_qy
			 order by reserve_class, account_date_qy
			;quit;
			proc transpose data=test out=test;
			by reserve_class;
			id account_date_qy;
			var GWP;
			run;*/

proc sql;
create table ResQ_Number_of_Claims_ALL_CL as
select *
  from (
select *
  from (select insr_type, channel, sub_channel, claim_id, reserve_class, event_date_my, registration_date_my as hist_change_date_my format yymmdd10., 
               1 as amount, 'Registered claims' as type
          from claims_reported)
 union all
	   (select insr_type, channel, sub_channel, claim_id, reserve_class, event_date_my, hist_change_date_my format yymmdd10.,
               1 as amount, 'Closed claims' as type
          from claims_closed)
        )
where (year(hist_change_date_my) < &rok ) or (year(hist_change_date_my) = &rok and month(hist_change_date_my) <= &miesiac) 
order by insr_type, channel, sub_channel, claim_id, event_date_my, hist_change_date_my
;quit;

		proc sql;
		create table ResQ_Number_of_Claims_ALL_wo_10 as
		select claim_id, reserve_class, amount, 'Registered claims' as type,
               intnx('quarter',hist_change_date_my,-0,'end') as hist_change_date_qy format yymmdd10.,
               intnx('quarter',event_date_my,-0,'end') as event_date_qy format yymmdd10.
		  from (select * 
				  from Database_ResQ
				 where type <> 'REGRES')d
		 where ((year(hist_change_date) < &rok. ) 
		    or (year(hist_change_date) = &rok. and month(hist_change_date) <= &miesiac.)) 
		/*		   and catt(claim_id, reserve_class) in (select catt(claim_id, reserve_class) from Claims_Big)*/
		 order by claim_id, reserve_class, hist_change_date_my
		;quit;
		proc sql;
		create table ResQ_Number_of_Claims_ALL_wo_10 as
		select claim_id, reserve_class, type, event_date_qy, hist_change_date_qy, sum(amount) as amount
		  from ResQ_Number_of_Claims_ALL_wo_10 d
		 group by claim_id, reserve_class, type, event_date_qy, hist_change_date_qy
		 order by claim_id, reserve_class, type, event_date_qy, hist_change_date_qy
		;quit;
				proc sql;
				create table All_periods as
				select claim_id, reserve_class, event_date_qy, period_qy as hist_change_date_qy
				  from (select unique claim_id, reserve_class, event_date_qy, 1 as lacznik from ResQ_Number_of_Claims_ALL_wo_10) d 
					   left join (select unique intnx('quarter',acc_period,-0,'end') as period_qy format yymmdd10., 1 as lacznik
		                            from development) dev on dev.lacznik=d.lacznik and dev.period_qy >= d.event_date_qy
				 order by claim_id, reserve_class, event_date_qy, period_qy
				;quit;
		proc sql;
		create table ResQ_Number_of_Claims_ALL_wo_100 as
		select p.claim_id, p.reserve_class, p.event_date_qy, p.hist_change_date_qy, amount
		  from All_periods p 
			   left join ResQ_Number_of_Claims_ALL_wo_10 d on p.claim_id=d.claim_id
														  and p.reserve_class=d.reserve_class   
														  and p.hist_change_date_qy=d.hist_change_date_qy               
		 order by p.claim_id, p.reserve_class, p.event_date_qy, p.hist_change_date_qy
		;quit;
		data ResQ_Number_of_Claims_ALL_wo_100;
		 set ResQ_Number_of_Claims_ALL_wo_100;
			array nums _numeric_;
			do over nums;
			if nums=. then nums=0.00;
			end;
		type = 'Registered claims';
		run;
		data ResQ_Number_of_Claims_ALL_wo_100;
		set ResQ_Number_of_Claims_ALL_wo_100;
		retain amount_c 0;
		by claim_id reserve_class hist_change_date_qy;
		if first.reserve_class then do amount_c = amount; end;
		else do; amount_c = amount_c + amount;end;
		run;
		data ResQ_Number_of_Claims_ALL_wo_100;
		set ResQ_Number_of_Claims_ALL_wo_100;
		if amount_c <> 0 then number_of_claims = 1; else number_of_claims = 0;
		drop amount amount_c;
		run;
		proc sql;
		create table nadysk.ResQ_Number_of_Claims_ALL_wo_10 as
		select reserve_class, event_date_qy, hist_change_date_qy, type, sum(number_of_claims) as number_of_claims
		  from ResQ_Number_of_Claims_ALL_wo_100 p 
		 group by reserve_class, event_date_qy, hist_change_date_qy, type
		 order by reserve_class, event_date_qy, hist_change_date_qy, type
		;quit;

proc sql;
create table nadysk.ResQ_Number_of_Claims_OP as 
select unique *
  from (
select insr_type, channel, sub_channel, claim_id, reserve_class, event_date_my, intnx('quarter',dev_period,-0,'end') as hist_change_date_my format yymmdd10., 
       amount, 'Open claims' as type
  from claims_open c
 where amount = 1
   and claim_id is not null
   and ((year(dev_period) < &rok ) or (year(dev_period) = &rok and month(dev_period) <= &miesiac))
      )
 order by insr_type, channel, sub_channel, claim_id, reserve_class, event_date_my, hist_change_date_my
;quit;

proc sql;
create table nadysk.Database_ResQ as 
select *
  from Database_ResQ
;quit;

proc sql;
create table nadysk.paid_hist as 
select *
  from paid_hist
;quit;

proc sql;
create table nadysk.claim_hist as 
select *
  from claim_hist
;quit;

options dlcreatedir;
libname nadyskro "P:\DEP\actuarial\05 REPORTS - OPERATIONAL\07 Actuary\11 Run Off\Database\Database_&date_end";

proc sql;
create table nadyskro.ResQ_Reserves_and_Payments_SUB_2 as 
select insr_type, channel, sub_channel, reserve_class, sub_1_reserve_class, sub_2_reserve_class, type, event_date_my, registration_date_my, hist_change_date_my, sum(amount) as amount
  from (
select insr_type, channel, sub_channel, reserve_class, amount, type, 
	   case when sub_type like '%EXP%' then 'EXP'
	        when sub_type like '%OBJ%' then 'OBJ' else 'Other' end as sub_1_reserve_class,
	   case when year(event_date_my) = year(registration_date_my) then catt(reserve_class," ",'KCR') else catt(reserve_class," ",'IBNR')  end as sub_2_reserve_class,
       event_date_my, registration_date_my, hist_change_date_my
  from Database_ResQ
 where (year(hist_change_date) < &rok. ) or (year(hist_change_date) = &rok. and month(hist_change_date) <= &miesiac.) 
       )
 group by insr_type, channel, sub_channel, reserve_class, sub_1_reserve_class, sub_2_reserve_class, type, event_date_my, registration_date_my, hist_change_date_my
 order by insr_type, channel, sub_channel, reserve_class, sub_1_reserve_class, sub_2_reserve_class, type, event_date_my, registration_date_my, hist_change_date_my
;quit;

/*proc sql;
create table test as 
select unique type
  from nadysk.ResQ_Reserves_and_Payments_SUB
;quit;

/***************************************************************************************************************************************************************************/
/*EXPORT DLA AGATY*/
/***************************************************************************************************************************************************************************/

data database_resq_agata;
set database_resq;
where round(amount,0.01)<> 0;
run;

ods xml body="P:\DEP\Wymiennik\AvF\BINSIS-2703 - Tabela DATABSE_ResQ\BINSIS-2703 - Tabela DATABASE_ResQ &date_end..csv" type=csv;
proc print data=database_resq_agata;
run;
ods xml close;

data _null_;
x %str(%'C:\Program Files\7-Zip\7z.EXE%' u -tzip 
"P:\DEP\Wymiennik\AvF\BINSIS-2703 - Tabela DATABSE_ResQ\BINSIS-2703 - Tabela DATABASE_ResQ &date_end..zip" 
"P:\DEP\Wymiennik\AvF\BINSIS-2703 - Tabela DATABSE_ResQ\BINSIS-2703 - Tabela DATABASE_ResQ &date_end..csv" -r );
run; 

FILENAME MyFile "P:\DEP\Wymiennik\AvF\BINSIS-2703 - Tabela DATABSE_ResQ\BINSIS-2703 - Tabela DATABASE_ResQ &date_end..csv";
  DATA _NULL_ ;
    rc = FDELETE('MyFile') ;
  RUN ;
FILENAME MyFile CLEAR ;

/***************************************************************************************************************************************************************************/
/*WYS£ANIE NA EMAIL*/
/***************************************************************************************************************************************************************************/

x 'cd P:\DEP\Actuarial\05 REPORTS - OPERATIONAL\16 SAS - Macro';
%inc "MIS - email - tekst - MIS.sas";

%let row_num=0;
proc sql noprint;
select count(*) as row_num into: row_num
from nadysk.database_resq;
quit;
%put &row_num;

%macro wyslij_error();
%if &row_num. <= 100 %then %do;

%runtime(&nazwa_raportu,1);

options emailsys=smtp emailhost=email4app.groupama.local emailport=587; 
filename mymail email ("ewelina.cichocka@proama.pl" "luiza.smargol@proama.pl" "barbara.bielesz@proama.pl")
    type = 'text/html' 
 subject = "ERROR - BINSIS-2703 - Tabela DATABASE_ResQ &date_end." 
    from = "Zespol Analiz i Raportowania <ZespolAnalizIRaportowania@proama.pl>"
 replyto = "ZespolAnalizIRaportowania@proama.pl"
      cc = ("ZespolAnalizIRaportowania@proama.pl" );

%let stopka1=" ";
%let stopka2="Raport BINSIS-2703 - Tabela DATABASE_ResQ - wyst¹pi³ b³¹d podczas generowania raportu";
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
filename mymail email ("agata.kariozen@proama.pl" "ewelina.cichocka@proama.pl" "luiza.smargol@proama.pl" "barbara.bielesz@proama.pl")
    type = 'text/html' 
 subject = "C3_BINSIS-2703 - Tabela DATABASE_ResQ &date_end." 
    from = "Zespol Analiz i Raportowania <ZespolAnalizIRaportowania@proama.pl>"
 replyto = "ZespolAnalizIRaportowania@proama.pl"
      cc = ("ZespolAnalizIRaportowania@proama.pl")
  attach = ("P:\DEP\Wymiennik\AvF\BINSIS-2703 - Tabela DATABSE_ResQ\BINSIS-2703 - Tabela DATABASE_ResQ &date_end..zip");

%let stopka1='Witam,';
%let stopka2="Tabela DATABASE_ResQ zosta³a zapisana na dysku, stan na &date_end..";
%let stopka3=' ';

%email_tekst_MIS (&stopka1., &stopka2., &stopka3.);
%end;
%mend; 

%wyslij();

/******************************************************************************************************************************************************************/
/******************************************************************************************************************************************************************/
/* SK£ADKI */
/******************************************************************************************************************************************************************/
/******************************************************************************************************************************************************************/

%biblioteki();

proc sql; 
create table gep_exposure as 
select *
  from arc05tst.gep_exposure 
 where (datepart(data_wyliczenia)<intnx('month',"&sysdate"d,0,'b') and koniec_miesiaca=1) 
/*    or (month(datepart(data_wyliczenia))=month("&sysdate"d) and year(datepart(data_wyliczenia))=year("&sysdate"d) and koniec_miesiaca=0)  */
;quit;

proc sql;
create table premiums as
select insr_type, cover_type, data_wyliczenia, sum(exposure) as exposure, sum(gep) as gep
  from gep_exposure
 where gep <> .
    or gep <> 0
 group by insr_type, cover_type, data_wyliczenia
 order by insr_type, cover_type, data_wyliczenia
;quit;
%change_datetime_format(premiums,data_wyliczenia);

proc sql;
create table ResQ_GEP_and_EXPOSURE as
select p.*, insurance_group, tagetik_lob, macro_lob, reserve_class
  from premiums p
	   left join (select unique insr_type, cover_type, insurance_group, reserve_class, tagetik_lob, macro_lob 
                    from arc05tst.cover_lob_knf) k on k.insr_type=p.insr_type and k.cover_type=p.cover_type
;quit;
data ResQ_GEP_and_EXPOSURE;
set ResQ_GEP_and_EXPOSURE;
     if reserve_class = '1001 MTPL' then exposure = exposure/2; 
else if reserve_class = '1001 CASCO' then exposure = exposure/4; 
else exposure=exposure;
run;

proc sql;
create table ResQ_GEP_and_EXPOSURE as
select *
  from (
select *
  from (select insr_type, reserve_class, 'EXPOSURE' as type, exposure as amount, data_wyliczenia
          from ResQ_GEP_and_EXPOSURE)
 union all
	   (select insr_type, reserve_class, 'GEP' as type, gep as amount, data_wyliczenia
          from ResQ_GEP_and_EXPOSURE)
	   )
 order by insr_type, reserve_class, type, data_wyliczenia
;quit;

libname nadysk "P:\DEP\actuarial\05 REPORTS - OPERATIONAL\07 Actuary\10 ResQ\Database\Database_&date_end";

proc sql;
create table nadysk.ResQ_GEP_and_EXPOSURE  as 
select *
  from ResQ_GEP_and_EXPOSURE
;quit;
