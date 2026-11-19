import SwiftUI

/// Toast tipo "Live Activity" con el resultado del último comando o escena.
struct FeedbackToast: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible: CommandFeedback?
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            if let feedback = visible {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: feedback.isError ? "exclamationmark.triangle.fill" : feedback.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(feedback.isError ? Theme.Palette.danger : Theme.Palette.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(feedback.title).font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.Palette.textPrimary)
                        if let message = feedback.message {
                            Text(message).font(Typography.label)
                                .foregroundStyle(feedback.isError ? Theme.Palette.danger : Theme.Palette.textSecondary)
                        }
                    }
                    if !feedback.isError {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.Palette.success)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .frame(minHeight: 44)
                .background(Capsule().fill(Color.black))
                .overlay(Capsule().strokeBorder(feedback.isError ? Theme.Palette.danger.opacity(0.5) : Theme.Palette.border))
                .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.9)))
                .accessibilityElement(children: .combine)
                .id(feedback.id)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : Theme.Motion.spring, value: visible?.id)
        .onChange(of: model.bus.lastFeedback) { _, newValue in
            guard let newValue else { return }
            visible = newValue
            hideTask?.cancel()
            hideTask = Task {
                try? await Task.sleep(for: .milliseconds(newValue.isError ? 3500 : 1800))
                guard !Task.isCancelled else { return }
                visible = nil
            }
        }
        .allowsHitTesting(false)
    }
}
