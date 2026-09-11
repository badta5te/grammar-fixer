import AppKit
import SwiftUI

/// The settings window.
///
/// Every field applies as it is changed. There is no Save button on purpose:
/// the menu's switches have always worked that way, a half-applied window would
/// be a second kind of state to reason about, and the button that checks the
/// key would then have to ask which of the two it is checking.
@MainActor
public final class SettingsPanel: NSObject, NSWindowDelegate {
    private let settings: Settings
    private let store: ProviderStore
    private let usage: UsageStore
    private let catalog: PriceCatalog
    private let shortcut: ShortcutBinder
    private var panel: FloatingPanel?

    public init(
        settings: Settings,
        store: ProviderStore,
        usage: UsageStore,
        catalog: PriceCatalog,
        shortcut: ShortcutBinder
    ) {
        self.settings = settings
        self.store = store
        self.usage = usage
        self.catalog = catalog
        self.shortcut = shortcut
        super.init()
    }

    public func show() {
        // An agent app is never the active one, and a window with text fields
        // in it is unusable until it is. Unlike the result panel, this window
        // is meant to be sat in front of.
        NSApp.activate(ignoringOtherApps: true)

        if let panel {
            panel.present()
            return
        }

        let state = SettingsFormState(
            settings: settings,
            store: store,
            usage: usage,
            catalog: catalog,
            shortcut: shortcut
        )
        let panel = FloatingPanel(styleMask: [.titled, .closable]) {
            SettingsView(state: state)
        }
        // Not .popUpMenu: this is a window somebody leaves open while working
        // in another app, not something that floats over everything.
        panel.level = .normal
        panel.title = "\(AppInfo.name) Settings"
        panel.delegate = self
        panel.present()
        self.panel = panel
    }

    /// The window can go while the shortcut field is still listening, and
    /// closing a window does not make its first responder resign — verified
    /// against a panel built the same way as this one. The field's own way of
    /// noticing therefore never fires, the hot key stays given back with nobody
    /// left to take it again, and the app's only way in is dead until the next
    /// launch. Asking for it here costs nothing when it was never let go:
    /// taking a key that is still held does nothing at all.
    public func windowWillClose(_ notification: Notification) {
        panel = nil
        shortcut.resume()
    }
}

/// What the window is showing. Values are read once when it opens and written
/// through as they change, so the next round uses them and nothing is left
/// waiting in a form.
@MainActor
@Observable
public final class SettingsFormState {
    public enum KeyState: Equatable {
        case untested
        case checking
        case checked(KeyCheck.Outcome)
    }

    /// The provider's own list of models. Never anything this app made up.
    public enum ModelListState: Equatable {
        case notLoaded
        case loading
        case loaded([String])
        case failed(String)
    }

    var presetId: String
    var model: String
    var address: String
    var apiKey: String
    var requestsUsage: Bool
    var reasoning: ProviderConfiguration.Reasoning
    var theme: Theme
    var readsSelectionDirectly: Bool
    var restoreClipboard: Bool
    var pasteByTyping: Bool
    var promptTemplate: String
    var monthlyLimit: String
    var startsAtLogin: Bool
    var shortcut: Shortcut
    /// A combination that could not be had. Shown beside the field, because
    /// the alternative is a key that quietly does nothing later.
    var shortcutRefusal: Notice?
    var priceRows: [PriceRow] = []

    var keyState: KeyState = .untested
    var modelList: ModelListState = .notLoaded
    /// The system refusing to add or remove the login item. Shown beside the
    /// switch, because a switch that snaps back on its own is the one outcome
    /// that leaves somebody flipping it forever.
    var loginItemFailure: Notice?

    /// A Keychain that refused. Shown in place of the key field's own hint,
    /// because a key that fails to save without a word is the one outcome that
    /// leaves a person retyping it forever.
    var keyFailure: Notice?

    let overrides: EnvironmentOverrides

    private let settings: Settings
    private let store: ProviderStore
    private let usage: UsageStore
    let catalog: PriceCatalog
    private let loginItem: LoginItem
    private let binder: ShortcutBinder

    init(
        settings: Settings,
        store: ProviderStore,
        usage: UsageStore,
        catalog: PriceCatalog,
        shortcut binder: ShortcutBinder,
        loginItem: LoginItem = LoginItem()
    ) {
        self.settings = settings
        self.store = store
        self.usage = usage
        self.catalog = catalog
        self.loginItem = loginItem
        self.binder = binder
        shortcut = binder.shortcut
        presetId = store.preset.id
        model = store.model
        address = settings.address
        requestsUsage = settings.requestsUsage
        reasoning = settings.reasoning
        theme = settings.theme
        readsSelectionDirectly = settings.readsSelectionDirectly
        restoreClipboard = settings.restoreClipboardAfterPaste
        pasteByTyping = settings.pasteMethod == .typing
        promptTemplate = settings.promptTemplate
        overrides = store.overrides
        apiKey = (try? store.key(for: store.preset)) ?? ""
        monthlyLimit = String(format: "%.2f", settings.monthlyLimit)
        // Asked of the system rather than stored beside it: a login item can
        // be removed in System Settings, and a remembered switch would then
        // show the opposite of what happens at the next login. The window
        // makes a new form every time it opens, so it asks again then.
        startsAtLogin = loginItem.isOn
        reloadPrices()
    }

    // MARK: - Spending

    /// One row of the price table as it is being edited. The two amounts are
    /// text rather than numbers because a half-typed figure is not a number
    /// yet, and a field that fought back mid-keystroke would be unusable.
    struct PriceRow: Identifiable, Equatable {
        var id: String { PriceTable.key(provider: provider, model: model) }
        var provider: String
        var model: String
        var input: String
        var output: String
        /// There is an entry of this person's own behind this row.
        var isEdited: Bool
        /// What the catalogue says, if anything. Kept so the row can be put
        /// back to it: a field emptied by hand would otherwise leave the row
        /// blank with no way back short of reopening the window.
        var fetched: Price?
        /// The model the next round will use.
        var isCurrent: Bool

        var canBePutBack: Bool { isEdited || fetched != nil }
    }

    var summary: SpendSummary { usage.summary(prices: catalog.table) }

    var budget: Budget { settings.budget }

    /// The last few rounds, newest first. Enough to see that the counter is
    /// working and which rounds it had to guess at, and not so many that the
    /// window becomes a ledger.
    var recentRounds: [UsageRecord] {
        usage.records.suffix(6).reversed()
    }

    func cost(of record: UsageRecord) -> Double? {
        catalog.table.cost(of: record)
    }

    /// Where the prices came from, and when. "Never" is a real state: a first
    /// launch without a network has no prices at all, and the window has to
    /// say so rather than leave every row mysteriously empty.
    var priceSourceNote: String {
        guard let fetchedAt = catalog.fetchedAt else {
            return "\(ModelsDev.name): not fetched yet"
        }
        return "\(ModelsDev.name), \(Self.fetched.localizedString(for: fetchedAt, relativeTo: Date()))"
    }

    private static let fetched: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.unitsStyle = .full
        return formatter
    }()

    /// Asks the catalogue again, from the button in the window. The prices in
    /// hand stay if it fails.
    func loadPrices() async {
        await catalog.refresh()
        reloadPrices()
    }

    func limitChanged() {
        // An emptied or half-typed field reads as no limit rather than as a
        // refusal: the limit is soft, and a window that fought back while a
        // figure was being typed would be worse than a moment without one.
        settings.monthlyLimit = Money.parse(monthlyLimit) ?? 0
    }

    /// The rows worth showing: the model the next round will use, and every
    /// model this month has already been billed for. The shipped table holds
    /// more, but a window listing prices for models somebody has never touched
    /// is a wall of figures to scroll past.
    func reloadPrices() {
        var keys: [(provider: String, model: String)] = []
        if !model.isEmpty { keys.append((preset.id, model)) }
        for record in usage.records.reversed() where !record.model.isEmpty {
            keys.append((record.provider, record.model))
        }

        var seen = Set<String>()
        let prices = catalog.table
        let fetched = PriceTable(entries: catalog.entries)
        let overrides = settings.priceOverrides
        priceRows = keys.compactMap { key in
            let id = PriceTable.key(provider: key.provider, model: key.model)
            guard seen.insert(id).inserted else { return nil }
            let price = prices.price(provider: key.provider, model: key.model)
            return PriceRow(
                provider: key.provider,
                model: key.model,
                input: price.map { trim($0.input) } ?? "",
                output: price.map { trim($0.output) } ?? "",
                isEdited: overrides[id] != nil,
                fetched: fetched.price(provider: key.provider, model: key.model),
                isCurrent: key.provider == preset.id && key.model == model
            )
        }
    }

    func priceChanged(_ row: PriceRow) {
        guard let price = Price.parse(input: row.input, output: row.output) else {
            // Half a figure typed is not a price yet. Storing nothing leaves
            // the round unpriced, which is what it is until both fields make
            // sense.
            settings.removePrice(provider: row.provider, model: row.model)
            markEdited(row.id, false)
            return
        }
        settings.setPrice(price, provider: row.provider, model: row.model)
        markEdited(row.id, true)
    }

    /// Putting a row back is the same act as forgetting it was ever edited,
    /// so the shipped price comes back with it.
    func forgetPrice(_ row: PriceRow) {
        settings.removePrice(provider: row.provider, model: row.model)
        reloadPrices()
    }

    private func markEdited(_ id: String, _ isEdited: Bool) {
        guard let index = priceRows.firstIndex(where: { $0.id == id }) else { return }
        priceRows[index].isEdited = isEdited
    }

    /// Prices run from eight cents to fifteen dollars a million tokens, so a
    /// fixed number of decimals would either round the cheap ones to nothing
    /// or hang zeros off the dear ones.
    private func trim(_ amount: Double) -> String {
        let text = String(format: "%.4f", amount)
        guard text.contains(".") else { return text }
        var trimmed = text
        while trimmed.hasSuffix("0") { trimmed.removeLast() }
        if trimmed.hasSuffix(".") { trimmed.removeLast() }
        return trimmed
    }

    var preset: ProviderPreset { ProviderPreset.named(presetId) ?? .custom }

    /// A template that has lost its placeholder sends the model a prompt with
    /// no text in it. Said here while it is being typed, because the round
    /// itself quietly falls back to the original and somebody would otherwise
    /// never learn why their wording stopped mattering.
    var promptHasNoPlaceholder: Bool {
        !promptTemplate.contains(Prompt.placeholder)
    }

    var promptIsTheDefault: Bool {
        promptTemplate.trimmed == Prompt.default.template.trimmed
    }

    // MARK: - Writing through

    /// The system has the last word here. A refusal puts the switch back where
    /// it was instead of leaving it showing something that will not happen.
    ///
    /// Written through by hand rather than through the section's usual
    /// `onChange`: putting the switch back is itself a change, and the echo of
    /// it would come straight back in here and wipe the refusal off the screen.
    func setStartsAtLogin(_ on: Bool) {
        loginItemFailure = loginItem.set(on)
        startsAtLogin = loginItem.isOn
    }

    var loginItemWaitsForApproval: Bool { loginItem.waitsForApproval }

    /// A recorded combination. The binder has the last word: it checks what
    /// the system owns, asks Carbon, and stores nothing until both agree.
    func recordShortcut(_ recorded: Shortcut) {
        if let refusal = binder.apply(recorded) {
            shortcutRefusal = refusal.notice(for: recorded)
        } else {
            shortcutRefusal = nil
        }
        shortcut = binder.shortcut
    }

    func resetShortcut() {
        recordShortcut(.default)
    }

    var shortcutIsTheDefault: Bool { shortcut == .default }

    /// While the field listens, the hot key is given back, or the combination
    /// somebody is trying to replace would start a round instead of being
    /// recorded.
    func shortcutRecording(_ isRecording: Bool) {
        if isRecording {
            binder.suspend()
        } else {
            binder.resume()
        }
    }

    func presetChanged() {
        store.preset = preset
        // Both fields follow the choice. A key or a model name carried over
        // from another provider is refused, and the refusal names the key even
        // when it was the model that was wrong.
        apiKey = (try? store.key(for: preset)) ?? ""
        model = store.model
        // The list belongs to the provider it was loaded from.
        modelList = .notLoaded
        keyState = .untested
        keyFailure = nil
        reloadPrices()
        Log.write("provider: \(preset.id)")
    }

    func modelChanged() {
        store.model = model
        keyState = .untested
        // The price table shows the model the next round will use, so it
        // follows the field.
        reloadPrices()
    }

    func addressChanged() {
        settings.address = address
        // The list came from the server at the old address. Offering it for a
        // different server would hand somebody a model name that server has
        // never heard of.
        modelList = .notLoaded
    }

    func keyChanged() {
        keyState = .untested
        // A different key can mean a different account with a different list.
        modelList = .notLoaded
        do {
            try store.setKey(apiKey, for: preset)
            keyFailure = nil
        } catch let error as any UserFacingError {
            keyFailure = Notice(title: error.title, message: error.message)
            Log.write("key not saved: \(error.title)")
        } catch {
            keyFailure = Notice(title: "The key could not be saved", message: "\(error)")
        }
    }

    func requestsUsageChanged() { settings.requestsUsage = requestsUsage }

    func reasoningChanged() { settings.reasoning = reasoning }

    func themeChanged() {
        settings.theme = theme
        // Applied to the application, so the windows already on screen change
        // with it instead of waiting to be reopened.
        theme.apply()
        Log.write("theme: \(theme.rawValue)")
    }

    func readsSelectionDirectlyChanged() {
        settings.readsSelectionDirectly = readsSelectionDirectly
        Log.write("read the selection through the system: \(readsSelectionDirectly)")
    }

    func restoreClipboardChanged() { settings.restoreClipboardAfterPaste = restoreClipboard }

    func pasteByTypingChanged() { settings.pasteMethod = pasteByTyping ? .typing : .clipboard }

    func promptChanged() { settings.promptTemplate = promptTemplate }

    func resetPrompt() {
        promptTemplate = Prompt.default.template
        settings.promptTemplate = promptTemplate
    }

    func loadModels() async {
        modelList = .loading
        do {
            let models = try await store.models()
            modelList = .loaded(models)
            Log.write("model list received: \(models.count)")
        } catch let error as any UserFacingError {
            modelList = .failed(error.message)
            Log.write("model list not received: \(error.title)")
        } catch {
            modelList = .failed("\(error)")
        }
    }

    func checkKey() async {
        keyState = .checking
        do {
            // Deliberately not requiring a model: the key is pasted first, and
            // the list of models cannot be fetched before there is a key.
            let outcome = await KeyCheck.run(
                configuration: try store.configuration(requiringModel: false)
            )
            // A check that went and fetched the list has already done the work
            // the button beside the model field would do.
            if case .accepted(let models) = outcome { modelList = .loaded(models) }
            keyState = .checked(outcome)
        } catch let error as any UserFacingError {
            // Being half-configured is the commonest reason the check cannot
            // run, and it names itself: no model, no key, no address.
            keyState = .checked(.refused(title: error.title, message: error.message))
        } catch {
            keyState = .checked(.refused(title: "The key could not be checked", message: "\(error)"))
        }
    }
}
