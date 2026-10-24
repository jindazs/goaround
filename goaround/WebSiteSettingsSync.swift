import Foundation
import Combine

protocol SettingsCloudStore: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ value: Data?, forKey key: String)
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: SettingsCloudStore {}

/// One versioned value keeps the order and per-page options consistent across devices.
struct WebSiteSettingsSnapshot: Codable, Equatable {
    var version = 1
    var modifiedAt: Date
    var revision = UUID().uuidString
    var settings: [WebSiteSetting]

    func isNewer(than other: Self) -> Bool {
        modifiedAt == other.modifiedAt ? revision > other.revision : modifiedAt > other.modifiedAt
    }
}

final class WebSiteSettingsSync: ObservableObject {
    static let shared = WebSiteSettingsSync()
    static let cloudKey = "webSiteSettings.snapshot.v1"
    static let migrationSuppressedKey = "webSiteSettings.suppressMigration"
    static let localKey = "webSiteSettings.localSnapshot.v1"
    @Published private(set) var message = "同じApple Accountの端末で登録ページを自動同期します。反映には時間がかかる場合があります。"

    private let defaults: UserDefaults
    private let cloud: SettingsCloudStore
    private var observer: NSObjectProtocol?

    init(defaults: UserDefaults = .standard, cloud: SettingsCloudStore = NSUbiquitousKeyValueStore.default) {
        self.defaults = defaults
        self.cloud = cloud
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud, queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let reason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            if reason == NSUbiquitousKeyValueStoreQuotaViolationChange {
                self.message = "iCloudの同期容量を超えました。登録ページはこの端末に保存されています。"
            } else if reason == NSUbiquitousKeyValueStoreAccountChange {
                // Do not upload the previous account's cached list into a new account.
                self.defaults.removeObject(forKey: Self.localKey)
                self.defaults.set(true, forKey: Self.migrationSuppressedKey)
                if let remote = self.decode(self.cloud.data(forKey: Self.cloudKey)) {
                    self.persist(remote)
                }
            } else {
                self.reconcile()
            }
        }
        refresh()
    }

    func refresh() {
        if !cloud.synchronize() {
            message = "iCloudを利用できません。登録ページはこの端末に保存され、利用可能になると同期されます。"
        }
        reconcile()
    }

    func save(_ settings: [WebSiteSetting], now: Date = Date()) {
        let local = decode(defaults.data(forKey: Self.localKey))
        let remote = decode(cloud.data(forKey: Self.cloudKey))
        let latestDate = [local?.modifiedAt, remote?.modifiedAt].compactMap { $0 }.max() ?? .distantPast
        let snapshot = WebSiteSettingsSnapshot(
            modifiedAt: max(now, latestDate.addingTimeInterval(0.001)),
            settings: WebSiteSettingsStore.normalizedForSaving(settings)
        )
        persist(snapshot)
        publish(snapshot)
    }

    func reconcile() {
        let remote = decode(cloud.data(forKey: Self.cloudKey))
        let local = decode(defaults.data(forKey: Self.localKey))
        if let remote {
            if let local, local.isNewer(than: remote) {
                publish(local)
            } else {
                persist(remote)
            }
        } else if let local {
            publish(local)
        } else {
            guard !defaults.bool(forKey: Self.migrationSuppressedKey),
                  cloud.data(forKey: Self.cloudKey) == nil else { return }
            let existing = WebSiteSettingsStore.editableSettings(defaults: defaults)
            guard existing.contains(where: \.isConfigured) else { return }
            // Migration is older than every explicit save, including a delayed initial download.
            let migrated = WebSiteSettingsSnapshot(modifiedAt: .distantPast, settings: existing)
            persist(migrated)
            publish(migrated)
        }
    }

    private func decode(_ data: Data?) -> WebSiteSettingsSnapshot? {
        guard let data,
              let snapshot = try? JSONDecoder().decode(WebSiteSettingsSnapshot.self, from: data),
              snapshot.version == 1,
              snapshot.settings.count <= Constants.maxWebSites,
              Set(snapshot.settings.map(\.id)).count == snapshot.settings.count else { return nil }
        return snapshot
    }

    private func persist(_ snapshot: WebSiteSettingsSnapshot) {
        guard let data = WebSiteSettingsStore.encode(snapshot.settings),
              let metadata = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(metadata, forKey: Self.localKey)
        if defaults.data(forKey: WebSiteSettingsStore.settingsKey) != data {
            defaults.set(data, forKey: WebSiteSettingsStore.settingsKey)
            WebSiteSettingsStore.saveLegacyValues(snapshot.settings, defaults: defaults)
        }
    }

    private func publish(_ snapshot: WebSiteSettingsSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        guard data.count < 1_000_000 else {
            message = "登録ページのデータが大きすぎるため、iCloudに同期できません。この端末には保存されています。"
            return
        }
        if cloud.data(forKey: Self.cloudKey) != data {
            cloud.set(data, forKey: Self.cloudKey)
        }
    }
}
