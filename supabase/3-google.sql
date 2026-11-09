-- =====================================================================
-- GeoSmart Civil: inicio de sesión con Google
-- Ejecuta este archivo DESPUÉS de 1-esquema.sql (y del 2 si lo usaste).
-- Quien entra con Google no llena el formulario de registro, así que la
-- página le pide completar sus datos (cargo y empresa) la primera vez.
-- =====================================================================

-- Marca si el usuario ya completó su registro (los existentes quedan completos)
alter table public.perfiles add column if not exists completo boolean not null default true;

-- Al crear la cuenta: con el formulario queda completo; con Google, pendiente
create or replace function public.nuevo_usuario() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  emp uuid;
  meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  cod text := upper(trim(coalesce(meta->>'codigo_empresa', '')));
  nom_emp text := trim(coalesce(meta->>'empresa', ''));
  r text := coalesce(meta->>'rol', 'residente');
  nom text := coalesce(nullif(meta->>'nombre', ''), nullif(meta->>'full_name', ''), nullif(meta->>'name', ''), split_part(new.email, '@', 1));
begin
  if r not in ('residente','supervisor') then r := 'residente'; end if;
  if cod <> '' then
    select id into emp from public.empresas where codigo = cod;
    if emp is null then raise exception 'Código de empresa no válido'; end if;
  else
    insert into public.empresas (nombre)
      values (coalesce(nullif(nom_emp, ''), 'Empresa de ' || nom))
      returning id into emp;
  end if;
  insert into public.perfiles (id, nombre, cargo, empresa_id, rol, completo)
    values (new.id, nom, coalesce(meta->>'cargo', ''), emp, r, meta ? 'rol');
  return new;
end $$;

-- Completar el registro (o cambiarse de empresa con un código)
create or replace function public.completar_registro(p_nombre text, p_rol text, p_empresa text, p_codigo text)
returns text language plpgsql security definer set search_path = public as $$
declare
  yo public.perfiles;
  emp uuid;
  vieja uuid;
  cod text := upper(trim(coalesce(p_codigo, '')));
begin
  select * into yo from public.perfiles where id = auth.uid();
  if yo.id is null then raise exception 'Sin perfil'; end if;
  vieja := yo.empresa_id;
  if cod <> '' then
    select id into emp from public.empresas where codigo = cod;
    if emp is null then raise exception 'Código de empresa no válido'; end if;
  else
    emp := vieja;
    if coalesce(trim(p_empresa), '') <> '' and (select count(*) from public.perfiles where empresa_id = vieja) = 1 then
      update public.empresas set nombre = trim(p_empresa) where id = vieja;
    end if;
  end if;
  update public.perfiles set
    nombre = coalesce(nullif(trim(p_nombre), ''), nombre),
    cargo = case when rol in ('residente','supervisor') and p_rol = 'supervisor' then 'Supervisor de obra'
                 when rol in ('residente','supervisor') and p_rol = 'residente' then 'Ingeniero residente'
                 else cargo end,
    rol = case when rol in ('residente','supervisor') and p_rol in ('residente','supervisor') then p_rol else rol end,
    empresa_id = emp,
    completo = true
  where id = yo.id;
  -- Si la empresa automática quedó vacía, se elimina
  if emp is distinct from vieja
     and not exists (select 1 from public.perfiles where empresa_id = vieja)
     and not exists (select 1 from public.registros where empresa_id = vieja) then
    delete from public.empresas where id = vieja;
  end if;
  return (select nombre from public.empresas where id = emp);
end $$;
grant execute on function public.completar_registro(text, text, text, text) to authenticated;
