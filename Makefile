APP := build/GrammarFixer.app

# XCTest поставляется с Xcode, а не с CommandLineTools. Полный Xcode не нужен
# для сборки приложения, но нужен для запуска тестов, поэтому если он есть, все
# цели используют его тулчейн через переменную окружения. Это не требует sudo и
# ничего не меняет в системе, в отличие от xcode-select -s. Один тулчейн на все
# цели выбран намеренно: иначе сборка и тесты подменяли бы друг другу SDK и
# каждый раз пересобирали всё заново.
ifneq ($(wildcard /Applications/Xcode.app/Contents/Developer),)
export DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer
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
ifndef DEVELOPER_DIR
	@echo "Для запуска тестов нужен Xcode: XCTest не входит в CommandLineTools" >&2
	@exit 1
endif
	@swift test

clean:
	@rm -rf build .build
