import SwiftUI

struct ContentView: View {
    @AppStorage("webSites") private var webSitesData: Data = Data()
    @AppStorage("openInApp") private var openInAppData: Data = Data()
    @State private var webSites: [String] = []
    @State private var openInApp: [Bool] = []
    @State private var currentWebViewIndex: Int = 0
    @State private var reloadWebView: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                if webSites.isEmpty {
                    Text("表示するWebサイトがありません")
                } else {
                    GeometryReader { geometry in
                        ZStack {
                            ForEach(Array(webSites.enumerated()), id: \.offset) { index, site in
                                WebViewContainer(
                                    urlString: site,
                                    openInApp: openInApp[index],
                                    reloadWebView: $reloadWebView,
                                    index: index,
                                    currentWebViewIndex: $currentWebViewIndex
                                )
                                .padding(.bottom, geometry.size.height * 0.05) // 下部の余白を設定
                                .opacity(currentWebViewIndex == index ? 1 : 0)
                                .animation(.easeInOut, value: currentWebViewIndex) // スムーズなアニメーションを適用
                            }

                            // 画面左右端からのスワイプを検出
                            Rectangle()
                                .fill(Color.clear)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .contentShape(Rectangle()) // タップ領域をフルにする
                                .gesture(DragGesture(minimumDistance: 10, coordinateSpace: .local)
                                    .onEnded { value in
                                        let threshold: CGFloat = 0.05 // 画面の5%の幅
                                        let startX = value.startLocation.x / geometry.size.width

                                        if startX < threshold {
                                            // 左端からのスワイプ
                                            goToPrevious()
                                        } else if startX > 1 - threshold {
                                            // 右端からのスワイプ
                                            goToNext()
                                        }
                                    }
                                )
                        }
                    }
                }

                VStack {
                    Spacer()
                    HStack {
                        // 左下に戻るボタンを配置
                        Button(action: {
                            goBack()
                        }) {
                            Image(systemName: "arrowshape.turn.up.backward")
                                .resizable()
                                .frame(width: 25, height: 25)
                                .padding(10)
                                .background(Color.white.opacity(0.8))
                                .clipShape(Circle())
                                .shadow(radius: 10)
                        }
                        .padding()
                        .offset(y: 25) // ボタンを25ポイント下げる

                        Spacer()

                        NavigationLink(destination: SettingsView()) {
                            Image(systemName: "gearshape")
                                .resizable()
                                .frame(width: 25, height: 25)
                                .padding(10)
                                .background(Color.white.opacity(0.8))
                                .clipShape(Circle())
                                .shadow(radius: 10)
                                .onTapGesture(count: 2) {
                                    reloadWebView = true
                                }
                        }
                        .padding()
                        .offset(y: 25) // ボタンを25ポイント下げる
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

    private func loadWebSites() {
        if let decodedWebSites = try? JSONDecoder().decode([String].self, from: webSitesData) {
            webSites = decodedWebSites.filter { !$0.isEmpty }
        } else {
            webSites = Array(repeating: "", count: 20) // 希望する上限値に変更
        }

        if let decodedOpenInApp = try? JSONDecoder().decode([Bool].self, from: openInAppData) {
            openInApp = zip(webSites, decodedOpenInApp)
                .filter { !$0.0.isEmpty }
                .map { $0.1 }
        } else {
            openInApp = Array(repeating: true, count: 20) // 希望する上限値に変更
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

    private func goBack() {
        // 現在表示中のWebViewに戻る動作を指示
        reloadWebView = true // WebViewに戻るアクションを伝えるフラグを設定
    }
}
