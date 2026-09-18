#!/bin/bash
# Crea un bundle .app real desde el binario de swift build.
# Uso: ./build-app.sh  →  produces ./UAM Class.app
set -e

swift build -c release

APP="UAM Class.app"
BIN=".build/release/UAMClass"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/UAMClass"
chmod +x "$APP/Contents/MacOS/UAMClass"

# Bundle de recursos de SwiftPM (el logotipo de la UAM).
#
# `Bundle.module` lo busca JUNTO AL EJECUTABLE, así que va en MacOS/ y no en
# Resources/. Sin este paso la app compila y arranca, pero el logo no aparece:
# `Bundle.module` no lo encuentra y cae al respaldo tipográfico.
# Va en Resources/ y NO junto al ejecutable: un bundle anidado dentro de MacOS/
# rompe la firma ("bundle format unrecognized") y la app no arranca.
# `Bundle.module` igual lo encuentra, porque busca en `Bundle.main.resourceURL`.
RES_BUNDLE=".build/release/UAMClass_UAMClass.bundle"
if [ -d "$RES_BUNDLE" ]; then
  cp -R "$RES_BUNDLE" "$APP/Contents/Resources/"
else
  echo "⚠︎  No se encontró $RES_BUNDLE — el logotipo no va a cargar."
fi

# Ícono. Sin esto el Dock muestra el genérico gris: no alcanza con que el .icns
# exista en el repo, hay que copiarlo Y declararlo en el Info.plist.
if [ -f "UAMClass.icns" ]; then
  cp "UAMClass.icns" "$APP/Contents/Resources/UAMClass.icns"
else
  echo "⚠︎  UAMClass.icns no existe — la app va a salir con el ícono gris."
  echo "   Generalo con: ./Tools/make-icon.sh <arte.png>"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>UAM Class</string>
    <key>CFBundleDisplayName</key>
    <string>UAM Class</string>
    <key>CFBundleIdentifier</key>
    <string>com.kisnner.uamclass</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>UAMClass</string>
    <key>CFBundleIconFile</key>
    <string>UAMClass</string>
    <key>CFBundleIconName</key>
    <string>UAMClass</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>UAM Class controla la app de Spotify para mostrar y manejar lo que estás escuchando mientras estudiás.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.education</string>
    <key>NSHumanReadableCopyright</key>
    <string>© 2026 Kisnner</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>com.kisnner.uamclass.deeplink</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>uamclass</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

# Firma con una identidad ESTABLE.
#
# Esto es lo que evita que macOS pida la clave del llavero cada dos por tres. El
# ACL de cada ítem del llavero se ata a la identidad de código de la app; con la
# firma ad-hoc que deja `swift build`, esa identidad es el hash del binario y
# cambia en CADA compilación, así que el sistema ve una app distinta y vuelve a
# preguntar. Con un certificado de verdad el requisito pasa a ser
# "identificador + certificado", que sobrevive a las recompilaciones.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
           | grep -m1 -o '"[^"]*"' | tr -d '"')

# Los bundles anidados se firman ANTES que el contenedor: codesign exige que
# todo lo de adentro ya esté sellado cuando sella la app.
if [ -n "$IDENTITY" ] && [ -d "$APP/Contents/Resources/UAMClass_UAMClass.bundle" ]; then
  codesign --force --sign "$IDENTITY" \
      "$APP/Contents/Resources/UAMClass_UAMClass.bundle" >/dev/null 2>&1 || true
fi

if [ -n "$IDENTITY" ] && codesign --force --sign "$IDENTITY" \
       --identifier "com.kisnner.uamclass" "$APP" >/dev/null 2>&1; then
  echo "✓ Firmada con: $IDENTITY"
else
  codesign --force --sign - --identifier "com.kisnner.uamclass" "$APP" >/dev/null 2>&1 || true
  echo "⚠︎  Sin identidad de firma estable — queda ad-hoc."
  echo "   El llavero va a volver a pedir la clave después de cada compilación."
fi

echo ""
echo "✓ Bundle listo: $(pwd)/$APP"
echo "  Movelo a /Applications con: mv \"$APP\" /Applications/"
echo "  O corré directamente: open \"$APP\""
