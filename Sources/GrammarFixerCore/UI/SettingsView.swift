import SwiftUI

/// The settings window's contents.
///
/// Grouped rather than free-form: the provider section is the one somebody
/// opens the window for, and it comes first. Everything below it is a switch
/// they will touch once.
struct SettingsView: View {
    @Bindable var state: SettingsFormState

    var body: some View {
        Form {
            shortcutSection
            providerSection
            spendingSection
            appearanceSection
            pasteSection
            startupSection
            promptSection
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 620)
    }

    // MARK: - Shortcut

    private var shortcutSection: some View {
        Section("Shortcut") {
            LabeledContent("Fix the selection") {
                ShortcutField(
                    shortcut: state.shortcut,
                    onRecording: { state.shortcutRecording($0) },
                    onRecorded: { state.recordShortcut($0) }
                )
                .frame(width: 160, height: 24)
            }

            if let refusal = state.shortcutRefusal {
                Label("\(refusal.title). \(refusal.message)", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Click and press the combination you want. It takes effect at once. "
                    + "A combination macOS keeps for itself is refused, but one held by another "
                    + "app can only be found out by pressing it: Carbon accepts it and stays quiet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Back to \(Shortcut.default.display)") { state.resetShortcut() }
                    .disabled(state.shortcutIsTheDefault)
            }
        }
    }

    // MARK: - Provider

    private var providerSection: some View {
        Section("Provider") {
            Picker("Provider", selection: $state.presetId) {
                ForEach(ProviderPreset.all) { preset in
                    Text(preset.name).tag(preset.id)
                }
            }
            .onChange(of: state.presetId) { state.presetChanged() }
            .disabled(state.overrides.provider)
            overrideNote(state.overrides.provider, "GRAMMARFIXER_PROVIDER")

            if state.preset.wantsItsOwnAddress {
                TextField("Address", text: $state.address, prompt: Text("https://example.com/v1"))
                    .onChange(of: state.address) { state.addressChanged() }
                    .disabled(state.overrides.address)
                overrideNote(state.overrides.address, "GRAMMARFIXER_BASE_URL")
            }

            keyField

            HStack {
                TextField("Model", text: $state.model, prompt: Text("model name"))
                    .onChange(of: state.model) { state.modelChanged() }
                    .disabled(state.overrides.model)
                modelListButton
            }
            overrideNote(state.overrides.model, "GRAMMARFIXER_MODEL")
            modelListNote

            Toggle("Ask the provider for token usage", isOn: $state.requestsUsage)
                .onChange(of: state.requestsUsage) { state.requestsUsageChanged() }
            Text("With this off, spending is guessed from the text instead of counted, and every "
                + "round is marked as an estimate. A few servers refuse the request outright; the "
                + "round is then sent again without it, and comes back without token counts.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(
                "Let the model think before answering",
                isOn: Binding(
                    get: { state.reasoning == .providerDefault },
                    set: {
                        state.reasoning = $0 ? .providerDefault : .off
                        state.reasoningChanged()
                    }
                )
            )
            Text("Correcting spelling needs no deliberation and is billed for it: "
                + "one model charged 2966 tokens for a 205-character answer, and eight with thinking off.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// The list comes from the provider, with the key that is already in the
    /// field beside it. This app knows no model names of its own: it would have
    /// to be taught each new one by hand, and that is the chore it exists to
    /// avoid.
    @ViewBuilder
    private var modelListButton: some View {
        switch state.modelList {
        case .loading:
            ProgressView().controlSize(.small)
        case .loaded(let models) where !models.isEmpty:
            Menu {
                ForEach(models, id: \.self) { name in
                    Button(name) {
                        state.model = name
                        state.modelChanged()
                    }
                }
                Divider()
                Button("Load again") { Task { await state.loadModels() } }
            } label: {
                Image(systemName: "list.bullet")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(state.overrides.model)
        default:
            Button {
                Task { await state.loadModels() }
            } label: {
                Image(systemName: "arrow.down.circle")
            }
            .buttonStyle(.borderless)
            .help("Ask the provider which models it has")
        }
    }

    @ViewBuilder
    private var modelListNote: some View {
        switch state.modelList {
        case .loaded(let models) where models.isEmpty:
            Text("The provider answered with no models this app could use. "
                + "Type the name in by hand.")
                .font(.footnote)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        default:
            EmptyView()
        }
    }

    private var keyField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SecureField("API key", text: $state.apiKey, prompt: Text("sk-…"))
                    .onChange(of: state.apiKey) { state.keyChanged() }
                    .disabled(state.overrides.key)
                Button("Check") {
                    Task { await state.checkKey() }
                }
                // There is nothing to check while the field is empty, and a
                // refusal saying so would be a window telling somebody off for
                // not having filled in the field they are looking at.
                .disabled(state.keyState == .checking || state.apiKey.trimmed.isEmpty)
            }
            overrideNote(state.overrides.key, "GRAMMARFIXER_API_KEY")

            if let failure = state.keyFailure {
                Label(failure.message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.footnote)
            } else {
                Text("Kept in the Keychain under \(state.preset.name), never in a settings file. "
                    + "Each provider keeps its own.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            switch state.keyState {
            case .untested:
                EmptyView()
            case .checking:
                Label("Asking the provider…", systemImage: "clock")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .checked(.working(let model)):
                Label("The key works, and \(model) answered", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.footnote)
            case .checked(.accepted(let models)):
                Label(
                    models.isEmpty
                        ? "The key works. This provider offers no list of models, so type the name in."
                        : "The key works. Choose a model below: \(models.count) to pick from.",
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(.green)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            case .checked(.refused(let title, let message)):
                VStack(alignment: .leading, spacing: 2) {
                    Label(title, systemImage: "xmark.circle.fill").foregroundStyle(.red)
                    Text(message).foregroundStyle(.secondary)
                }
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// A field showing one value while requests go out with another would be
    /// worse than no window at all.
    @ViewBuilder
    private func overrideNote(_ isOverridden: Bool, _ variable: String) -> some View {
        if isOverridden {
            Text("\(variable) is set, so it is used instead of this.")
                .font(.footnote)
                .foregroundStyle(.orange)
        }
    }


    // MARK: - Spending

    /// The second reason this app exists. The month's total, the limit that
    /// decides when it starts saying something, and the prices behind both.
    private var spendingSection: some View {
        Section("Spending") {
            HStack {
                Text("Monthly limit")
                Spacer()
                Text("$")
                    .foregroundStyle(.secondary)
                TextField("Monthly limit", text: $state.monthlyLimit, prompt: Text("3.00"))
                    .labelsHidden()
                    // Bordered on purpose: a plain field inside a grouped form
                    // reads as a label, and a price nobody realises they can
                    // edit is a price that stays wrong.
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: state.monthlyLimit) { state.limitChanged() }
            }
            Text("Soft: the correction is always sent. Past 80 per cent of the limit the panel says "
                + "where the month stands, and past the limit itself the menu bar icon turns red. "
                + "Zero means no limit at all.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            monthLine
            pricesEditor
            recentRounds
        }
    }

    private var monthLine: some View {
        let summary = state.summary
        let level = state.budget.level(spent: summary.total)
        return VStack(alignment: .leading, spacing: 4) {
            Label(summary.describe(limit: state.budget.limit), systemImage: level.systemImage)
                .foregroundStyle(level == .over ? Color.orange : .primary)

            if summary.rounds > 0 {
                // Tokens first among the details, because they are the part
                // that came from the provider rather than from a price list.
                Text("\(summary.rounds) \(summary.rounds == 1 ? "round" : "rounds") · \(summary.tokens)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Text(approximateNote(summary))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            providerBreakdown(summary)
        }
    }

    /// Who was paid what, and none of it while only one provider was used.
    @ViewBuilder
    private func providerBreakdown(_ summary: SpendSummary) -> some View {
        if !summary.providers.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(summary.providers) { provider in
                    HStack(spacing: 8) {
                        Text(providerName(provider.provider))
                        Spacer(minLength: 8)
                        Text("\(TokenCount.text(provider.promptTokens)) in"
                            + " + \(TokenCount.text(provider.completionTokens)) out")
                            .foregroundStyle(.secondary)
                        Text(provider.unpricedRounds == provider.rounds
                            ? "no price"
                            : "about \(Money.text(provider.total))")
                            .foregroundStyle(provider.unpricedRounds == provider.rounds
                                ? Color.orange
                                : .primary)
                            .frame(width: 84, alignment: .trailing)
                    }
                    .font(.caption)
                }
            }
            .padding(.top, 2)
        }
    }

    private func providerName(_ id: String) -> String {
        ProviderPreset.named(id)?.name ?? id
    }

    /// Why the figure above is a floor rather than a sum. Without this the
    /// total looks exact, and an exact-looking figure that is not exact is the
    /// thing this counter was built to avoid.
    ///
    /// The two facts are stated apart rather than added up. A round can be
    /// both unpriced and guessed, and one number covering both would report
    /// more shaky rounds than the month actually holds — the same kind of
    /// figure that looks solid without being solid.
    private func approximateNote(_ summary: SpendSummary) -> String {
        var facts = ["Amounts are approximate: they come from \(ModelsDev.name)'s published "
            + "prices, not from your provider's invoice."]
        if summary.unpricedRounds > 0 {
            facts.append("\(summary.unpricedRounds) of this month's \(summary.rounds) rounds have no "
                + "price for the model and are left out of the total.")
        }
        if summary.estimatedRounds > 0 {
            facts.append("\(summary.estimatedRounds) were counted from the text, because the "
                + "provider reported no tokens.")
        }
        return facts.joined(separator: " ")
    }

    /// Prices per million tokens, for the model in use and whatever this month
    /// has already been billed for. A model with an empty row is one nothing
    /// here can price; typing the two figures in counts it, and counts the
    /// rounds it already went through.
    @ViewBuilder
    private var pricesEditor: some View {
        if !state.priceRows.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Per million tokens, in and out")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    priceSource
                }

                ForEach($state.priceRows) { $row in
                    HStack(spacing: 8) {
                        Text(row.model)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help("\(row.provider) · \(row.model)")
                        if row.isCurrent {
                            Text("in use")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        TextField("in", text: $row.input, prompt: Text("—"))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 62)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: row.input) { state.priceChanged(row) }
                        TextField("out", text: $row.output, prompt: Text("—"))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 62)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: row.output) { state.priceChanged(row) }
                        Button {
                            state.forgetPrice(row)
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .buttonStyle(.borderless)
                        .disabled(!row.canBePutBack)
                        .help("Back to the price from \(ModelsDev.name)")
                    }
                    .labelsHidden()
                }

                Text("A price typed here wins over the fetched one, and counts the rounds that "
                    + "already went through at that rate, this month included. Leave a row empty "
                    + "and the round shows as unpriced rather than as free.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Where the prices came from and when, with the way to ask again.
    ///
    /// Named on screen rather than buried in a comment: this is a figure about
    /// somebody's own money, and they are entitled to know whose price list it
    /// rests on.
    @ViewBuilder
    private var priceSource: some View {
        HStack(spacing: 6) {
            if state.catalog.isLoading {
                ProgressView().controlSize(.small)
            } else if let failure = state.catalog.failure {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(failure)
            }
            Text(state.priceSourceNote)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button {
                Task { await state.loadPrices() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(state.catalog.isLoading)
            .help("Fetch the prices from \(ModelsDev.name) again")
        }
    }

    /// The last few rounds. Enough to see that the counter works and which
    /// rounds it had to guess at.
    @ViewBuilder
    private var recentRounds: some View {
        if !state.recentRounds.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Recent rounds")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ForEach(state.recentRounds) { record in
                    HStack(spacing: 8) {
                        Text(record.date, format: .dateTime.day().month().hour().minute())
                            .foregroundStyle(.secondary)
                        Text(record.model)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text("\(record.promptTokens) + \(record.completionTokens)")
                            .foregroundStyle(.secondary)
                        // An estimate is marked where it is shown, not only in
                        // the total: a row that looks exact makes the total
                        // look exact too.
                        Text(amount(for: record))
                            .foregroundStyle(shade(for: record))
                            .frame(width: 64, alignment: .trailing)
                    }
                    .font(.caption)
                }
            }
        }
    }

    private func amount(for record: UsageRecord) -> String {
        guard let cost = state.cost(of: record) else { return "no price" }
        return record.isEstimated ? "≈\(Money.text(cost))" : Money.text(cost)
    }

    /// Three kinds of row, three ways of reading. A figure nothing can price
    /// is the one that needs doing something about, so it is the one in
    /// orange; a guessed figure is dimmed beside an exact one, because a
    /// single glyph is easy to slide past in a column of amounts.
    private func shade(for record: UsageRecord) -> Color {
        if state.cost(of: record) == nil { return .orange }
        return record.isEstimated ? .secondary : .primary
    }

    // MARK: - The rest

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $state.theme) {
                ForEach(Theme.allCases, id: \.self) { theme in
                    Text(theme.name).tag(theme)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: state.theme) { state.themeChanged() }
        }
    }

    private var pasteSection: some View {
        Section("Pasting") {
            Toggle("Restore the clipboard after pasting", isOn: $state.restoreClipboard)
                .onChange(of: state.restoreClipboard) { state.restoreClipboardChanged() }
            Text("Restoring is never complete: promised and lazy clipboard types cannot be copied "
                + "because they hold no data yet.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Toggle("Paste by typing instead of ⌘V", isOn: $state.pasteByTyping)
                .onChange(of: state.pasteByTyping) { state.pasteByTypingChanged() }
            Text("Typing never touches the clipboard at all, but it is slower and some apps drop "
                + "characters.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var startupSection: some View {
        Section("Startup") {
            Toggle(
                "Start \(AppInfo.name) at login",
                isOn: Binding(get: { state.startsAtLogin }, set: { state.setStartsAtLogin($0) })
            )

            if let failure = state.loginItemFailure {
                Label("\(failure.title). \(failure.message)", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            } else if state.loginItemWaitsForApproval {
                Label(
                    "macOS is waiting for you to allow it: System Settings → General → Login Items.",
                    systemImage: "clock"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("The app has no Dock icon and no window of its own, so starting it by hand is "
                    + "something to remember after every restart.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var promptSection: some View {
        Section("Prompt") {
            TextEditor(text: $state.promptTemplate)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 160)
                .onChange(of: state.promptTemplate) { state.promptChanged() }

            if state.promptHasNoPlaceholder {
                Label(
                    "Without \(Prompt.placeholder) the model never sees your text, "
                        + "so the original prompt is used instead.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("\(Prompt.placeholder) is replaced with the selected text. The closing line "
                    + "does real work: it stops weaker models from writing \"Here is the corrected text:\".")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Back to the original") { state.resetPrompt() }
                    .disabled(state.promptIsTheDefault)
            }
        }
    }
}
