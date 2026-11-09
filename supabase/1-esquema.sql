-- =====================================================================
-- GeoSmart Civil: base de datos para Supabase
-- Cómo usarlo: en Supabase abre "SQL Editor", pega TODO este archivo y
-- presiona "Run". Se ejecuta una sola vez por proyecto.
-- =====================================================================

-- 1) Empresas (cada cliente pertenece a una empresa)
create table if not exists public.empresas (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  codigo text unique not null default upper(substr(md5(random()::text), 1, 8)),
  creado timestamptz not null default now()
);

-- 2) Perfiles de usuario (uno por cuenta)
--    rol: residente y supervisor son clientes; operador, revisor y admin son el equipo GeoSmart.
create table if not exists public.perfiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nombre text not null default '',
  cargo text not null default '',
  telefono text not null default '',
  empresa_id uuid references public.empresas(id),
  rol text not null default 'residente' check (rol in ('residente','supervisor','operador','revisor','admin')),
  creado timestamptz not null default now()
);

-- 3) Registros del panel: obras, vuelos, comparaciones, alertas, avance, etc.
--    coleccion: projects, flights, comparisons, alerts, activities, deliverables,
--               requests, surveys, tests, reports, meta
create table if not exists public.registros (
  coleccion text not null,
  id text not null,
  empresa_id uuid references public.empresas(id) on delete cascade,
  data jsonb not null default '{}'::jsonb,
  actualizado timestamptz not null default now(),
  primary key (coleccion, id)
);
create index if not exists registros_empresa_idx on public.registros (empresa_id);

-- 4) Funciones de apoyo (se ejecutan con permisos del sistema para no caer en bucles de seguridad)
create or replace function public.mi_empresa() returns uuid
language sql stable security definer set search_path = public as $$
  select empresa_id from public.perfiles where id = auth.uid()
$$;

create or replace function public.mi_rol() returns text
language sql stable security definer set search_path = public as $$
  select rol from public.perfiles where id = auth.uid()
$$;

create or replace function public.es_equipo() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select rol in ('operador','revisor','admin') from public.perfiles where id = auth.uid()), false)
$$;

-- Permite comprobar un código de empresa antes de registrarse (solo devuelve el nombre)
create or replace function public.empresa_por_codigo(cod text) returns text
language sql stable security definer set search_path = public as $$
  select nombre from public.empresas where codigo = upper(trim(cod))
$$;
grant execute on function public.empresa_por_codigo(text) to anon, authenticated;

-- 5) Al registrarse: crea el perfil y une al usuario a su empresa
--    - Con código de empresa válido: se une a esa empresa.
--    - Sin código: se crea una empresa nueva con el nombre que escribió.
--    - Nadie puede registrarse como equipo GeoSmart; eso lo asigna un admin.
create or replace function public.nuevo_usuario() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  emp uuid;
  cod text := upper(trim(coalesce(new.raw_user_meta_data->>'codigo_empresa', '')));
  nom_emp text := trim(coalesce(new.raw_user_meta_data->>'empresa', ''));
  r text := coalesce(new.raw_user_meta_data->>'rol', 'residente');
begin
  if r not in ('residente','supervisor') then r := 'residente'; end if;
  if cod <> '' then
    select id into emp from public.empresas where codigo = cod;
    if emp is null then raise exception 'Código de empresa no válido'; end if;
  else
    insert into public.empresas (nombre)
      values (coalesce(nullif(nom_emp, ''), 'Empresa de ' || coalesce(new.raw_user_meta_data->>'nombre', new.email)))
      returning id into emp;
  end if;
  insert into public.perfiles (id, nombre, cargo, empresa_id, rol)
    values (new.id, coalesce(new.raw_user_meta_data->>'nombre', ''), coalesce(new.raw_user_meta_data->>'cargo', ''), emp, r);
  return new;
end $$;

drop trigger if exists al_crear_usuario on auth.users;
create trigger al_crear_usuario after insert on auth.users
  for each row execute function public.nuevo_usuario();

-- 6) Seguridad por filas (RLS): cada empresa ve solo lo suyo; el equipo GeoSmart ve todo
alter table public.empresas  enable row level security;
alter table public.perfiles  enable row level security;
alter table public.registros enable row level security;

drop policy if exists "empresas_ver" on public.empresas;
create policy "empresas_ver" on public.empresas for select to authenticated
  using (id = public.mi_empresa() or public.es_equipo());
drop policy if exists "empresas_equipo" on public.empresas;
create policy "empresas_equipo" on public.empresas for all to authenticated
  using (public.es_equipo()) with check (public.es_equipo());

drop policy if exists "perfiles_ver" on public.perfiles;
create policy "perfiles_ver" on public.perfiles for select to authenticated
  using (id = auth.uid() or empresa_id = public.mi_empresa() or public.es_equipo());
-- Cada uno edita sus datos, pero no puede cambiarse el rol ni la empresa
drop policy if exists "perfiles_editar_propio" on public.perfiles;
create policy "perfiles_editar_propio" on public.perfiles for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid() and rol = public.mi_rol() and empresa_id is not distinct from public.mi_empresa());
-- El admin cambia roles y empresas
drop policy if exists "perfiles_admin" on public.perfiles;
create policy "perfiles_admin" on public.perfiles for update to authenticated
  using (public.mi_rol() = 'admin') with check (public.mi_rol() = 'admin');

-- Clientes: no ven borradores de alertas, vuelos sin publicar ni datos internos del equipo
drop policy if exists "registros_ver" on public.registros;
create policy "registros_ver" on public.registros for select to authenticated
  using (
    public.es_equipo()
    or (
      empresa_id = public.mi_empresa()
      and coleccion not in ('tests','meta')
      and not (coleccion = 'alerts'  and coalesce(data->>'internal','') <> 'publicada')
      and not (coleccion = 'flights' and coalesce(data->>'status','')   <> 'publicado')
    )
  );

drop policy if exists "registros_crear" on public.registros;
create policy "registros_crear" on public.registros for insert to authenticated
  with check (
    public.es_equipo()
    or (empresa_id = public.mi_empresa() and coleccion in ('projects','comparisons','activities','requests','surveys','reports'))
  );

drop policy if exists "registros_editar" on public.registros;
create policy "registros_editar" on public.registros for update to authenticated
  using (
    public.es_equipo()
    or (empresa_id = public.mi_empresa() and coleccion in ('projects','comparisons','activities','requests')
        or (empresa_id = public.mi_empresa() and coleccion = 'alerts' and data->>'internal' = 'publicada'))
  )
  with check (
    public.es_equipo()
    or (empresa_id = public.mi_empresa() and coleccion in ('projects','comparisons','activities','requests')
        or (empresa_id = public.mi_empresa() and coleccion = 'alerts' and data->>'internal' = 'publicada'))
  );

drop policy if exists "registros_borrar" on public.registros;
create policy "registros_borrar" on public.registros for delete to authenticated
  using (public.es_equipo());

-- 7) Actualización en vivo (los cambios aparecen sin recargar)
do $$ begin
  alter publication supabase_realtime add table public.registros;
exception when duplicate_object then null; end $$;

-- 8) Almacenamiento de fotos y entregables (privado; carpeta = id de la empresa)
insert into storage.buckets (id, name, public) values ('fotos', 'fotos', false)
  on conflict (id) do nothing;

drop policy if exists "fotos_ver" on storage.objects;
create policy "fotos_ver" on storage.objects for select to authenticated
  using (bucket_id = 'fotos' and ((storage.foldername(name))[1] = public.mi_empresa()::text or public.es_equipo()));
drop policy if exists "fotos_subir" on storage.objects;
create policy "fotos_subir" on storage.objects for insert to authenticated
  with check (bucket_id = 'fotos' and public.es_equipo());
drop policy if exists "fotos_borrar" on storage.objects;
create policy "fotos_borrar" on storage.objects for delete to authenticated
  using (bucket_id = 'fotos' and public.es_equipo());
