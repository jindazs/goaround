//
//  SettingsView.swift
//  goaround
//
//  Created by Yuki Jin on 2024/07/13.
//

import SwiftUI
import UniformTypeIdentifiers

struct WebSiteSetting: Identifiable, Codable, Equatable {
    var id: UUID
    var url: String
    var openInApp: Bool

    init(id: UUID = UUID(), url: String, openInApp: Bool) {
        self.id = id
        self.url = url
        self.openInApp = openInApp
    }

    var trimmedURL: String {
        url.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isConfigured: Bool {
        !trimmedURL.isEmpty
    }
}

struct WebSiteSettingsExport: Codable {
    struct Site: Codable {
        var url: String
        var openInApp: Bool
    }

    var version: Int = 1
    var sites: [Site]
}

enum WebSiteSettingsTransferError: LocalizedError {
    case noImportableURLs
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .noImportableURLs:
            "インポートできるURLがありません"
        case .unsupportedFormat:
            "対応していないファイル形式です"
        }
    }
}

enum WebSiteSettingsTransfer {
    static func exportData(from settings: [WebSiteSetting]) throws -> Data {
        let export = WebSiteSettingsExport(
            sites: WebSiteSettingsStore.normalizedForSaving(settings)
                .filter(\.isConfigured)
                .map { WebSiteSettingsExport.Site(url: $0.trimmedURL, openInApp: $0.openInApp) }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(export)
    }

    static func importedSettings(from data: Data) throws -> [WebSiteSetting] {
        let decoder = JSONDecoder()

        if let export = try? decoder.decode(WebSiteSettingsExport.self, from: data) {
            return try validated(export.sites.map { WebSiteSetting(url: $0.url, openInApp: $0.openInApp) })
        }

        if let sites = try? decoder.decode([WebSiteSettingsExport.Site].self, from: data) {
            return try validated(sites.map { WebSiteSetting(url: $0.url, openInApp: $0.openInApp) })
        }

        if let settings = try? decoder.decode([WebSiteSetting].self, from: data) {
            return try validated(settings)
        }

        if let urls = try? decoder.decode([String].self, from: data) {
            return try validated(urls.map { WebSiteSetting(url: $0, openInApp: true) })
        }

        guard let text = String(data: data, encoding: .utf8) else {
            throw WebSiteSettingsTransferError.unsupportedFormat
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedText.hasPrefix("{") || trimmedText.hasPrefix("[") {
            throw WebSiteSettingsTransferError.unsupportedFormat
        }

        let separators = CharacterSet.newlines.union(CharacterSet(charactersIn: ","))
        let settings = text
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .map { WebSiteSetting(url: $0, openInApp: true) }

        return try validated(settings)
    }

    private static func validated(_ settings: [WebSiteSetting]) throws -> [WebSiteSetting] {
        let normalized = WebSiteSettingsStore.normalizedForSaving(settings).filter(\.isConfigured)
        guard !normalized.isEmpty else {
            throw WebSiteSettingsTransferError.noImportableURLs
        }

        return normalized
    }
}

struct URLListDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.json, .plainText, .text]
    }

    var data: Data

    init(settings: [WebSiteSetting] = []) {
        data = (try? WebSiteSettingsTransfer.exportData(from: settings)) ?? Data()
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum WebSiteSettingsStore {
    static let settingsKey = "webSiteSettings"
    static let legacyWebSitesKey = "webSites"
    static let legacyOpenInAppKey = "openInApp"

    static func editableSettings(defaults: UserDefaults = .standard) -> [WebSiteSetting] {
        editableSettings(
            settingsData: defaults.data(forKey: settingsKey) ?? Data(),
            legacyWebSitesData: defaults.data(forKey: legacyWebSitesKey) ?? Data(),
            legacyOpenInAppData: defaults.data(forKey: legacyOpenInAppKey) ?? Data()
        )
    }

    static func editableSettings(
        settingsData: Data,
        legacyWebSitesData: Data,
        legacyOpenInAppData: Data
    ) -> [WebSiteSetting] {
        let loaded = loadSettings(
            settingsData: settingsData,
            legacyWebSitesData: legacyWebSitesData,
            legacyOpenInAppData: legacyOpenInAppData
        )

        if loaded.isEmpty {
            return emptySettings()
        }

        return paddedSettings(loaded)
    }

    static func editableSettings(from settings: [WebSiteSetting]) -> [WebSiteSetting] {
        let normalized = normalizedForSaving(settings)
        return normalized.isEmpty ? emptySettings() : paddedSettings(normalized)
    }

    static func configuredSettings(
        settingsData: Data,
        legacyWebSitesData: Data,
        legacyOpenInAppData: Data
    ) -> [WebSiteSetting] {
        loadSettings(
            settingsData: settingsData,
            legacyWebSitesData: legacyWebSitesData,
            legacyOpenInAppData: legacyOpenInAppData
        )
        .filter(\.isConfigured)
    }

    static func normalizedForSaving(_ settings: [WebSiteSetting]) -> [WebSiteSetting] {
        uniqueSettings(settings.prefix(Constants.maxWebSites).map { setting in
            var copy = setting
            copy.url = copy.trimmedURL
            return copy
        })
    }

    static func encode(_ settings: [WebSiteSetting]) -> Data? {
        try? JSONEncoder().encode(normalizedForSaving(settings))
    }

    static func saveLegacyValues(_ settings: [WebSiteSetting], defaults: UserDefaults = .standard) {
        let normalized = normalizedForSaving(settings)
        let urls = normalized.map(\.url)
        let openInAppValues = normalized.map(\.openInApp)

        if let urlsData = try? JSONEncoder().encode(urls) {
            defaults.set(urlsData, forKey: legacyWebSitesKey)
        }

        if let openInAppData = try? JSONEncoder().encode(openInAppValues) {
            defaults.set(openInAppData, forKey: legacyOpenInAppKey)
        }
    }

    private static func loadSettings(
        settingsData: Data,
        legacyWebSitesData: Data,
        legacyOpenInAppData: Data
    ) -> [WebSiteSetting] {
        if let saved = try? JSONDecoder().decode([WebSiteSetting].self, from: settingsData),
           !saved.isEmpty {
            return uniqueSettings(saved)
        }

        return legacySettings(webSitesData: legacyWebSitesData, openInAppData: legacyOpenInAppData)
    }

    private static func legacySettings(webSitesData: Data, openInAppData: Data) -> [WebSiteSetting] {
        let urls = (try? JSONDecoder().decode([String].self, from: webSitesData)) ?? []
        let openInApp = (try? JSONDecoder().decode([Bool].self, from: openInAppData)) ?? []
        let count = max(urls.count, openInApp.count)

        return uniqueSettings((0..<count).map { index in
            WebSiteSetting(
                url: index < urls.count ? urls[index] : "",
                openInApp: index < openInApp.count ? openInApp[index] : true
            )
        })
    }

    private static func paddedSettings(_ settings: [WebSiteSetting]) -> [WebSiteSetting] {
        var padded = Array(uniqueSettings(settings).prefix(Constants.maxWebSites))

        while padded.count < Constants.maxWebSites {
            padded.append(WebSiteSetting(url: "", openInApp: true))
        }

        return padded
    }

    private static func emptySettings() -> [WebSiteSetting] {
        (0..<Constants.maxWebSites).map { _ in WebSiteSetting(url: "", openInApp: true) }
    }

    private static func uniqueSettings<S: Sequence>(_ settings: S) -> [WebSiteSetting] where S.Element == WebSiteSetting {
        var seenIDs = Set<UUID>()

        return settings.map { setting in
            var copy = setting

            if seenIDs.contains(copy.id) {
                copy.id = UUID()
            }

            seenIDs.insert(copy.id)
            return copy
        }
    }
}

struct SettingsView: View {
    @AppStorage("webSiteSettings") private var webSiteSettingsData: Data = Data()
    @AppStorage("isSettingsCompleted") private var isSettingsCompleted: Bool = false
    @State private var webSiteSettings: [WebSiteSetting]
    @State private var isImportingURLs = false
    @State private var isExportingURLs = false
    @State private var exportDocument = URLListDocument()
    @State private var importExportMessage = ""
    @State private var isShowingImportExportMessage = false
    @Environment(\.editMode) private var editMode
    @Environment(\.dismiss) private var dismiss

    init() {
        _webSiteSettings = State(initialValue: WebSiteSettingsStore.editableSettings())
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach($webSiteSettings) { $setting in
                    VStack {
                        TextField("URLを入力", text: $setting.url)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        HStack {
                            Spacer()
                            Text("Open In-App").foregroundColor(.gray)
                            Toggle("", isOn: $setting.openInApp)
                                .labelsHidden()
                        }
                    }
                }
                .onMove(perform: moveWebSite)

                Section {
                    Button("URL一覧をインポート") {
                        isImportingURLs = true
                    }
                    Button("URL一覧をエクスポート") {
                        exportURLList()
                    }
                }
            }
            .navigationTitle("設定")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完了") {
                        completeSettings()
                    }
                }
            }
            .onChange(of: editMode?.wrappedValue) { oldValue, newValue in
                if newValue == .inactive {
                    saveSettings()
                }
            }
            .onDisappear {
                saveSettings()
            }
            .fileImporter(
                isPresented: $isImportingURLs,
                allowedContentTypes: URLListDocument.readableContentTypes,
                allowsMultipleSelection: false,
                onCompletion: handleImport
            )
            .fileExporter(
                isPresented: $isExportingURLs,
                document: exportDocument,
                contentType: .json,
                defaultFilename: "goaround-urls",
                onCompletion: handleExport
            )
            .alert("URL一覧", isPresented: $isShowingImportExportMessage) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importExportMessage)
            }
        }
    }

    private func moveWebSite(from source: IndexSet, to destination: Int) {
        webSiteSettings.move(fromOffsets: source, toOffset: destination)
    }

    private func saveSettings() {
        let normalized = WebSiteSettingsStore.normalizedForSaving(webSiteSettings)

        if let data = WebSiteSettingsStore.encode(normalized) {
            webSiteSettingsData = data
        }

        WebSiteSettingsStore.saveLegacyValues(normalized)
    }

    private func completeSettings() {
        saveSettings()
        isSettingsCompleted = true
        dismiss()
    }

    private func exportURLList() {
        let configuredSettings = WebSiteSettingsStore.normalizedForSaving(webSiteSettings).filter(\.isConfigured)

        guard !configuredSettings.isEmpty else {
            showImportExportMessage("エクスポートできるURLがありません")
            return
        }

        exportDocument = URLListDocument(settings: configuredSettings)
        isExportingURLs = true
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            guard let fileURL = try result.get().first else {
                throw WebSiteSettingsTransferError.unsupportedFormat
            }

            let importedSettings = try readImportedSettings(from: fileURL)
            webSiteSettings = WebSiteSettingsStore.editableSettings(from: importedSettings)
            saveSettings()
            showImportExportMessage("\(importedSettings.count)件のURLをインポートしました")
        } catch {
            showImportExportMessage(error.localizedDescription)
        }
    }

    private func handleExport(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            showImportExportMessage("URL一覧をエクスポートしました")
        case .failure(let error):
            showImportExportMessage(error.localizedDescription)
        }
    }

    private func readImportedSettings(from fileURL: URL) throws -> [WebSiteSetting] {
        let canAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if canAccess {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: fileURL)
        return try WebSiteSettingsTransfer.importedSettings(from: data)
    }

    private func showImportExportMessage(_ message: String) {
        importExportMessage = message
        isShowingImportExportMessage = true
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
