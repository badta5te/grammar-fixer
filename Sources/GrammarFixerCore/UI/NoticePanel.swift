import AppKit
import SwiftUI

/// An error message. A plain NSAlert will not do: an agent app is inactive, and
/// a modal window may get neither focus nor a chance to appear. A panel with
/// FloatingPanel's properties is shown reliably.
@MainActor
public final class NoticePanel: NoticePresenting {
    private var panel: FloatingPanel?
    private var dismissTask: Task<Void, Never>?

    public init() {}

    public func show(_ error: any UserFacingError) {
        show(title: error.title, message: error.message)
    }

    public func show(title: String, message: String, timeout: TimeInterval = 8) {
        dismiss()

        let panel = FloatingPanel(styleMask: [.borderless]) {
            NoticeView(title: title, message: message)
        }
        panel.dismissOnOutsideClick { [weak self] in self?.dismiss() }
        panel.present()
        self.panel = panel

        // The message must not hang around forever: the app has no Dock icon
        // and no window a person could come back to it through.
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            self.dismiss()
        }
    }

    public func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        panel?.dismiss()
        panel = nil
    }
}

private struct NoticeView: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("esc to dismiss")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(20)
        .frame(width: 460, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.separator, lineWidth: 1)
        )
    }
}
