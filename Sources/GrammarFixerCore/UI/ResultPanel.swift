import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The result panel. The correction appears here first and goes nowhere until
/// the person says so: ⏎ pastes it back where the text came from, ⌘⏎ takes the
/// clipboard, Esc leaves everything as it was.
@MainActor
public final class ResultPanel: ResultPresenting {
    private var panel: ResultWindow?

    public init() {}

    public func present(_ session: CorrectionSession) async -> ResultDecision {
        let panel = ResultWindow(session: session)
        self.panel = panel

        let decision = await withCheckedContinuation { continuation in
            let gate = DecisionGate()
            // Every way out is funnelled through one place. Two resumes trap,
            // and a way out that resumes nothing leaves the round open and the
            // shortcut dead until the app is restarted.
            let finish: (ResultDecision) -> Void = { decision in
                guard !gate.resumed else { return }
                gate.resumed = true
                continuation.resume(returning: decision)
            }
            panel.onDecision = finish
            panel.dismissOnOutsideClick { finish(.dismissed) }
            panel.present()
        }

        await release(panel)
        self.panel = nil
        return decision
    }

    /// Ordering the panel out is not the same as handing keyboard focus back.
    /// The panel held key status while it was open, and a synthetic ⌘V goes
    /// wherever the keyboard is pointing — which, until this returns, is still
    /// us. A fixed delay here would be the "sometimes it pasted into the wrong
    /// window" bug in a new place, so the wait is on the thing itself.
    private func release(_ panel: ResultWindow) async {
        panel.dismiss()
        for _ in 0 ..< 40 {
            guard NSApp.keyWindow != nil else { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        Log.write("the panel did not give up the keyboard within 200 ms")
    }
}

/// A resume-once flag. A local `var` captured by two escaping closures is not
/// something the compiler will let pass, and the guard has to be shared.
@MainActor
private final class DecisionGate {
    var resumed = false
}

/// The window itself. Keyboard handling lives here rather than in SwiftUI: the
/// panel has no focusable controls, and a keypress with nowhere to land never
/// reaches a view.
@MainActor
final class ResultWindow: FloatingPanel {
    var onDecision: ((ResultDecision) -> Void)?
    private let session: CorrectionSession

    init(session: CorrectionSession) {
        self.session = session
        super.init(styleMask: [.borderless]) {
            ResultView(session: session)
        }
    }

    override func keyDown(with event: NSEvent) {
        let isReturn = Int(event.keyCode) == kVK_Return || Int(event.keyCode) == kVK_ANSI_KeypadEnter
        guard isReturn else {
            super.keyDown(with: event)
            return
        }

        if event.modifierFlags.contains(.command) {
            if let text = session.result { onDecision?(.copy(text)) }
            return
        }
        if let text = session.result {
            onDecision?(.paste(text))
            return
        }
        // Nothing to paste yet: still waiting, or the round failed. A retry is
        // what ⏎ means then, and while the answer is still arriving the press
        // is ignored — the panel already says on its face why.
        if session.hasFailed { session.start() }
    }
}

private struct ResultView: View {
    let session: CorrectionSession

    private let bodyWidth: CGFloat = 560
    private let bodyHeight: CGFloat = 220

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            budgetBanner

            // The size is fixed on purpose. The window takes its size from the
            // content, and a panel that grew with every piece of the answer
            // would jump about the screen while being read.
            content
                .frame(width: bodyWidth, height: bodyHeight, alignment: .topLeading)
                .padding(20)

            Divider()
            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.separator, lineWidth: 1)
        )
    }

    /// The month, when the month is worth mentioning. It sits above the answer
    /// rather than in the footer: the footer is read after the decision and
    /// this is meant to be read before it. It never stands in the way — the
    /// correction below it is finished and ⏎ still pastes it.
    @ViewBuilder
    private var budgetBanner: some View {
        if let notice = session.budgetNotice {
            HStack(spacing: 8) {
                Image(systemName: notice.level.systemImage)
                Text(notice.text)
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(notice.level == .over ? Color.orange : .secondary)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .frame(width: bodyWidth + 40, alignment: .leading)
            Divider()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch session.state {
        case .waiting:
            // A round takes seconds, and seconds of an empty window read as a
            // broken app.
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Waiting for the model…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

        case .streaming(let text):
            answer(text, isComplete: false)

        case .finished(let text):
            answer(text, isComplete: true)

        case .failed(let title, let message):
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                ScrollView {
                    Text(message)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// The answer itself. While it is arriving it is plain text; once it is
    /// whole the words the model changed are tinted. The scrolling deliberately
    /// still watches the plain text: the tinted value is rebuilt on every
    /// redraw, and handing that to `onChange` would set the panel scrolling
    /// every time anything else on it moved.
    private func answer(_ text: String, isComplete: Bool) -> some View {
        ScrollViewReader { scroll in
            ScrollView {
                Text(session.diff?.highlighted ?? AttributedString(text))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(Self.answerID)
            }
            // While the answer is arriving the newest line is the interesting
            // one; once it is whole, the beginning is.
            .onChange(of: text) {
                scroll.scrollTo(Self.answerID, anchor: isComplete ? .top : .bottom)
            }
        }
    }

    private static let answerID = "answer"

    private var footer: some View {
        HStack(spacing: 12) {
            Text(session.model.isEmpty ? AppInfo.name : session.model)
            if let text = shownText {
                Text("·")
                Text(TextMetrics.describe(text))
            }
            // Only once the answer is whole: a count that climbed while the
            // text arrived would be counting words that had not been compared
            // with anything yet.
            if let diff = session.diff {
                Text("·")
                Text(TextMetrics.describeChanges(diff.changes))
            }
            Spacer()
            Text(hints)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var shownText: String? {
        switch session.state {
        case .streaming(let text), .finished(let text): text
        case .waiting, .failed: nil
        }
    }

    private var hints: String {
        switch session.state {
        case .waiting, .streaming: "esc cancel"
        case .finished: "⏎ paste · ⌘⏎ copy · esc close"
        case .failed: "⏎ retry · esc close"
        }
    }
}
