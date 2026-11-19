#!/usr/bin/env bash
# Compila Aura en Release, la firma, la notariza (si hay credenciales) y arma un DMG.
#
# Uso:
#   scripts/build_release.sh
#
# Variables opcionales:
#   SIGN_IDENTITY   "Developer ID Application: Nombre (TEAMID)". Sin esto se firma ad-hoc ("-").
#   NOTARY_PROFILE  Perfil de `xcrun notarytool store-credentials`. Sin esto no se notariza.
#   VERSION         Versión para el nombre del DMG (por defecto la de project.yml).
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
BUILD="$ROOT/.build/release"
DIST="$ROOT/dist"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
VERSION="${VERSION:-$(grep -m1 'MARKETING_VERSION' project.yml | sed -E 's/.*"(.*)".*/\1/')}"
APP="$BUILD/Build/Products/Release/Aura.app"
DMG="$DIST/Aura-$VERSION.dmg"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

step() { printf '\n\033[1;34m▸ %s\033[0m\n' "$1"; }

step "Generando el proyecto"
command -v xcodegen >/dev/null || { echo "Falta XcodeGen: brew install xcodegen"; exit 1; }
xcodegen generate --quiet

step "Compilando Release"
xcodebuild -project Aura.xcodeproj -scheme Aura -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$BUILD" \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" CODE_SIGN_STYLE=Manual OTHER_CODE_SIGN_FLAGS="--timestamp" \
  build | grep -E "error:|warning:|BUILD" || true
[ -d "$APP" ] || { echo "No se generó $APP"; exit 1; }

step "Firmando ($SIGN_IDENTITY)"
if [ "$SIGN_IDENTITY" = "-" ]; then
  codesign --force --deep --sign - --entitlements Aura/Resources/Aura.entitlements "$APP"
  echo "Firma ad-hoc: en otra Mac hay que abrirla con clic derecho → Abrir la primera vez."
else
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
    --entitlements Aura/Resources/Aura.entitlements "$APP"
fi
codesign --verify --strict --verbose=2 "$APP"

step "Armando el DMG"
rm -rf "$DIST/dmg" && mkdir -p "$DIST/dmg/.background"
cp -R "$APP" "$DIST/dmg/"
ln -s /Applications "$DIST/dmg/Applications"
# Fondo oscuro con flecha, dibujado con las herramientas del sistema (sin dependencias).
BG="$DIST/dmg/.background/background.png"
python3 - "$BG" <<'PY' 2>/dev/null || cp "Aura/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512.png" "$BG"
import sys, zlib, struct
w, h = 600, 380
rows = []
for y in range(h):
    row = bytearray([0])
    for x in range(w):
        t = y / h
        r, g, b = int(14 - 7 * t), int(20 - 9 * t), int(36 - 16 * t)
        # flecha central
        if 270 < x < 330 and 182 < y < 198 or (330 <= x < 352 and abs(y - 190) < (352 - x)):
            r, g, b = 47, 123, 255
        row += bytes((r, g, b))
    rows.append(bytes(row))
raw = b"".join(rows)
def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
open(sys.argv[1], "wb").write(png)
PY

rm -f "$DMG" "$DIST/tmp.dmg"
hdiutil create -volname "Aura" -srcfolder "$DIST/dmg" -ov -format UDRW "$DIST/tmp.dmg" >/dev/null
MOUNT="$(hdiutil attach -readwrite -noverify -noautoopen "$DIST/tmp.dmg" | grep -E '/Volumes/' | sed -E 's/.*(\/Volumes\/.*)/\1/')"
osascript <<OSA || echo "No se pudo acomodar la ventana del DMG (sigue siendo válido)."
tell application "Finder"
  tell disk "Aura"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 800, 500}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 112
    set background picture of viewOptions to file ".background:background.png"
    set position of item "Aura.app" of container window to {150, 190}
    set position of item "Applications" of container window to {450, 190}
    close
  end tell
end tell
OSA
sync
hdiutil detach "$MOUNT" >/dev/null
hdiutil convert "$DIST/tmp.dmg" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -f "$DIST/tmp.dmg"
rm -rf "$DIST/dmg"
if [ "$SIGN_IDENTITY" != "-" ]; then codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG"; fi

if [ -n "${NOTARY_PROFILE:-}" ] && [ "$SIGN_IDENTITY" != "-" ]; then
  step "Notarizando"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
else
  echo "Sin NOTARY_PROFILE o sin Developer ID: se omite la notarización."
fi

step "Listo"
echo "$DMG"
