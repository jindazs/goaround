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
        let savedData = UserDefaults.standard.data(forKey: "webSiteSettings") ?? Data()
        let decoded: [WebSiteSetting]
        if let saved = try? JSONDecoder().decode([WebSiteSetting].self, from: savedData) {
            decoded = saved
        } else {
            decoded = defaultSettings
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
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
