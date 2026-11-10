# GeoSmart Civil: cómo ponerlo en internet

Esta carpeta es la página web completa de GeoSmart Civil. Funciona en dos modos:

- **Modo demostración:** si `config.js` está vacío. Se entra eligiendo un perfil y los cambios no se guardan. Sirve para probar.
- **Modo real:** con Supabase configurado. Hay cuentas con correo y contraseña, los datos se guardan en la nube y **cada empresa ve solo sus obras**.

Contenido de la carpeta:

| Archivo | Para qué sirve |
|---|---|
| `index.html` | La página completa |
| `config.js` | Dirección y clave pública de Supabase (paso 1) |
| `supabase/1-esquema.sql` | Crea tablas, roles y reglas de seguridad |
| `supabase/2-datos-ejemplo.sql` | Carga 3 empresas y obras de ejemplo (opcional) |
| `img/ejemplos/` | Fotos reales de ejemplo (créditos en `CREDITOS.md`) |
| `robots.txt`, `sitemap.xml` | Para que Google encuentre la página |

---

## Paso 1. Crear la base de datos en Supabase

1. Entra a https://supabase.com, crea una cuenta y luego un proyecto nuevo (por ejemplo `geosmart-civil`). Elige la región más cercana (São Paulo) y guarda la contraseña de la base de datos.
2. En el menú izquierdo abre **SQL Editor**, pega todo el contenido de `supabase/1-esquema.sql` y presiona **Run**.
3. Si quieres las obras de ejemplo, haz lo mismo con `supabase/2-datos-ejemplo.sql`.
4. Ejecuta también `supabase/3-google.sql` (permite entrar con Google y pide completar el registro la primera vez).

### Activar "Continuar con Google"

1. En https://console.cloud.google.com crea un proyecto, configura la **pantalla de consentimiento OAuth** (tipo Externo) y crea un **ID de cliente OAuth** de tipo "Aplicación web".
2. En **URI de redireccionamiento autorizados** pon: `https://przvfyhxtuijwzlthntz.supabase.co/auth/v1/callback`
3. En Supabase, abre **Authentication > Sign In / Providers > Google**, actívalo y pega el **Client ID** y el **Client Secret**. Guarda.
4. Ve a **Project Settings > API** y copia:
   - **Project URL**
   - La clave **anon public**
5. Pégalas en `config.js`:

   ```js
   window.GEOSMART_CONFIG = {
     SUPABASE_URL: "https://xxxxxxxx.supabase.co",
     SUPABASE_ANON_KEY: "eyJhbGciOi..."
   };
   ```

   La clave **anon** es pública y puede ir en la página. **Nunca** pongas ni compartas la clave **service_role**.

## Paso 2. Publicar la página en GitHub Pages

1. Entra a https://github.com y crea una cuenta.
2. Crea un repositorio **público** llamado `geosmart-civil`.
3. En el repositorio, presiona **Add file > Upload files** y arrastra **todo el contenido** de esta carpeta, incluidas las carpetas `img` y `supabase`. Luego presiona **Commit changes**.
4. Ve a **Settings > Pages**. En "Branch" elige `main` y la carpeta `/ (root)`, y guarda.
5. En uno o dos minutos la página estará en: `https://TU-USUARIO.github.io/geosmart-civil/`

## Paso 3. Conectar Supabase con la dirección de la página

En Supabase, abre **Authentication > URL Configuration**:

- **Site URL:** `https://TU-USUARIO.github.io/geosmart-civil/`
- **Redirect URLs:** agrega esa misma dirección.

Así funcionan los correos de confirmación de cuenta y de "olvidé mi contraseña".

## Paso 4. Crear el administrador (equipo GeoSmart)

1. Entra a la página publicada y crea tu cuenta con **Crear cuenta**. Confirma tu correo.
2. En Supabase, abre el **SQL Editor** y ejecuta (cambia el correo):

   ```sql
   update public.perfiles set rol = 'admin'
   where id = (select id from auth.users where email = 'tu-correo@ejemplo.com');
   ```

3. Vuelve a iniciar sesión. Como administrador ves todas las empresas y obras. En **Usuarios y configuración** puedes dar a otros los roles de operador o revisor.

## Cómo se registran los clientes

- Un cliente nuevo crea su cuenta escribiendo el nombre de su empresa. Se crea su empresa y entra a un panel vacío.
- Sus compañeros se unen con el **código de empresa**, que aparece en **Usuarios y configuración**.
- El equipo GeoSmart registra las obras de cada empresa, carga los vuelos y publica las alertas.
- Para probar las obras de ejemplo, crea una cuenta con el código `DEMOVLA1`, `DEMOLPR2` o `DEMOLCE3`: verás solo la obra de esa empresa.

## Paso 5. Que Google encuentre la página

1. En `robots.txt` y `sitemap.xml`, cambia `TU-USUARIO` por tu usuario de GitHub y vuelve a subir esos dos archivos.
2. Entra a https://search.google.com/search-console, agrega la propiedad con el **prefijo de URL** `https://TU-USUARIO.github.io/geosmart-civil/` y verifícala con el método **Etiqueta HTML**: copia la etiqueta `<meta name="google-site-verification" ...>` y pégala en `index.html`, debajo de `<meta name="robots" ...>`. Sube el archivo y presiona **Verificar**.
3. En **Sitemaps**, envía `sitemap.xml`.
4. En **Inspección de URLs**, pega la dirección de la página y presiona **Solicitar indexación**.

Google suele tardar de unos días a algunas semanas en mostrarla. Solo se indexa la portada pública (inicio de sesión y descripción); el contenido de cada empresa es privado.

## Conectar el dron

En **Monitoreos con dron**, el equipo GeoSmart (operador, revisor o administrador) tiene dos opciones:

**1. Conectar dron (importar un vuelo)**

1. Conecta el dron a la computadora con su cable USB y enciéndelo, o inserta su tarjeta microSD en la computadora.
2. Presiona **Conectar dron** y luego **Elegir carpeta del dron**. Elige la carpeta `DCIM` (o la carpeta del vuelo).
3. La página lee de cada foto la fecha, la hora, el GPS, la altura y el modelo del dron. Muestra un resumen con el recorrido, la altura promedio y el área recorrida, y avisa si el vuelo está a más de 2 km de la obra.
4. Elige la fecha del vuelo (si hay varias), marca las fotos y asígnales una zona. Presiona **Crear monitoreo y subir fotos**.
5. El monitoreo queda "en proceso". Completa el número DGAC y el control de calidad para publicarlo al cliente.

Las fotos se reducen a 2048 px antes de subir para no llenar el almacenamiento gratuito (se puede desactivar). Cada foto guarda sus coordenadas y se puede abrir en Google Maps.

**2. Transmisión en vivo**

1. En la app del dron (por ejemplo DJI Fly o DJI Pilot 2) elige transmitir en vivo a **YouTube**, con visibilidad **No listado**.
2. Copia el enlace de la transmisión y pégalo en la tarjeta **Transmisión en vivo del dron** de la obra.
3. El cliente de esa empresa verá el vuelo en vivo dentro de su panel. Al terminar, presiona **Quitar transmisión**.

Un navegador no puede controlar el dron ni recibir su video directamente; por eso la conexión se hace con la memoria del dron (fotos) y con YouTube Live (video).

## Límites de esta versión

- Las reglas de la base de datos impiden que una empresa vea los datos de otra. Algunas reglas finas (por ejemplo, que solo el revisor valide alertas) se controlan en la página, no en la base de datos.
- El plan gratuito de Supabase pausa el proyecto tras una semana sin uso; se reactiva desde el panel de Supabase.
- Las fotos que suba el equipo se guardan en el almacenamiento privado de Supabase (plan gratuito: 1 GB).
