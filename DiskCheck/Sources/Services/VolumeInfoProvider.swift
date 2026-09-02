import Foundation

enum VolumeInfoProvider {
    static func availableVolumes() -> [VolumeInfo] {
        var volumes: [VolumeInfo] = []
        var seenPaths = Set<String>()

        if let dataVolume = volumeInfo(
            at: URL(fileURLWithPath: "/System/Volumes/Data"),
            displayName: "Macintosh HD"
        ) {
            volumes.append(dataVolume)
            seenPaths.insert(dataVolume.url.path)
        }

        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeIsRemovableKey,
            .volumeIsInternalKey,
        ]

        let mounted = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) ?? []

        for url in mounted {
            let scanURL = scanningURL(for: url)
            guard !seenPaths.contains(scanURL.path) else { continue }
            guard shouldIncludeVolume(url: url, scanURL: scanURL) else { continue }

            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  let name = values.volumeName,
                  let total = values.volumeTotalCapacity,
                  let available = values.volumeAvailableCapacity
            else { continue }

            let volume = VolumeInfo(
                id: scanURL.path,
                name: displayName(for: url, resourceName: name),
                url: scanURL,
                totalCapacity: Int64(total),
                availableSpace: Int64(available)
            )
            volumes.append(volume)
            seenPaths.insert(scanURL.path)
        }

        return volumes.sorted { $0.totalCapacity > $1.totalCapacity }
    }

    /// URL, который нужно сканировать для выбранного тома.
    static func scanningURL(for volume: VolumeInfo) -> URL {
        scanningURL(for: volume.url)
    }

    static func scanningURL(for url: URL) -> URL {
        let path = url.path
        if path == "/" || path == "/System/Volumes/Update/mnt1" {
            let dataURL = URL(fileURLWithPath: "/System/Volumes/Data")
            if FileManager.default.fileExists(atPath: dataURL.path) {
                return dataURL
            }
        }
        return url
    }

    private static func volumeInfo(at url: URL, displayName: String) -> VolumeInfo? {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacity
        else { return nil }

        return VolumeInfo(
            id: url.path,
            name: displayName,
            url: url,
            totalCapacity: Int64(total),
            availableSpace: Int64(available)
        )
    }

    private static func shouldIncludeVolume(url: URL, scanURL: URL) -> Bool {
        let excludedPrefixes = [
            "/System/Volumes/Preboot",
            "/System/Volumes/VM",
            "/System/Volumes/xarts",
            "/System/Volumes/iSCPreboot",
            "/System/Volumes/Hardware",
            "/System/Volumes/Update",
            "/private/var/folders",
        ]
        let path = scanURL.path
        if excludedPrefixes.contains(where: { path.hasPrefix($0) }) { return false }
        if path == "/" { return false }
        return true
    }

    private static func displayName(for mountURL: URL, resourceName: String) -> String {
        if mountURL.path == "/" || resourceName == "Macintosh HD" {
            return "Macintosh HD"
        }
        return resourceName
    }
}
