import SwiftUI

struct VolumeInsightsView: View {
    let health: VolumeHealthReport?
    let iCloudSummary: ICloudStorageSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let iCloudSummary, iCloudSummary.hasContent {
                iCloudSection(iCloudSummary)
            }

            if let health {
                systemSection(health)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private func iCloudSection(_ summary: ICloudStorageSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("iCloud на диске", systemImage: "icloud.fill")
                .font(.subheadline.weight(.semibold))

            if summary.iCloudDriveSize > 0 {
                insightRow(
                    title: "iCloud Drive",
                    value: ByteFormatter.format(summary.iCloudDriveSize)
                )
            }

            if summary.mobileDocumentsSize > 0 {
                insightRow(
                    title: "Mobile Documents",
                    value: "\(summary.mobileDocumentsCount) · \(ByteFormatter.format(summary.mobileDocumentsSize))"
                )
            }

            if summary.nosyncCount > 0 {
                insightRow(
                    title: ".nosync (не в облаке)",
                    value: "\(summary.nosyncCount) · \(ByteFormatter.format(summary.nosyncSize))"
                )
            }

            if summary.locallyStoredSize > 0 {
                insightRow(
                    title: "Скачано локально",
                    value: ByteFormatter.format(summary.locallyStoredSize)
                )
            }

            if summary.cloudOnlySize > 0 {
                insightRow(
                    title: "Только в облаке",
                    value: ByteFormatter.format(summary.cloudOnlySize)
                )
            }

            Text("Локальные .nosync можно найти в категории «.nosync».")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func systemSection(_ health: VolumeHealthReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Диск и система", systemImage: "internaldrive")
                .font(.subheadline.weight(.semibold))

            if let fileSystem = health.fileSystem {
                insightRow(title: "Файловая система", value: fileSystem)
            }

            insightRow(title: health.smartStatus.title, value: health.isEncrypted ? "Зашифрован" : "Не зашифрован")

            if health.hasTimeMachineSnapshots {
                insightRow(
                    title: "Снапшоты Time Machine",
                    value: timeMachineSnapshotLabel(health)
                )

                HStack(spacing: 8) {
                    Button("Управление снапшотами") {
                        SystemIntegration.openTimeMachineSettings()
                    }
                    .controlSize(.small)

                    Button("Справка") {
                        SystemIntegration.openTimeMachineSnapshotsHelp()
                    }
                    .controlSize(.small)
                }
            }

            Button("Проверить диск в Дисковой утилите") {
                SystemIntegration.openDiskUtility()
            }
            .controlSize(.small)
        }
    }

    private func insightRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.primary)
        }
    }

    private func timeMachineSnapshotLabel(_ health: VolumeHealthReport) -> String {
        if let bytes = health.timeMachineSnapshotBytes, bytes > 0 {
            return "\(health.timeMachineSnapshotCount) · \(ByteFormatter.format(bytes))"
        }
        return "\(health.timeMachineSnapshotCount)"
    }
}

struct DiskHealthBanner: View {
    let health: VolumeHealthReport

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)

            VStack(alignment: .leading, spacing: 2) {
                Text("Проблема с диском, а не с файлами")
                    .font(.subheadline.weight(.semibold))
                Text("SMART сообщает об ошибке на томе «\(health.volumeName)». Освобождение места не исправит аппаратную неисправность.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Проверить диск") {
                SystemIntegration.openDiskUtility()
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.red.opacity(0.08))
    }
}
