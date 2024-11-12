import SwiftUI

struct ContentView: View {
    @AppStorage("webSites") private var webSitesData: Data = Data()
    @AppStorage("openInApp") private var openInAppData: Data = Data()
    @State private var webSites: [String] = []
    @State private var openInApp: [Bool] = []
    @State private var currentWebViewIndex: Int = 0
    @State private var reloadWebView: Bool = false
    @State private var lastTranslation: CGFloat = 0

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.15, green: 0.15, blue: 0.35)
                    .edgesIgnoringSafeArea(.all)
                
                if webSites.isEmpty {
                    Text("表示するWebサイトがありません")
                } else {
                    GeometryReader { geometry in
                            if !reloadWebView {
                                ForEach(Array(webSites.enumerated()), id: \.offset) { index, site in
                                    WebViewItem(
                                        site: site,
                                        index: index,
                                        openInApp: openInApp[index],
                                        geometrySize: geometry.size,
                                        currentWebViewIndex: $currentWebViewIndex,
                                        reloadWebView: $reloadWebView,
                                        totalWebViews: webSites.count
                                    )
                                }
                            }
                    }
                }

                VStack {
                    HStack(spacing: 10) {
                        ForEach(0..<webSites.count, id: \.self) { index in
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
                        Spacer()
                        viewChanger()
                            .offset(x: 25)
                    }
                    .gesture(dragGesture)
                    .highPriorityGesture(TapGesture(count: 2)
                        .onEnded {
                            reloadWebView = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                reloadWebView = false
                            }
                        }
                    )
                    
                    Spacer()
                    
                    HStack {
                        Button(action: {
                            goBack()
                        }) {
                            Image(systemName: "arrowshape.turn.up.backward")
                                .resizable()
                                .frame(width: 15, height: 15)
                                .padding(10)
                                .background(Color.white.opacity(0.8))
                                .clipShape(Circle())
                                .shadow(radius: 10)
                        }
                        .padding()
                        .offset(y: 32)
                        .highPriorityGesture(TapGesture(count: 2)
                            .onEnded{
                                reloadWebView = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    reloadWebView = false
                                }
                            }
                        )

                        Spacer()

                        NavigationLink(destination: SettingsView()) {
                            Image(systemName: "gearshape")
                                .resizable()
                                .frame(width: 15, height: 15)
                                .padding(10)
                                .background(Color.white.opacity(0.8))
                                .clipShape(Circle())
                                .shadow(radius: 10)
                        }
                        .padding()
                        .offset(y: 32)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarHidden(true)
            .onAppear {
                loadWebSites()
            }
        }
    }

    // WebViewContainerをラップしたサブビュー
    private struct WebViewItem: View {
        let site: String
        let index: Int
        let openInApp: Bool
        let geometrySize: CGSize
        @Binding var currentWebViewIndex: Int
        @Binding var reloadWebView: Bool
        let totalWebViews: Int

        var body: some View {
            WebViewContainer(
                urlString: site,
                openInApp: openInApp,
                reloadWebView: $reloadWebView,
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
                        lastTranslation = value.translation.height
                    } else {
                        goToPreviousBySwipe()
                        lastTranslation = value.translation.height
                    }
                }
            }
    }

    private struct viewChanger: View {
        var body: some View {
            Capsule()
                .fill(Color.blue.opacity(0.2))
                .frame(width: 50, height: 150)
        }
    }

    private func loadWebSites() {
        if let decodedWebSites = try? JSONDecoder().decode([String].self, from: webSitesData) {
            webSites = decodedWebSites.filter { !$0.isEmpty }
        } else {
            webSites = Array(repeating: "", count: 20)
        }

        if let decodedOpenInApp = try? JSONDecoder().decode([Bool].self, from: openInAppData) {
            openInApp = zip(webSites, decodedOpenInApp)
                .filter { !$0.0.isEmpty }
                .map { $0.1 }
        } else {
            openInApp = Array(repeating: true, count: 20)
        }
    }

    private func goToNext() {
        if currentWebViewIndex < webSites.count - 1 {
            currentWebViewIndex += 1
        }
    }
    
    private func goToNextBySwipe() {
        if currentWebViewIndex < webSites.count - 1 {
            currentWebViewIndex += 1
        } else {
            currentWebViewIndex = 0
        }
    }

    private func goToPrevious() {
        if currentWebViewIndex > 0 {
            currentWebViewIndex -= 1
        }
    }
    
    private func goToPreviousBySwipe() {
        if currentWebViewIndex > 0 {
            currentWebViewIndex -= 1
        } else {
            currentWebViewIndex = webSites.count - 1
        }
    }
    
    private func goBack() {
        // 通知を発行
        NotificationCenter.default.post(name: .goBackInWebView, object: nil, userInfo: ["index": currentWebViewIndex])
    }
}

// 角を丸めるためのカスタム形状
struct RoundedCorners: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// 通知用の拡張
extension Notification.Name {
    static let goBackInWebView = Notification.Name("goBackInWebView")
}

// プレビュー用のコードを追加
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
