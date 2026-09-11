import Foundation

/// The round trip's settings. Read afresh on every access so that a switch in
/// the menu takes effect at once and without a restart.
///
/// The store is UserDefaults, so the same switches work from a terminal:
///
///     defaults write com.badta5te.GrammarFixer RestoreClipboardAfterPaste -bool false
@MainActor
public final class Settings {
    public static let restoreClipboardKey = "RestoreClipboardAfterPaste"
    public static let pasteMethodKey = "PasteMethod"
    public static let writesLogKey = "WriteLog"
    public static let themeKey = "Theme"
    public static let providerKey = "Provider"
    public static let modelKey = "Model"
    public static let addressKey = "BaseURL"
    public static let requestUsageKey = "RequestUsage"
    public static let reasoningKey = "Reasoning"
    public static let promptKey = "PromptTemplate"
    public static let limitKey = "MonthlyLimit"
    public static let pricesKey = "Prices"
    public static let shortcutKeyCodeKey = "ShortcutKeyCode"
    public static let shortcutModifiersKey = "ShortcutModifiers"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Self.restoreClipboardKey: true,
            Self.pasteMethodKey: PasteMethod.clipboard.rawValue,
            Self.writesLogKey: true,
            Self.themeKey: Theme.system.rawValue,
            // Cheap, and cheap is the whole reason this app exists instead of
            // a subscription.
            Self.providerKey: ProviderPreset.deepseek.id,
            Self.requestUsageKey: true,
            Self.reasoningKey: ProviderConfiguration.Reasoning.off.rawValue,
            Self.limitKey: Budget.default,
            Self.shortcutKeyCodeKey: Int(Shortcut.default.keyCode),
            Self.shortcutModifiersKey: Shortcut.default.modifiers.rawValue,
        ])

        // Before there was a window, one model was kept for the app as a whole.
        // Moved rather than read as a fallback, so that nothing is left behind
        // to be found again later under a name that no longer means anything.
        if let single = defaults.string(forKey: Self.modelKey) {
            let provider = defaults.string(forKey: Self.providerKey) ?? ProviderPreset.deepseek.id
            if defaults.string(forKey: Self.modelKey(for: provider)) == nil {
                defaults.set(single, forKey: Self.modelKey(for: provider))
            }
            defaults.removeObject(forKey: Self.modelKey)
        }
    }

    /// Restoring is never complete: promised and lazy clipboard types cannot
    /// be deep-copied because they have no data yet. That is why the switch
    /// exists, as an honest way out rather than a quirk.
    public var restoreClipboardAfterPaste: Bool {
        get { defaults.bool(forKey: Self.restoreClipboardKey) }
        set { defaults.set(newValue, forKey: Self.restoreClipboardKey) }
    }

    public var pasteMethod: PasteMethod {
        get { PasteMethod(rawValue: defaults.string(forKey: Self.pasteMethodKey) ?? "") ?? .clipboard }
        set { defaults.set(newValue.rawValue, forKey: Self.pasteMethodKey) }
    }

    public var writesLog: Bool {
        get { defaults.bool(forKey: Self.writesLogKey) }
        set { defaults.set(newValue, forKey: Self.writesLogKey) }
    }

    public var providerId: String {
        get { defaults.string(forKey: Self.providerKey) ?? ProviderPreset.deepseek.id }
        set { defaults.set(newValue, forKey: Self.providerKey) }
    }

    /// The model is kept per provider, the same way the key is.
    ///
    /// A model name belongs to the provider it was typed for: sending
    /// `claude-haiku` to DeepSeek is refused, and the refusal blames the key,
    /// which sends somebody to fix the wrong thing entirely. Trying another
    /// provider for a week and coming back must cost neither the key nor the
    /// name of the model that went with it.
    ///
    /// Left blank until somebody types one. A plausible but outdated name looks
    /// filled in, and the provider's refusal then reads as a broken app rather
    /// than as a name to change.
    public func model(for providerId: String) -> String {
        defaults.string(forKey: Self.modelKey(for: providerId))?.trimmed ?? ""
    }

    public func setModel(_ value: String, for providerId: String) {
        defaults.set(value.trimmed, forKey: Self.modelKey(for: providerId))
    }

    public static func modelKey(for providerId: String) -> String {
        "\(modelKey).\(providerId)"
    }

    /// Read only for the preset that has no address of its own.
    public var address: String {
        get { defaults.string(forKey: Self.addressKey)?.trimmed ?? "" }
        set { defaults.set(newValue.trimmed, forKey: Self.addressKey) }
    }

    public var requestsUsage: Bool {
        get { defaults.bool(forKey: Self.requestUsageKey) }
        set { defaults.set(newValue, forKey: Self.requestUsageKey) }
    }

    public var reasoning: ProviderConfiguration.Reasoning {
        get {
            ProviderConfiguration.Reasoning(rawValue: defaults.string(forKey: Self.reasoningKey) ?? "")
                ?? .off
        }
        set { defaults.set(newValue.rawValue, forKey: Self.reasoningKey) }
    }

    public var theme: Theme {
        get { Theme(rawValue: defaults.string(forKey: Self.themeKey) ?? "") ?? .system }
        set { defaults.set(newValue.rawValue, forKey: Self.themeKey) }
    }

    /// The prompt as the person has it.
    ///
    /// Stored only once it differs from the default, so that a better default
    /// in a later version reaches everybody who never edited theirs. Returning
    /// to the default is therefore the same act as forgetting the setting.
    public var promptTemplate: String {
        get { defaults.string(forKey: Self.promptKey) ?? Prompt.default.template }
        set {
            if newValue.trimmed == Prompt.default.template.trimmed {
                defaults.removeObject(forKey: Self.promptKey)
            } else {
                defaults.set(newValue, forKey: Self.promptKey)
            }
        }
    }

    public var promptIsTheDefault: Bool {
        defaults.string(forKey: Self.promptKey) == nil
    }

    /// Dollars a month before the app starts saying so. Soft: the request goes
    /// out whatever the counter reads. Zero means no limit at all.
    public var monthlyLimit: Double {
        get { defaults.double(forKey: Self.limitKey) }
        set { defaults.set(max(0, newValue), forKey: Self.limitKey) }
    }

    public var budget: Budget { Budget(limit: monthlyLimit) }

    /// The combination that starts a round.
    ///
    /// Stored as the key code and the modifiers rather than as a character:
    /// the shortcut is a physical key, and a character would mean a different
    /// key on a different layout. A combination with no real modifier in it
    /// would fire in the middle of a word, so one written by hand from a
    /// terminal is refused the same way the editor refuses it.
    public var shortcut: Shortcut {
        get {
            let keyCode = defaults.integer(forKey: Self.shortcutKeyCodeKey)
            let modifiers = Shortcut.Modifiers(
                rawValue: defaults.integer(forKey: Self.shortcutModifiersKey)
            )
            let stored = Shortcut(keyCode: UInt32(max(0, keyCode)), modifiers: modifiers)
            guard ShortcutCheck.run(stored, takenBy: []) == nil else { return .default }
            return stored
        }
        set {
            defaults.set(Int(newValue.keyCode), forKey: Self.shortcutKeyCodeKey)
            defaults.set(newValue.modifiers.rawValue, forKey: Self.shortcutModifiersKey)
        }
    }

    /// The prices somebody typed in themselves, and only those.
    ///
    /// The rest come from the catalogue, which is fetched rather than shipped:
    /// a price table written into the source is wrong the moment a provider
    /// changes a figure. A row typed here wins over the catalogue, for anybody
    /// running a model on their own machine or paying something other than the
    /// list price.
    public var priceOverrides: [String: Price] {
        get {
            guard let data = defaults.data(forKey: Self.pricesKey),
                  let table = try? JSONDecoder().decode([String: Price].self, from: data)
            else { return [:] }
            return table
        }
        set {
            guard !newValue.isEmpty else {
                // Nothing of their own left: the shipped table stands on its
                // own again, and an empty dictionary would only be a key
                // pretending to hold something.
                defaults.removeObject(forKey: Self.pricesKey)
                return
            }
            guard let data = try? JSONEncoder().encode(newValue) else {
                // Two doubles per row should never fail to encode. If they
                // ever do, the old table stays where it is rather than being
                // wiped, and the log says a price was typed that never landed.
                Log.write("a price was edited but could not be stored")
                return
            }
            defaults.set(data, forKey: Self.pricesKey)
        }
    }

    public func setPrice(_ price: Price, provider: String, model: String) {
        var overrides = priceOverrides
        overrides[PriceTable.key(provider: provider, model: model)] = price
        priceOverrides = overrides
    }

    public func removePrice(provider: String, model: String) {
        var overrides = priceOverrides
        overrides.removeValue(forKey: PriceTable.key(provider: provider, model: model))
        priceOverrides = overrides
    }
}
