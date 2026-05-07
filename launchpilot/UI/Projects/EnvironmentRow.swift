import SwiftUI

struct EnvironmentRow: View {
    let check: EnvironmentCheck

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: check.iconName)
                .foregroundStyle(statusColor)
                .font(.body)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(check.displayName)
                        .font(.callout.weight(.medium))
                    if check.severity == .required, !check.isSatisfied {
                        Text("REQUIRED")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.red.opacity(0.18)))
                            .foregroundStyle(.red)
                    }
                    Spacer(minLength: 0)
                    statusLabel
                }
                if let detail = check.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                if let hint = check.installHint, !check.isSatisfied {
                    Text(.init(hint))
                        .font(.caption)
                        .foregroundStyle(.tint)
                        .textSelection(.enabled)
                }
            }
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch check.status {
        case .ok(let version):
            Text(version ?? "Found")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        case .warning:
            Text("Check")
                .font(.caption.weight(.medium))
                .foregroundStyle(.orange)
        case .missing:
            Text("Missing")
                .font(.caption.weight(.medium))
                .foregroundStyle(.red)
        case .error:
            Text("Error")
                .font(.caption.weight(.medium))
                .foregroundStyle(.red)
        }
    }

    private var statusColor: Color {
        switch check.status {
        case .ok: return .green
        case .warning: return .orange
        case .missing, .error: return .red
        }
    }
}
