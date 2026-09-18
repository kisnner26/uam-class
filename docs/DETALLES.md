# UAM Class

App macOS nativa para el portal virtual de UAM. Diseñada como "Moodle con superpoderes": todo lo que hace Moodle web, más un montón de cosas que Moodle no tiene.

Hecha en SwiftUI, sin dependencias externas, empaquetada como `.app`.

## Instalación

```bash
# 1. Requerimientos: macOS 26+ (Tahoe / Golden Gate) y Xcode 26+
#
#    El piso es 26 por el diseño, no por las APIs: macOS decide si una app
#    recibe Liquid Glass leyendo el campo `sdk` de LC_BUILD_VERSION, y SwiftPM
#    lo estampa con el deployment target. Con un target menor a 26 el sistema
#    aplica el modo de compatibilidad heredado y todo el vidrio se degrada.
#    Verificable con:
#      otool -l "UAM Class.app/Contents/MacOS/UAMClass" | grep -A5 LC_BUILD_VERSION
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

# 2. Build del bundle .app
cd ~/uam-class
./build-app.sh

# 3. Correrla
open "UAM Class.app"

# 4. (opcional) Instalarla al sistema
mv "UAM Class.app" /Applications/
```

Al primer arranque te muestra un onboarding con las features principales. Después elegís plataforma → CIF + PIN → ya estás dentro.

## Features

### Filtro de período académico
Global, en el sidebar. Moodle codifica el período en el `shortname`
(`2026-1-LTEC03-…`), así que la app detecta tus cortes y filtra **toda** la
app a la vez: materias, tareas, notas, exámenes, marcadores y el archivador.
- `Actual` (el corte más reciente en tu matrícula) · `Anteriores` · `Todos` · o
  un período puntual
- El período "actual" se deduce de los datos, no del reloj: si UAM abre el corte
  tarde, la fecha de hoy mentiría
- El contador muestra cuántas materias quedan fuera, para que nadie crea que le
  faltan

### Asistencia
Registro **propio y local** por materia: marcás presente / tarde / justificada /
ausente con un click, en una tira de los últimos 14 días (marcar en diferido es
lo normal). Calcula tu porcentaje y lo resalta en rojo bajo 75%.
- No depende del plugin `mod_attendance` de Moodle, que es de terceros y puede
  no estar instalado en UAM. La app detecta si existe vía
  `core_webservice_get_site_info`.

### Directorio de personas
Buscar en UAM Virtual por **CIF o nombre**. Son dos búsquedas distintas de
Moodle y se hacen las dos en paralelo: `core_message_search_users` indexa el
nombre visible pero **no** el username, así que un CIF nunca aparece ahí; para
eso está `core_user_get_users_by_field`, que exige coincidencia exacta.
Los resultados se fusionan por id. La visibilidad depende de la política de
privacidad del sitio.

### Autenticación
- **Dos plataformas**: UAM Virtual (Moodle) y UAM Class (Registro Académico)
- **Multi-instancia Moodle**: Grado, Language Center, Posgrado
- **Token en Keychain**: acceso persistente sin re-ingresar clave (el PIN nunca se guarda)
- **Silent resume**: al abrir la app, si tenés sesión válida, entrás directo
- **Cambio rápido de cuentas** (`Services/AccountStore.swift`): guardá varias
  cuentas tuyas (grado, LC, posgrado, o distintas credenciales) y cambiá entre
  ellas desde la tarjeta de perfil del sidebar sin volver a escribir el PIN.
  - Se guarda el **token de web service** de cada cuenta, no una cookie. La app
    no usa cookies: se autentica contra la API de Moodle. El token dura semanas
    (una cookie de navegador, horas) y es el único que sirve para las llamadas
    de datos, así que es lo correcto para persistir.
  - Cada token vive en el **Keychain** bajo una clave propia por cuenta. En
    UserDefaults solo va el metadato para pintar la lista (nombre, CIF,
    instancia) — nunca el PIN, nunca el token en claro.
  - Si el token de una cuenta venció, el selector te manda a re-ingresar el PIN
    de esa cuenta; el resto siguen intactas.
  - "Cerrar sesión" olvida la cuenta activa (token incluido); "cambiar de
    cuenta" conserva todas.
- **Varias cuentas abiertas EN SIMULTÁNEO**: desde el selector, el botón
  `macwindow.badge.plus` abre una cuenta en su propia ventana. Cada ventana
  construye su propio `AppState` — y con él su propio `MoodleClient`, su token y
  su cache offline por cuenta (`OfflineCache(scope:)`), así que dos cuentas
  conviven sin pisarse. Compartir el estado haría que la segunda ventana
  desconectara a la primera.

### Datos de tus cursos
- **Materias** con card colorida y hero por curso
- **Vista de detalle** por materia con 6 tabs: Contenido, Notas, Asignaciones, Personas, Mis notas, Info
- **Contenido**: secciones colapsables, módulos categorizados (tarea, foro, recurso, quiz, etc.) con ícono y color por tipo
- **Notas** con comentarios del docente expandibles y badges Aprobado/Reprobado
- **Asignaciones** con fecha de entrega (rojo si venció)
- **Personas**: docentes destacados + estudiantes del curso, con `mailto:` directo
- **Foros**: lista de discusiones → posts → responder in-line

### Exámenes y cuestionarios

Se responden **dentro de la app**, sin abrir UAM Virtual en el navegador.

- Sección **Exámenes** con todos los cuestionarios de todas las materias,
  filtrables por disponibles / próximos / cerrados
- Pantalla previa con las reglas reales del examen: tiempo límite, intentos
  permitidos, ventana de apertura, nota máxima y motivos de bloqueo si Moodle
  no te deja entrar
- **Examinador a pantalla completa**: navegador de preguntas con estado,
  marcado "para revisar", cuenta regresiva y barra de progreso
- **Tipos soportados de forma nativa**: opción múltiple (simple y múltiple),
  verdadero/falso, respuesta corta, numérica, desarrollo y emparejar
- **Tipos derivados al visor web integrado**: arrastrar y soltar, anidadas
  (cloze) y seleccionar-en-el-texto. La respuesta de estos depende de
  JavaScript o de dónde se sueltan los elementos, así que responderlos
  nativamente daría un envío incorrecto en silencio. El visor web es un
  WKWebView dentro de la app, no una salida al navegador.
- **Revisión** de intentos ya entregados, con el estado de cada pregunta

Salvaguardas, porque un examen tiene nota real:

- **Autoguardado** a los ~1.8s de cada cambio, con reintento automático cada
  20s si falla
- El estado de guardado está **siempre visible**; si un guardado falla se
  muestra en rojo con reintento a un click, nunca como un toast que se va
- Las respuestas se envían **por cuerpo POST**, no por query string: un ensayo
  largo desborda el límite de URL y se truncaría en silencio
- Cada envío reenvía **todos los campos ocultos** de la pregunta, incluido
  `sequencecheck` — sin él Moodle descarta la respuesta
- **Confirmación explícita** antes de entregar, avisando cuántas preguntas
  quedan sin responder
- Al vencer el tiempo se entrega solo, marcado con `timeup` como espera Moodle
- Botón de **visor web** siempre presente en la barra superior

El parseo del HTML de preguntas es la pieza más frágil (Moodle manda las
preguntas renderizadas, no estructuradas). Tiene una batería de pruebas contra
markup real:

```bash
./Tools/check-quiz-parser.sh
```

### Descargas + Preview
- **Preview inline** sin descargar: PDF (PDFKit), imágenes (streaming), video (AVPlayer), texto plano, HTML
- **Master-detail**: lista de archivos a la izquierda, preview a la derecha
- **Descarga opcional**: guardá en `~/Downloads/UAM Class/{curso}/`
- **Quick Look nativo** para archivos descargados
- **Abrir con app externa** o mostrar en Finder

### Chat / Mensajes
- Sección **Mensajes** completa
- Lista de conversaciones con último mensaje, badge de no leídos, timestamp relativo
- Chat con burbujas propias vs ajenas, avatar, timestamps
- **Nuevo chat**: buscar personas → enviar mensaje inicial
- Usa endpoints Moodle `core_message_*`

### Sesiones de estudio
- **Timer Pomodoro** (⌘T) por materia con presets 15/25/45/60/90 min
- Círculo animado con countdown
- **Auto-tracking**: al entrar a un curso arranca timer silencioso; se registra si estuviste >60s
- **Historial de sesiones** con gráfico por día en Estadísticas

### Estadísticas
- Gráfico de tiempo estudiado por día (Charts nativos)
- Tiempo total, racha actual (días consecutivos), sesiones, favoritos
- Breakdown por materia con barras coloreadas
- Ranges: 7 días / 30 días / todo

### Command Palette (⌘K)
- Búsqueda global instantánea
- Cursos, archivos locales indexados, acciones rápidas
- Preview de texto en archivos PDF
- Ejecuta: Archivar semestre, Iniciar timer, Exportar iCal, Re-indexar, Cambiar plataforma

### Marcadores personales
- **Favoritos** ⭐ de materias (aparecen sticky arriba en Materias)
- **Bookmarks** de módulos individuales (sección Marcadores)
- **Tags custom** por materia
- **Rating** de dificultad de 5 estrellas
- **Notas personales** por materia con templates (Resumen, Preguntas, Fórmulas)
- Exportá tus notas a `.md`

### Notificaciones + Menu Bar
- **Recordatorios locales** 24h y 1h antes de cada entrega
- **Menu bar widget** con popover rico: próximas entregas, botón buscar y abrir
- Badge con contador de entregas próximas en las próximas 24h

### Archivador de semestre
- Un click descarga TODO el semestre a `~/Downloads/UAM Class/{año}-{período}/`:
  ```
  SIS0401 - Ingeniería de Software I/
    Índice.md
    00 - Presentación/*.pdf
    01 - Semana 1/*.pdf
    Notas.csv         (con comentarios del docente)
    Foros/*.md         (discusiones en markdown)
  ```
- Progreso en vivo, cancelable, "Mostrar en Finder" al terminar
- Tu propio archivo permanente, buscable con Spotlight

### AI local
- **Resumen automático** de PDFs con `NaturalLanguage` framework (NLTagger)
- Extrae: primeras oraciones, keywords, fechas mencionadas, URLs
- Sin API externa, sin envío de datos, todo local

### iCal export
- Un click y todas las entregas futuras se abren en Calendar.app como eventos con recordatorios

### Deep linking
- `uamclass://course/{id}` — abrir directo un curso
- `uamclass://palette` — abrir command palette
- `uamclass://timer` — abrir study timer

### Command shortcuts
- ⌘K → Buscar todo
- ⌘T → Sesión de estudio
- ⌘⇧D → Archivar semestre
- ⌘⇧P → Cambiar plataforma

### Diseño — sistema "Códice"

Manuscrito medieval iluminado, en **blanco, negro y grafito**. Sin color, sin
vidrio: papel e tinta. El layout de plataforma educativa se mantiene intacto;
lo que cambia es la piel.

- **Papel** (`Design/Ambience.swift`) — el fondo es una hoja: color cálido
  plano, grano fino de fibra en `multiply`, y un viñeteado que oscurece los
  bordes como la sombra de un libro abierto. Reemplazó al `MeshGradient` de
  colores del sistema anterior.
- **Superficies** (`Design/Glass.swift`) — las cards son hojas planas con filo
  hairline de tinta y sombra mínima; los paneles flotantes (palette, toasts,
  popovers) son vitela con un poco más de sombra. Los nombres de los
  modificadores se conservan (`contentCard`, `glassBar`, `glassPanel`,
  `glassChip`) aunque ya no haya vidrio, para no reescribir cada vista.
- **Tipografía** (`Design/Typography.swift`) — serif (New York, `.serif`) para
  todo lo que se lee y se contempla: títulos, enunciados, cuerpo. La firma es el
  **tracking amplio** en los titulares (letras abiertas, como grabadas) y la
  **cursiva** en subtítulos. Sans solo para el aparato de UI: versalitas y datos
  monoespaciados.
- **Paleta** (`Design/Colors.swift`) — papel cálido casi blanco / tinta casi
  negra / grafitos. El acento no es un color: es la tinta más negra. Los tres
  estados (aprobado/aviso/vencido) sobreviven como tintas muy apagadas —
  musgo, sepia, oxblood— casi monocromas, para no perder la señal sin romper el
  blanco/negro.
- **Ornamentos** (`Views/Components/Ornaments.swift`) — la firma del códice:
  - `Filigrana` — separador con nudo central, entre bloques.
  - `GothicArch` — arco ojival que recorta las portadas de curso, como el
    ventanal de un claustro.
  - `ChapterMark` — encabezado de sección (glifo + filete + versalita + sentido
    en cursiva).
  - `CornerFrame` — esquineras de álbum antiguo sobre las láminas.
  - `DropCap` — capitular encuadrada.
  - `BrandMark` — el sello es ahora una **torre almenada** grabada en tinta
    (antes era el puente Golden Gate).
- **Color determinístico por materia** — ahora una rampa de **grafitos**, no de
  colores; las materias se distinguen por valor, no por matiz. Hash estable
  entre lanzamientos.
- **Esquinas cerradas** (radios chicos) y **sombras suaves de papel**: una hoja
  apoyada sobre otra, no vidrio flotante.
- **Dark mode** — el códice en tinta-negra con letra de tiza.

> Nota: este sistema **reemplazó** al "Golden Gate / Liquid Glass" anterior. El
> target sigue en macOS 26 (funciona y es donde corre), pero ya no depende del
> Liquid Glass — los efectos de sistema que quedaban (`backgroundExtensionEffect`,
> `scrollEdgeEffectStyle`) están guardados por `#available` y degradan solos.

### Configuración (⌘,)
- Tema: auto / claro / oscuro
- Toggles de notificaciones
- Duración Pomodoro por defecto
- Re-indexar archivos locales
- Borrar preferencias locales

## Arquitectura

```
Sources/UAMClass/
├── App/               # UAMClassApp, AppDelegate, AppState, MenuBarController
├── Design/            # Colors (tokens Golden Gate), Typography, Spacing +
│                       # Elevation, Motion, CourseAccent, Glass (Liquid Glass +
│                       # fallbacks), Ambience (MeshGradient + grano), UserPrefs,
│                       # AppConfig
├── Models/            # MoodleModels (con extensions para HTML strip),
│                       # ClassPortalModels, Platform
├── Services/          # MoodleClient, ClassPortalClient, AuthService,
│                       # DownloadService, ArchiveService, LocalStore (UserDefaults),
│                       # LocalFileSearch, NotificationScheduler,
│                       # ICalExporter, PDFSummarizer, Keychain
├── Utils/             # Formatting, HTMLStripping
└── Views/
    ├── UAMClassApp.swift, RootView, SplashView
    ├── PlatformPickerView, LoginView, OnboardingSheet
    ├── MainWindow (NavigationSplitView + Sidebar + TopBar)
    ├── CommandPalette, ArchiverSheet, StudyTimer, SettingsSheet
    ├── Components/    # Card/HoverCard/GlassPanel/EmptyState/BlockHeader,
    │                   # Chips (Pill, CountBadge, KeyCap, IconTile,
    │                   #        GlassSegmented, MetricTile, AccentBar),
    │                   # PrimaryButton/SecondaryButton/GhostButton/GlassIconButton,
    │                   # TextInput + SearchField, Skeleton, Toast,
    │                   # InlinePreview (PDF/Image/Video/Web), TagsEditor, RatingCard
    └── Sections/
        ├── DashboardView (hero + hoy + calendario + stats + cursos)
        ├── MateriasView (grid/lista con favoritos sticky)
        ├── NotasView, AsignacionesView, MensajesView, EstadisticasView, BookmarksView
        ├── PersonalesView, HorarioView, NotasAcademicasView, ArancelesView
        ├── CourseDetailView (hero + tabs)
        └── CourseDetail/
            ├── ModuleInspector (Resource/URL/Forum/Assign inspectors)
            ├── PeopleTab
            └── MyNotesTab (con templates)
```

## Endpoints usados

### Moodle (`webservice/rest/server.php`)
- `mod_quiz_get_quizzes_by_courses`, `_get_quiz_access_information`,
  `_get_attempt_access_information` — metadatos y reglas
- `mod_quiz_get_user_attempts`, `_start_attempt` — intentos
- `mod_quiz_get_attempt_data`, `_get_attempt_summary` — preguntas (HTML renderizado)
- `mod_quiz_save_attempt`, `_process_attempt` — autoguardado y entrega
- `mod_quiz_get_attempt_review`, `_view_quiz`, `_view_attempt` — revisión y registro
- `core_webservice_get_site_info` — perfil
- `core_enrol_get_users_courses` — materias
- `core_enrol_get_enrolled_users` — personas del curso
- `core_course_get_contents` — secciones + módulos
- `mod_assign_get_assignments`, `_get_submission_status` — tareas
- `gradereport_user_get_grade_items` — notas + feedback del docente
- `mod_forum_get_forums_by_courses`, `_get_forum_discussions_paginated`, `_get_discussion_posts`, `_add_discussion_post` — foros
- `core_message_get_conversations`, `_get_conversation_messages`, `_send_messages_to_conversation`, `_send_instant_messages`, `_search_users` — chat

### CLASS Portal (`estudiantes/Ajax/Ajax_WebMethods.aspx`)
- `Rutina_LoginValidezToken` — login
- `Rutina_Obtie_Periodo_Ano_Calificador` — período

## Privacidad

- Todo lo que se guarda en disco vive **local** en tu Mac
- Token Moodle en **Keychain** (`com.kisnner.uamclass`)
- Preferencias/notas/bookmarks/sesiones en **UserDefaults**
- Materiales descargados en **~/Downloads/UAM Class/**
- **Nada** se envía a servidores externos aparte de UAM
- El PIN de UAM **nunca** se persiste en ningún lado

## Estado de features

| Feature                          | Estado |
|----------------------------------|--------|
| Login Moodle multi-instancia     | ✓      |
| Login CLASS Portal               | ✓ (detecta portal cerrado) |
| Dashboard con widgets            | ✓      |
| Materias grid + lista + favs     | ✓      |
| Course detail (6 tabs)           | ✓      |
| Preview inline archivos          | ✓      |
| Descarga + Quick Look            | ✓      |
| Chat completo con Moodle         | ✓      |
| Foros + responder                | ✓      |
| Notas con feedback docente       | ✓      |
| Personas (docentes + estudiantes)| ✓      |
| Sesiones Pomodoro + tracking     | ✓      |
| Estadísticas con Charts          | ✓      |
| Command Palette ⌘K               | ✓      |
| Menu bar popover                 | ✓      |
| Notificaciones de entregas       | ✓      |
| Archivador de semestre           | ✓      |
| Búsqueda de archivos locales     | ✓      |
| AI Summary (NLTagger local)      | ✓      |
| Deep linking uamclass://         | ✓      |
| Onboarding                       | ✓      |
| Dark mode adaptativo             | ✓      |
| Marcadores, tags, rating         | ✓      |
| Notas personales + templates     | ✓      |
| Export ICS a Calendar            | ✓      |
| Exámenes nativos (6 tipos)       | ✓      |
| Exámenes drag&drop / cloze       | ✓ (visor web integrado) |
| Autoguardado + entrega           | ✓      |
| Subida de entregas               | Pendiente (mod_assign_save_submission requiere upload multipart) |
| Horario CLASS Portal             | Pendiente (esperando reapertura de UAM) |
| Aranceles CLASS Portal           | Pendiente (idem) |
