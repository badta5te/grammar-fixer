import Foundation

/// Захват выделения синтетическим ⌘C.
///
/// Провал определяется по счётчику изменений буфера, а не по задержке. Без
/// этого «ничего не выделено» тихо означало бы исправление вчерашнего
/// содержимого буфера и вставку его в чужое приложение.
///
/// Порядок железный: **до подтверждённого инкремента в буфер не пишется
/// ничего.**
@MainActor
public final class TextCapture {
    public enum Outcome: Equatable, Sendable {
        case captured(String)
        /// Счётчик не сдвинулся: копировать было нечего.
        case nothingSelected
        /// Счётчик сдвинулся, а текста нет. Найдено в Chrome на нетекстовом
        /// выделении: без этой ветки дальше поехал бы nil.
        case unsupportedSelection
    }

    public struct Result: Sendable {
        public let outcome: Outcome
        public let snapshot: ClipboardSnapshot
        public let changeCountBefore: Int
    }

    private let clipboard: Clipboard
    private let keyboard: SyntheticKeyboard
    private let pollInterval: TimeInterval
    private let timeout: TimeInterval
    private let lateCopyWindow: TimeInterval
    private let sleep: @MainActor (TimeInterval) async -> Void

    /// - Parameters:
    ///   - timeout: сколько ждать инкремента. Прототип дал 30 замеров с
    ///     медианой 34 мс и максимумом 146 мс, и стоявшая там секунда читалась
    ///     как «приложение не среагировало». Полсекунды — троекратный запас
    ///     сверх наблюдавшегося максимума. Цена ошибки несимметрична: слишком
    ///     короткий таймаут объявит «ничего не выделено» там, где текст был.
    ///   - lateCopyWindow: сколько ещё присматривать за буфером после отказа.
    ///     Копия, приехавшая с опозданием, иначе молча оставила бы выделение
    ///     пользователя в его буфере вместо того, что там лежало. Окно короче
    ///     самого ожидания намеренно: чем дальше от нашего ⌘C, тем вероятнее,
    ///     что буфер изменил кто-то другой, и тогда защита превращается во вред.
    public init(
        clipboard: Clipboard,
        keyboard: SyntheticKeyboard,
        pollInterval: TimeInterval = 0.01,
        timeout: TimeInterval = 0.5,
        lateCopyWindow: TimeInterval = 0.5,
        sleep: @escaping @MainActor (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }
    ) {
        self.clipboard = clipboard
        self.keyboard = keyboard
        self.pollInterval = pollInterval
        self.timeout = timeout
        self.lateCopyWindow = lateCopyWindow
        self.sleep = sleep
    }

    public func capture() async -> Result {
        let snapshot = clipboard.snapshot()
        let before = clipboard.changeCount
        Log.write("снимок буфера: элементов \(snapshot.items.count), типов \(snapshot.typeCount)")

        keyboard.copy()

        let start = Date()
        for _ in 0 ..< polls(within: timeout) {
            await sleep(pollInterval)
            guard clipboard.changeCount != before else { continue }

            Log.write(String(format: "буфер обновился за %.0f мс", Date().timeIntervalSince(start) * 1000))
            guard let text = clipboard.readText(), !text.isEmpty else {
                return Result(outcome: .unsupportedSelection, snapshot: snapshot, changeCountBefore: before)
            }
            Log.write("захвачено символов: \(text.count)")
            return Result(outcome: .captured(text), snapshot: snapshot, changeCountBefore: before)
        }

        Log.write("счётчик буфера не сдвинулся за \(Int(timeout * 1000)) мс — выделения нет")
        return Result(outcome: .nothingSelected, snapshot: snapshot, changeCountBefore: before)
    }

    /// Присматривает за буфером после отказа и возвращает содержимое, если ⌘C
    /// всё-таки доехал. Сигнал пользователю к этому моменту уже прозвучал:
    /// быстрый отказ и защита буфера — разные сроки, и смешивать их нельзя.
    ///
    /// Чужую копию, попавшую в это окно, защита затрёт. Случай не выдуманный:
    /// в терминале с `copy-on-select` выделение само уезжает в буфер, и стоило
    /// выделить текст сразу после несработавшего хоткея, как копия пропадала.
    /// Поэтому окно и урезано до полусекунды.
    @discardableResult
    public func restoreIfCopyLandsLate(after result: Result) async -> Bool {
        for _ in 0 ..< polls(within: lateCopyWindow) {
            await sleep(pollInterval)
            guard clipboard.changeCount != result.changeCountBefore else { continue }
            Log.write("копия приехала после отказа, буфер возвращается на место")
            return clipboard.restore(result.snapshot)
        }
        return false
    }

    private func polls(within duration: TimeInterval) -> Int {
        max(1, Int((duration / pollInterval).rounded()))
    }
}
