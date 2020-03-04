--

select 
	et.cuit,
    et.provincia as province, 
	coords.lat, 
    coords.longit,
    et.c_empleadora as is_employer,
    et.tamanio as size,
    et.macro_sector,
    if(et.c_rap_crecimiento>0,1,0) as fast_growth,
    if(et.c_importadora>0,1,0) as importing,
	if(et.c_exportadora>0,1,0) as exporting,    
	case when et.c_cliente_bice then 1
		when et.c_usa_gde then 1
		when et.c_encuestada then 1
		when et.p_registro_pyme then 1
		when et.p_bonos_bk then 1
		when et.p_exporta_simple then 1
		when et.p_fondo_semilla then 1
		when et.p_ctit then 1
		else 0 end as is_client    
    
from empresas_target  et
	inner join coords on coords.provincia = et.provincia
	where et.macro_sector !='Desconocido' and et.provincia !='' and et.provincia != 'N/A';
-- 	group by empresas_target.provincia, coords.lat, coords.longit order by empresas_target.provincia;
    