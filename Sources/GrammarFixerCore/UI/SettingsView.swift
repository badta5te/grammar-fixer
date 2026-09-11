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
            providerSection
            appearanceSection
            pasteSection
            promptSection
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 620)
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
