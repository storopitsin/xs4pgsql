--
-- PostgreSQL database dump
--

-- Dumped from database version 14.5
-- Dumped by pg_dump version 15.1

-- Started on 2023-04-09 03:50:04

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 6 (class 2615 OID 25035)
-- Name: xs; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA xs;


ALTER SCHEMA xs OWNER TO postgres;

--
-- TOC entry 3333 (class 0 OID 0)
-- Dependencies: 6
-- Name: SCHEMA xs; Type: COMMENT; Schema: -; Owner: postgres
--

COMMENT ON SCHEMA xs IS 'eXtended Sheet';


--
-- TOC entry 218 (class 1255 OID 25036)
-- Name: eval2text(text); Type: FUNCTION; Schema: xs; Owner: postgres
--

CREATE FUNCTION xs.eval2text(expression text) RETURNS text
    LANGUAGE plpgsql
    AS $$
declare
  result text;
begin
  execute expression into result;
  return result;
exception when others then
	raise notice 'xs.eval2text(text): error on calculate expression: "%"', expression;
	raise notice '% %', SQLERRM, SQLSTATE;
    return null;
end;
$$;


ALTER FUNCTION xs.eval2text(expression text) OWNER TO postgres;

--
-- TOC entry 220 (class 1255 OID 25037)
-- Name: eval2text(text, json); Type: FUNCTION; Schema: xs; Owner: postgres
--

CREATE FUNCTION xs.eval2text(expression text, param json) RETURNS text
    LANGUAGE plpgsql
    AS $$
declare
  result text;
begin
	if( param is null ) then
		execute expression into "result";
	else
		execute expression into "result" using param;
	end if;
	return "result";
exception when others then
	raise notice 'xs.eval2text(text, json): error on calculate expression: "%"', expression;
	raise notice '% %', SQLERRM, SQLSTATE;
    return null;
end;
$$;


ALTER FUNCTION xs.eval2text(expression text, param json) OWNER TO postgres;

--
-- TOC entry 221 (class 1255 OID 25038)
-- Name: eval2text(text, json, text); Type: FUNCTION; Schema: xs; Owner: postgres
--

CREATE FUNCTION xs.eval2text(expression text, param json, origin text) RETURNS text
    LANGUAGE plpgsql
    AS $$
declare
  "result" text;
begin
	if( param is null ) then
		execute expression into "result";
	else
		execute expression into "result" using param;
	end if;
	return "result";
exception when others then
	raise notice 'xs.eval2text(text, json, text): "%" error on calculate expression: "%"', origin, "expression";
	raise notice '% %', SQLERRM, SQLSTATE;
    return null;
end;
$$;


ALTER FUNCTION xs.eval2text(expression text, param json, origin text) OWNER TO postgres;

--
-- TOC entry 238 (class 1255 OID 25041)
-- Name: eval4cell(json, text, json, text[]); Type: FUNCTION; Schema: xs; Owner: postgres
--

CREATE FUNCTION xs.eval4cell(expr json, address text, cells json, stack text[]) RETURNS text
    LANGUAGE plpgsql
    AS $_$
declare
  result text;
  inparam json;
  instack text;
  newstack text[];
begin
	-- raise notice 'xs.eval4cell(json, text, json, text[]): in calculate cell: "%" expression: "%"', address, expr->>'F';
	-- проверяем
	-- instack = (with st as (select unnest(stack) "addr") select "addr" from st where "addr" = address);
	instack = (with st as (select unnest(stack) "addr") select "addr" from st where "addr"=address);
	if (instack is not null) then
		-- предотвращаем рекурсию
		return null;
	else
		if(address is not null) then
			-- адрес задан, добавляем в стэк
			newstack = (select coalesce(stack || array[address]::text[], array[address]::text[]));
		end if;
		if(address is not null) then
			-- адрес известен, ищем значение в кэше
			-- raise notice 'xs.eval4cell(json, text, json, text[]): search cell: "%"', address;
			result = (select "value" from xs_cache_temp_table where "key" = address);
			if(result is not null) then
				-- raise notice 'xs.eval4cell(json, text, json, text[]): for cell: "%" found "%"', address, result;
				return result;
			end if;
		end if;
		if (expr is null) then
			expr = (
				with cell_map as (
					select "key", "value" "cell" from json_each( cells ) "cell_map"
				)
				select "cell" from cell_map
				where "key" = address
			);
		end if;
		if (expr is null) then
			return null;
		else
			if (expr->'V' is not null) then
				if(address is not null) then
					-- адрес задан, добавляем в стэк
					-- raise notice 'xs.eval4cell(json, text, json, text[]): for cell: "%" are caching value "%"', address, expr->>'V';
					insert into xs_cache_temp_table ("key", "value") values(address, expr->>'V');
				end if;
				return expr->>'V';
			else
				-- получаем параметры
				inparam = (
					with cell_map as (
						select "key", "value" "cell" from json_each( cells ) "cell_map"
					)
					--select json_object_agg(pms."key", cell_map."cell")
					select json_object_agg(
						pms."key"
						, case when cell_map."cell"->'V' is not null then
							cell_map."cell"->>'V'
						else
							xs.eval4cell(cell_map."cell", cell_map."key", cells, newstack)
						end
					)
					from json_each(expr->'P') pms 
					left outer join cell_map on cell_map."key" = pms."value"#>>'{}'
				);
				-- вычисляем формулу из ячейки
				-- execute 'select ' || (expr->>'F')
				-- into result using inparam;
				-- return result;
				result = (
					with "names" as (
						select string_agg('"' || format("name") || '" text', ', ') "name"
						from json_object_keys( inparam ) "name"
					)
					, prep as (
						select
							"names"."name"
							,'select * from json_to_record($1) as x(' || "names"."name"::text || ') ' "params"
						from "names"
					)
					, prep2 as (
						select
							prep."params"
							,case
								when prep."params" is null then
									'select (' || (expr->>'F') || ')'
								else
									'with params as (' || prep."params" || ') select (' || (expr->>'F') || ') from params'
							end  "expression"
							,inparam "param"
						from prep
					)
					select xs.eval2text(prep2."expression", prep2."param", address) "result" from prep2
					-- select xs.eval2text(prep2."expression", prep2."param", address) "result" from prep2
				);
				if(address is not null) then
					-- адрес задан, добавляем в стэк
					-- raise notice 'xs.eval4cell(json, text, json, text[]): for cell: "%" are caching value "%"', address, result;
					insert into xs_cache_temp_table ("key", "value") values(address, result);
				end if;
				return result;
			end if;
		end if;
	end if;
exception when others then
	raise notice 'xs.eval4cell(json, text, json, text[]): error on calculate cell: "%" expression: "%"', address, expr->>'F';
	raise notice '% %', SQLERRM, SQLSTATE;
    return null;
end;
$_$;


ALTER FUNCTION xs.eval4cell(expr json, address text, cells json, stack text[]) OWNER TO postgres;

--
-- TOC entry 233 (class 1255 OID 25042)
-- Name: merge2json(json, json); Type: FUNCTION; Schema: xs; Owner: postgres
--

CREATE FUNCTION xs.merge2json(json1 json, json2 json) RETURNS json
    LANGUAGE plpgsql
    AS $$
declare
	result json;
begin
	result = (with all_json_key_value as (
	  select "key", "value" from json_each( json1 ) as t1
	  union all
	  select "key", "value" from json_each( json2 ) as t2
	)
	select json_object_agg("key", "value") 
	from all_json_key_value);
	return result;
end;
$$;


ALTER FUNCTION xs.merge2json(json1 json, json2 json) OWNER TO postgres;

--
-- TOC entry 234 (class 1255 OID 25043)
-- Name: n0(text, numeric); Type: FUNCTION; Schema: xs; Owner: postgres
--

CREATE FUNCTION xs.n0(text, numeric DEFAULT 0.0) RETURNS numeric
    LANGUAGE plpgsql
    AS $_$
DECLARE x NUMERIC;
BEGIN
    x = coalesce(xs.text2numeric($1), $2);
    RETURN x;
END;
$_$;


ALTER FUNCTION xs.n0(text, numeric) OWNER TO postgres;

--
-- TOC entry 235 (class 1255 OID 25044)
-- Name: n1(text, numeric); Type: FUNCTION; Schema: xs; Owner: postgres
--

CREATE FUNCTION xs.n1(text, numeric DEFAULT 1.0) RETURNS numeric
    LANGUAGE plpgsql
    AS $_$
DECLARE x NUMERIC;
BEGIN
    x = coalesce(xs.text2numeric($1), $2);
    RETURN x;
END;
$_$;


ALTER FUNCTION xs.n1(text, numeric) OWNER TO postgres;

--
-- TOC entry 219 (class 1255 OID 25045)
-- Name: nn(text, numeric); Type: FUNCTION; Schema: xs; Owner: postgres
--

CREATE FUNCTION xs.nn(text, numeric DEFAULT NULL::numeric) RETURNS numeric
    LANGUAGE plpgsql
    AS $_$
DECLARE x NUMERIC;
BEGIN
    x = coalesce(xs.text2numeric($1), $2);
    RETURN x;
END;
$_$;


ALTER FUNCTION xs.nn(text, numeric) OWNER TO postgres;

--
-- TOC entry 239 (class 1255 OID 25049)
-- Name: table2calc(text, boolean, json); Type: FUNCTION; Schema: xs; Owner: postgres
--

CREATE FUNCTION xs.table2calc(tablename text, skipemptycell boolean DEFAULT true, params json DEFAULT NULL::json) RETURNS TABLE(key text, value text)
    LANGUAGE plpgsql
    AS $$
begin
	-- raise notice 'xs.table2calc(text, boolean, json): "%"', 'in';
	-- создаем временную таблицу для кэширования посчитанных значений ячеек
	drop table if exists xs_cache_temp_table;
	create temporary table xs_cache_temp_table (
	   "key" text,
	   "value" text
	) on commit drop;
	insert into xs_cache_temp_table ("key", "value") values("key", "value");
	-- возвращаем пересчитанную таблицу имя_ячейки (ключ) - значение_ячейки
	return query
	with jssr as (
		select xs."table2json"(tablename, skipemptycell) cell_map
	)
	, jssr_ex as (
		select cell_map, xs.merge2json(cell_map, coalesce(params, '{}'::json)) cell_map_ex from jssr
	)
	, cell_map as (
		select cell_map."key", cell_map."value" "cell" from jssr, json_each( jssr."cell_map" ) cell_map
	)
	, cells as (
		select
			cell_map."key"
			, case
				when cell_map."cell"->'V' is not null then
					cell_map."cell"->>'V'
				when cell_map."cell"->'F' is not null then
					xs.eval4cell(cell_map."cell", cell_map."key", jssr_ex."cell_map_ex", array[]::text[])
				else "cell"::text
			end "value"
		from cell_map
		left outer join jssr_ex on true
	)
	select cells."key", cells."value" from cells;
--exception when others then
--    return null;
end;
$$;


ALTER FUNCTION xs.table2calc(tablename text, skipemptycell boolean, params json) OWNER TO postgres;

--
-- TOC entry 236 (class 1255 OID 25050)
-- Name: table2json(text, boolean); Type: FUNCTION; Schema: xs; Owner: postgres
--

CREATE FUNCTION xs.table2json(tablename text, skipemptycell boolean DEFAULT true) RETURNS json
    LANGUAGE plpgsql
    AS $_$
declare
	"result" json;
	cmd text;
begin
	-- raise notice 'xs.table2json(text, boolean): "%"', 'in';
	cmd = format('with jsrows as ('||chr(13)||chr(10)
		|| 'select row_num, row_to_json(sh) "jsrow" from %s sh order by row_num'||chr(13)||chr(10)
		|| ')'||chr(13)||chr(10)
		|| ', tcells as ('||chr(13)||chr(10)
		|| 'select row_num, "key" || row_num "key", "value", ("value"#>>''{}'') is null'||chr(13)||chr(10)
		|| 'from jsrows, json_each( jsrows."jsrow" ) "jseach"'||chr(13)||chr(10)
		|| 'where "key"<>''row_num'''||chr(13)||chr(10)
		|| 'and (($1 = false) or ("value"#>>''{}'') is not null)'||chr(13)||chr(10)
		|| '-- similar to -> and "value"::text<>''null'''||chr(13)||chr(10)
		|| ')'||chr(13)||chr(10)
		|| 'select json_object_agg("key", "value") "cell_map" from tcells;', tableName);

	-- выполняем запрос
	execute cmd	into result using skipEmptyCell;
	-- raise notice 'xs.table2json(text, boolean): "%"', 'out';
	return result;
--exception when others then
--    return null;
end;
$_$;


ALTER FUNCTION xs.table2json(tablename text, skipemptycell boolean) OWNER TO postgres;

--
-- TOC entry 237 (class 1255 OID 25051)
-- Name: text2numeric(text); Type: FUNCTION; Schema: xs; Owner: postgres
--

CREATE FUNCTION xs.text2numeric(text) RETURNS numeric
    LANGUAGE plpgsql IMMUTABLE STRICT
    AS $_$
DECLARE x NUMERIC;
BEGIN
    x = $1::NUMERIC;
    RETURN x;
EXCEPTION WHEN others THEN
    RETURN null;
END;
$_$;


ALTER FUNCTION xs.text2numeric(text) OWNER TO postgres;

-- Completed on 2023-04-09 03:50:04

--
-- PostgreSQL database dump complete
--

