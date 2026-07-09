import SwiftUI

struct ContentView: View {
    @AppStorage("webSiteSettings") private var webSiteSettingsData: Data = Data()
    @AppStorage("webSites") private var legacyWebSitesData: Data = Data()
    @AppStorage("openInApp") private var legacyOpenInAppData: Data = Data()
    @State private var webSiteSettings: [WebSiteSetting] = []
    @State private var currentWebViewIndex: Int = 0
    @State private var reloadAllWebViewsTrigger: Int = 0
    @State private var showSettings: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.1, green: 0.1, blue: 0.1)
                    .edgesIgnoringSafeArea(.all)
                
                if webSiteSettings.isEmpty {
                    Text("表示するWebサイトがありません")
                } else {
                    GeometryReader { geometry in
                        ForEach(Array(webSiteSettings.enumerated()), id: \.element.id) { index, setting in
                            WebViewItem(
                                setting: setting,
                                index: index,
                                geometrySize: geometry.size,
                                currentWebViewIndex: $currentWebViewIndex,
                                reloadAllWebViewsTrigger: reloadAllWebViewsTrigger,
                                totalWebViews: webSiteSettings.count
                            )
                        }
                    }
                }

                VStack {
                    HStack(spacing: 10) {
                        ForEach(webSiteSettings.indices, id: \.self) { index in
                            Circle()
                                .fill(index == currentWebViewIndex ? Color.white : Color.white.opacity(0.5))
                                .frame(width: 10, height: 10)
                                .onTapGesture {
                                    withAnimation {
                                        currentWebViewIndex = index
                                    }
                                }
                                .offset(y: -10)
                        }
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 0) {
                        viewChanger()
                            .offset(x: -25)
                            .simultaneousGesture(LongPressGesture().onEnded { _ in
                                goBack()
                            })

                        Spacer()

                        viewChanger()
                            .offset(x: 25)
                            .simultaneousGesture(LongPressGesture().onEnded { _ in
                                showSettings = true
                            })
                    }
                    .gesture(dragGesture)
                    .highPriorityGesture(TapGesture(count: 2)
                        .onEnded {
                            reloadAllWebViewsTrigger += 1
                        }
                    )
                    
                    Spacer()
                }
            }
            .navigationTitle("")
            .navigationBarHidden(true)
            .onAppear {
                loadWebSites()
            }
            .onChange(of: webSiteSettingsData) { _, _ in
                loadWebSites()
            }
            .onChange(of: legacyWebSitesData) { _, _ in
                loadWebSites()
            }
            .onChange(of: legacyOpenInAppData) { _, _ in
                loadWebSites()
            }
            .sheet(isPresented: $showSettings, onDismiss: {
                loadWebSites()
            }) {
                SettingsView()
            }
        }
    }

    // WebViewContainerをラップしたサブビュー
    private struct WebViewItem: View {
        let setting: WebSiteSetting
        let index: Int
        let geometrySize: CGSize
        @Binding var currentWebViewIndex: Int
        let reloadAllWebViewsTrigger: Int
        let totalWebViews: Int

        var body: some View {
            WebViewContainer(
                urlString: setting.trimmedURL,
                openInApp: setting.openInApp,
                reloadAllWebViewsTrigger: reloadAllWebViewsTrigger,
                index: index,
                currentWebViewIndex: $currentWebViewIndex,
                totalWebViews: totalWebViews
            )
            .offset(y: offsetValue)
            .opacity(opacityValue)
            .zIndex(zIndexValue)
            .animation(.easeOut(duration: 0.1), value: currentWebViewIndex)
            .frame(height: geometrySize.height)
        }

        private var offsetValue: CGFloat {
            currentWebViewIndex == index ? 0 : geometrySize.height * (index > currentWebViewIndex ? 1.2 : -1.2)
        }

        private var opacityValue: Double {
            (currentWebViewIndex == index || index == currentWebViewIndex - 1 || index == currentWebViewIndex + 1) ? 1 : 0
        }

        private var zIndexValue: Double {
            Double(index == currentWebViewIndex ? 1 : 0)
        }
    }

    // 共通のジェスチャを返すプロパティ
    private var dragGesture: some Gesture {
        DragGesture()
            .onEnded { value in
                let minimumDistance: CGFloat = 50 // フリックと判定する最小距離
                let minimumSpeed: CGFloat = 50   // フリックと判定する最小速度
                
                let translation = value.translation
                let velocity = value.predictedEndTranslation
                
                if abs(translation.height) > minimumDistance && abs(velocity.height) > minimumSpeed {
                    if translation.height > 0 {
                        goToNextBySwipe()
                    } else {
                        goToPreviousBySwipe()
                    }
                }
            }
    }

    private struct viewChanger: View {
        var body: some View {
            Capsule()
                .fill(Color(red: 0.15, green: 0.15, blue: 0.35).opacity(0.2))
                .frame(width: 50, height: 150)
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.5), lineWidth: 0.5) // 白い縁取りを追加
                )
        }
    }

    private func loadWebSites() {
        webSiteSettings = WebSiteSettingsStore.configuredSettings(
            settingsData: webSiteSettingsData,
            legacyWebSitesData: legacyWebSitesData,
            legacyOpenInAppData: legacyOpenInAppData
        )

        if webSiteSettings.isEmpty {
            currentWebViewIndex = 0
        } else if currentWebViewIndex >= webSiteSettings.count {
            currentWebViewIndex = webSiteSettings.count - 1
        }
    }

    private func goToNextBySwipe() {
        guard !webSiteSettings.isEmpty else { return }

        if currentWebViewIndex < webSiteSettings.count - 1 {
            currentWebViewIndex += 1
        } else {
            currentWebViewIndex = 0
        }
    }

    private func goToPreviousBySwipe() {
        guard !webSiteSettings.isEmpty else { return }

        if currentWebViewIndex > 0 {
            currentWebViewIndex -= 1
        } else {
            currentWebViewIndex = webSiteSettings.count - 1
        }
    }
    
    private func goBack() {
        // 通知を発行
        NotificationCenter.default.post(name: .goBackInWebView, object: nil, userInfo: ["index": currentWebViewIndex])
    }
}

// 通知用の拡張
extension Notification.Name {
    static let goBackInWebView = Notification.Name("goBackInWebView")
}
