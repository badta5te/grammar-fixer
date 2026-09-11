#!/bin/bash
# Собирает .app из результата SwiftPM и подписывает его.
#
# Подпись обязана быть стабильной: macOS привязывает выданный доступ
# Accessibility к паре «путь плюс подпись». При ad-hoc подписи хеш кода
# меняется от сборки к сборке, и доступ приходится выдавать заново каждый раз.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-debug}"
APP_NAME="GrammarFixer"
BUNDLE_ID="com.badta5te.GrammarFixer"
DEV_IDENTITY="GrammarFixer Dev"
APP="build/${APP_NAME}.app"

swift build -c "$CONFIG"
BINARY="$(swift build -c "$CONFIG" --show-bin-path)/${APP_NAME}"

rm -rf "$APP"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "$BINARY" "${APP}/Contents/MacOS/${APP_NAME}"
cp Resources/Info.plist "${APP}/Contents/Info.plist"

# Порядок важен: подписывать нужно уже собранный бандл целиком, иначе подпись
# не покроет Info.plist.
if [ -n "${SIGN_IDENTITY:-}" ]; then
    identity="$SIGN_IDENTITY"
# Без -v намеренно: свежий самоподписанный сертификат числится недоверенным,
# и с -v он бы не нашёлся. Для локальной подписи доверие не требуется,
# codesign с ним работает.
elif security find-identity -p codesigning 2>/dev/null | grep -qF "$DEV_IDENTITY"; then
    identity="$DEV_IDENTITY"
else
    identity="-"
    cat >&2 <<WARNING

  Сертификат «${DEV_IDENTITY}» не найден, подпись будет ad-hoc.
  Доступ Accessibility придётся выдавать заново после каждой сборки.
  Как создать сертификат один раз — в README, раздел «Подпись».

WARNING
fi

# --force затирает подпись и отладочные права, которые SwiftPM накладывает на
# исполняемый файл при сборке.
codesign --force --sign "$identity" --identifier "$BUNDLE_ID" --timestamp=none "$APP"

echo "Собрано: ${APP}"
echo "Подписано: ${identity}"
