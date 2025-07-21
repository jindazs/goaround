//
//  SettingsView.swift
//  goaround
//
//  Created by Yuki Jin on 2024/07/13.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("webSiteSettings") private var webSiteSettingsData: Data = Data()
    @AppStorage("isSettingsCompleted") private var isSettingsCompleted: Bool = false
    @State private var webSiteSettings: [WebSiteSetting]
    @Environment(\.editMode) private var editMode

    struct WebSiteSetting: Identifiable, Codable {
        let id: UUID
        var url: String
        var openInApp: Bool
        init(id: UUID = UUID(), url: String, openInApp: Bool) {
            self.id = id
            self.url = url
            self.openInApp = openInApp
        }
    }

    init() {
        let defaultSettings = Array(
            repeating: WebSiteSetting(url: "", openInApp: true),
            count: Constants.maxWebSites
        )
        let savedData = UserDefaults.standard.data(forKey: "webSiteSettings")
        let decoded: [WebSiteSetting]
        if let savedData,
           let saved = try? JSONDecoder().decode([WebSiteSetting].self, from: savedData) {
            decoded = saved
        } else {
            // Try to initialize from separate values used by ContentView
            let urlsData = UserDefaults.standard.data(forKey: "webSites") ?? Data()
            let openInAppData = UserDefaults.standard.data(forKey: "openInApp") ?? Data()
            let urls = (try? JSONDecoder().decode([String].self, from: urlsData)) ?? []
            let openInApp = (try? JSONDecoder().decode([Bool].self, from: openInAppData)) ?? []
            var combined = zip(urls, openInApp).map { WebSiteSetting(url: $0.0, openInApp: $0.1) }
            while combined.count < Constants.maxWebSites {
                combined.append(WebSiteSetting(url: "", openInApp: true))
            }
            decoded = combined.isEmpty ? defaultSettings : combined
        }
        _webSiteSettings = State(initialValue: decoded)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(webSiteSettings.indices, id: \.self) { index in
                    VStack {
                        TextField("URLを入力", text: $webSiteSettings[index].url)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        HStack {
                            Spacer()
                            Text("Open In-App").foregroundColor(.gray)
                            Toggle("", isOn: $webSiteSettings[index].openInApp)
                                .labelsHidden()
                        }
                    }
                }
                .onMove(perform: moveWebSite)
            }
            .navigationTitle("設定")
            .toolbar {
                EditButton()
            }
            .onChange(of: editMode?.wrappedValue) { oldValue, newValue in
                if newValue == .inactive {
                    saveSettings()
                }
            }
            .onDisappear {
                saveSettings()
                isSettingsCompleted = true
            }
        }
    }

    private func moveWebSite(from source: IndexSet, to destination: Int) {
        webSiteSettings.move(fromOffsets: source, toOffset: destination)
    }

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(webSiteSettings) {
            webSiteSettingsData = data
        }
        // Update values used by ContentView
        let urls = webSiteSettings.map { $0.url }
        let openInAppValues = webSiteSettings.map { $0.openInApp }
        if let urlsData = try? JSONEncoder().encode(urls) {
            UserDefaults.standard.set(urlsData, forKey: "webSites")
        }
        if let openInAppData = try? JSONEncoder().encode(openInAppValues) {
            UserDefaults.standard.set(openInAppData, forKey: "openInApp")
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
