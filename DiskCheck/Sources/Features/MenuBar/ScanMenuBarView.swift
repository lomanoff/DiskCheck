import AppKit
import SwiftUI

struct ScanMenuBarLabel: View {
    let store: DiskScanStore

    var body: some View {
        if store.isScanning {
            HStack(spacing: 4) {
                Image(systemName: "internaldrive.badge.magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)

                Text(menuBarProgressText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .monospacedDigit()
            }
        } else {
            Image(systemName: "internaldrive.badge.magnifyingglass")
                .symbolRenderingMode(.hierarchical)
        }
    }

    private var menuBarProgressText: String {
        if store.scanPhase == .estimating {
            return "…"
        }
        return "\(Int(store.scanProgressFraction * 100))%"
    }
}

struct ScanMenuBarView: View {
    let store: DiskScanStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.isScanning {
                Text(store.scanPhase == .estimating ? "Подсчёт объектов…" : "Сканирование")
                    .font(.headline)

                if let target = store.scanningTargetName {
                    Text(target)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                ProgressView(value: store.scanProgressFraction, total: 1)

                if store.scanVolumeUsedTarget > 0 {
                    Text("\(ByteFormatter.format(store.scanDiscoveredBytes)) из \(ByteFormatter.format(store.scanVolumeUsedTarget))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Text(store.scanProgress.isEmpty ? "…" : store.scanProgress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text("DiskCheck")
                    .font(.headline)

                Text("Сканирование не выполняется")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button("Открыть DiskCheck") {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        .padding(12)
        .frame(width: 260)
    }
}
