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
    @State private var webSites: [String] = [
        "https://www.google.com"
    ]
    @State private var openInApp: [Bool] = Array(repeating: true, count: 10)

    var body: some View {
        NavigationView {
            List {
                ForEach(0..<10, id: \.self) { index in
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
