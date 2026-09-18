# UAM Class

app nativa de macOS para el portal virtual de la UAM. moodle con superpoderes:
todo lo que hace moodle web, más un montón de cosas que moodle no tiene.
swiftui, sin dependencias externas, empaquetada como `.app`.

> capturas pendientes de subir

## qué la hace distinta de abrir moodle en el navegador

- **exámenes nativos dentro de la app** — opción múltiple, verdadero/falso,
  respuesta corta, numérica, desarrollo y emparejar se responden sin salir a
  moodle. autoguardado cada ~1.8s con reintento si falla, envío por POST
  (no por query string, para no truncar ensayos largos), y reenvío de todos
  los campos ocultos que moodle exige o descarta la respuesta.
- **varias cuentas abiertas a la vez, cada una en su propia ventana** —
  grado, language center, posgrado, o distintas credenciales. cada ventana
  tiene su propio token, su propio cache y no se pisan entre sí.
- **archivador de semestre** — un click descarga todo el semestre organizado
  por materia y semana, con notas y foros exportados a markdown.
- **auditor de api interno** — lee qué funciones del web service de moodle
  puede llamar tu token y compara contra lo que la app ya usa, para
  encontrar features nuevas que el sitio ya soporta pero nadie construyó.
- **todo local** — token en keychain, el PIN nunca se guarda, nada sale a
  servidores que no sean los de la UAM.

## instalación

```bash
git clone https://github.com/kisnner26/uam-class.git
cd uam-class
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
./build-app.sh
open "UAM Class.app"
```

requiere macOS 26+ y Xcode 26+.

## documentación completa

catálogo de features, arquitectura, endpoints usados y el sistema de diseño
"Códice" están en [`docs/DETALLES.md`](docs/DETALLES.md).

## privacidad

todo lo que se guarda en disco vive local en tu mac. token en keychain, nada
se envía a servidores externos aparte de la UAM, y el PIN nunca se persiste.
