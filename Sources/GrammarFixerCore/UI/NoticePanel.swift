import AppKit
import SwiftUI

/// Сообщение об ошибке. Обычный NSAlert здесь не годится: приложение-агент
/// неактивно, и модальное окно может не получить ни фокуса, ни показа. Панель
/// со свойствами FloatingPanel показывается гарантированно.
@MainActor
public final class NoticePanel {
    private var panel: FloatingPanel?
    private var dismissTask: Task<Void, Never>?

    public init() {}

    public func show(_ error: RoundTripError, timeout: TimeInterval = 8) {
        show(title: error.title, message: error.message, timeout: timeout)
    }

    public func show(title: String, message: String, timeout: TimeInterval = 8) {
        dismiss()

        let panel = FloatingPanel(styleMask: [.borderless]) {
            NoticeView(title: title, message: message)
        }
        panel.dismissOnOutsideClick { [weak self] in self?.dismiss() }
        panel.present()
        self.panel = panel

        // Сообщение не должно висеть вечно: у приложения нет ни дока, ни окна,
        // куда пользователь мог бы к нему вернуться.
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
