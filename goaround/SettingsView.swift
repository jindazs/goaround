//
//  SettingsView.swift
//  goaround
//
//  Created by Yuki Jin on 2024/07/13.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("webSites") private var webSitesData: Data = Data()
    @AppStorage("openInApp") private var openInAppData: Data = Data()
    @AppStorage("isSettingsCompleted") private var isSettingsCompleted: Bool = false
    @State private var webSites: [String]
    @State private var openInApp: [Bool]

    init() {
        // 新しい上限値に応じて、デフォルトのWebサイトとIn-App設定を変更します。
        let defaultWebSites = Array(repeating: "", count: 20) // ここで20を希望する上限値に変更
        let defaultOpenInApp = Array(repeating: true, count: 20)
        
        _webSites = State(initialValue: defaultWebSites)
        _openInApp = State(initialValue: defaultOpenInApp)
    }

    var body: some View {
        NavigationView {
            List {
                ForEach(0..<webSites.count, id: \.self) { index in
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Webサイト \(index + 1):")
                            TextField("URLを入力", text: $webSites[index])
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        }
                        Toggle("In-App", isOn: $openInApp[index])
                            .labelsHidden()
                    }
                }
            }
            .navigationTitle("設定")
            .navigationBarItems(trailing: Button("保存") {
                saveWebSites()
                isSettingsCompleted = true
            })
            .onAppear {
                loadWebSites()
            }
        }
    }

    private func saveWebSites() {
        if let data = try? JSONEncoder().encode(webSites) {
            webSitesData = data
        }
        if let data = try? JSONEncoder().encode(openInApp) {
            openInAppData = data
        }
    }

    private func loadWebSites() {
        if let webSites = try? JSONDecoder().decode([String].self, from: webSitesData) {
            self.webSites = webSites
        }
        if let openInApp = try? JSONDecoder().decode([Bool].self, from: openInAppData) {
            self.openInApp = openInApp
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
