//
//  ContentView.swift
//  goaround
//
//  Created by Yuki Jin on 2024/07/13.
//　memo

import SwiftUI

struct ContentView: View {
    @AppStorage("webSites") private var webSitesData: Data = Data()
    @AppStorage("openInApp") private var openInAppData: Data = Data()
    @State private var webSites: [String] = []
    @State private var openInApp: [Bool] = []
    @State private var currentWebViewIndex: Int = 0
    @State private var reloadWebView: Bool = false

    var body: some View {
        NavigationView {
            ZStack {
                if webSites.isEmpty {
                    Text("表示するWebサイトがありません")
                } else {
                    ZStack {
                        TabView(selection: $currentWebViewIndex) {
                            ForEach(Array(webSites.enumerated()), id: \.offset) { index, site in
                                WebView(urlString: site, openInApp: openInApp[index], reloadWebView: $reloadWebView)
                                    .tabItem {
                                        Text(URL(string: site)?.host ?? "Web Page")
                                    }
                                    .tag(index)
                            }
                        }
                        .tabViewStyle(PageTabViewStyle())
                        .gesture(DragGesture(minimumDistance: 20, coordinateSpace: .local)
                            .onEnded { value in
                                if value.translation.width < -50 {
                                    goToNext()
                                } else if value.translation.width > 50 {
                                    goToPrevious()
                                }
                            }
                        )
                    }
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
                                .onTapGesture(count: 2) {
                                    reloadWebView = true
                                }
                        }
                        .padding()
                    }
                }
            }
            .navigationBarTitle("", displayMode: .inline)
            .navigationBarHidden(true)
            .onAppear {
                loadWebSites()
            }
        }
    }

    private func loadWebSites() {
        if let decodedWebSites = try? JSONDecoder().decode([String].self, from: webSitesData) {
            webSites = decodedWebSites.filter { !$0.isEmpty }
        } else {
            webSites = []
        }

        if let decodedOpenInApp = try? JSONDecoder().decode([Bool].self, from: openInAppData) {
            openInApp = zip(webSites, decodedOpenInApp)
                .filter { !$0.0.isEmpty }
                .map { $0.1 }
        } else {
            openInApp = []
        }
    }

    private func goToNext() {
        if currentWebViewIndex < webSites.count - 1 {
            currentWebViewIndex += 1
        }
    }

    private func goToPrevious() {
        if currentWebViewIndex > 0 {
            currentWebViewIndex -= 1
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
