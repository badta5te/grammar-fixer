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
    private var panel: FloatingPanel?

    public init(settings: Settings, store: ProviderStore) {
        self.settings = settings
        self.store = store
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

        let state = SettingsFormState(settings: settings, store: store)
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

    public func windowWillClose(_ notification: Notification) {
        panel = nil
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
    var restoreClipboard: Bool
    var pasteByTyping: Bool
    var promptTemplate: String

    var keyState: KeyState = .untested
    var modelList: ModelListState = .notLoaded
    /// A Keychain that refused. Shown in place of the key field's own hint,
    /// because a key that fails to save without a word is the one outcome that
    /// leaves a person retyping it forever.
    var keyFailure: Notice?

    let overrides: EnvironmentOverrides

    private let settings: Settings
    private let store: ProviderStore

    init(settings: Settings, store: ProviderStore) {
        self.settings = settings
        self.store = store
        presetId = store.preset.id
        model = store.model
        address = settings.address
        requestsUsage = settings.requestsUsage
        reasoning = settings.reasoning
        theme = settings.theme
        restoreClipboard = settings.restoreClipboardAfterPaste
        pasteByTyping = settings.pasteMethod == .typing
        promptTemplate = settings.promptTemplate
        overrides = store.overrides
        apiKey = (try? store.key(for: store.preset)) ?? ""
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
        Log.write("провайдер: \(preset.id)")
    }

    func modelChanged() {
        store.model = model
        keyState = .untested
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
            Log.write("ключ не сохранён: \(error.title)")
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
        Log.write("тема: \(theme.rawValue)")
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
            Log.write("список моделей получен: \(models.count)")
        } catch let error as any UserFacingError {
            modelList = .failed(error.message)
            Log.write("список моделей не получен: \(error.title)")
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
