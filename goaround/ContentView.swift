//
//  ContentView.swift
//  goaround
//
//  Created by Yuki Jin on 2024/07/13.
//

import SwiftUI

struct ContentView: View {
    @AppStorage("webSites") private var webSitesData: Data = Data()
    @AppStorage("openInApp") private var openInAppData: Data = Data()
    @State private var webSites: [String] = []
    @State private var openInApp: [Bool] = []

    var body: some View {
        NavigationView {
            ZStack {
                if !webSites.isEmpty {
                    TabView {
                        ForEach(Array(webSites.enumerated()), id: \.offset) { index, site in
                            WebView(urlString: site, openInApp: openInApp[index])
                                .tabItem {
                                    Text(URL(string: site)?.host ?? "Web Page")
                                }
                        }
                    }
                    .tabViewStyle(PageTabViewStyle())
                } else {
                    Text("表示するWebサイトがありません")
                }

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        NavigationLink(destination: SettingsView()) {
                            Image(systemName: "gearshape")
                                .resizable()
                                .frame(width: 30, height: 30)
                                .padding(10)
                                .background(Color.white.opacity(0.8))
                                .clipShape(Circle())
                                .shadow(radius: 10)
                        }
                        .padding()
                    }
                }
            }
            .navigationBarTitle("", displayMode: .inline)
            .navigationBarHidden(true)
        }
        .onAppear {
            loadWebSites()
        }
    }

    private func loadWebSites() {
        if let webSites = try? JSONDecoder().decode([String].self, from: webSitesData) {
            self.webSites = webSites.filter { !$0.isEmpty }
        } else {
            self.webSites = []
        }

        if let openInApp = try? JSONDecoder().decode([Bool].self, from: openInAppData) {
            self.openInApp = zip(webSites, openInApp).filter { !$0.0.isEmpty }.map { $0.1 }
        } else {
            self.openInApp = []
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
