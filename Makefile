APP := build/GrammarFixer.app

# XCTest поставляется с Xcode, а не с CommandLineTools. Полный Xcode не нужен
# для сборки приложения, но нужен для запуска тестов, поэтому если текущий
# тулчейн его не содержит, цели используют тулчейн Xcode через переменную
# окружения. Это не требует sudo и ничего не меняет в системе, в отличие от
# xcode-select -s. Один тулчейн на все цели выбран намеренно: иначе сборка и
# тесты подменяли бы друг другу SDK и каждый раз пересобирали всё заново.
#
# Путь к Xcode не зашит: он может быть переименован, лежать не в /Applications
# или стоять из xcodes. Спрашиваем Spotlight и только потом падаем на путь по
# умолчанию.
ifeq ($(shell xcrun --find xctest 2>/dev/null),)
XCODE_APP := $(shell mdfind "kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode'" 2>/dev/null | head -1)
ifeq ($(XCODE_APP),)
XCODE_APP := $(wildcard /Applications/Xcode.app)
endif
ifneq ($(XCODE_APP),)
export DEVELOPER_DIR := $(XCODE_APP)/Contents/Developer
endif
endif

.PHONY: all run bundle release verify test clean

all: run

## Собрать, упаковать, подписать и запустить.
# open переиспользует уже запущенный экземпляр, поэтому старый сначала
# дожидаемся мёртвым, иначе запустится не новая сборка, а старая.
run: bundle
	@pkill -x GrammarFixer 2>/dev/null || true
	@while pgrep -qx GrammarFixer; do sleep 0.1; done
	@open $(APP)
	@echo "Запущено, иконка в меню-баре"

## Собрать и подписать бандл
bundle:
	@./scripts/bundle.sh

## То же, но сборка в релизной конфигурации
release:
	@CONFIG=release ./scripts/bundle.sh

## Показать, чем подписан бандл и какие у него права
verify:
	@codesign -dvvv $(APP) 2>&1 | grep -E '^(Identifier|Authority|Signature)' || true
	@echo "--- права:"
	@codesign -d --entitlements - --xml $(APP) 2>/dev/null | plutil -p - 2>/dev/null || echo "прав нет"
	@echo "--- LSUIElement:"
	@plutil -extract LSUIElement raw $(APP)/Contents/Info.plist

test:
	@xcrun --find xctest >/dev/null 2>&1 || { \
		echo "Для запуска тестов нужен Xcode: XCTest не входит в CommandLineTools" >&2; \
		exit 1; }
	@swift test

clean:
	@rm -rf build .build
