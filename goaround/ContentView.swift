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
                            ZStack {
                                if !reloadWebView {
                                    ForEach(Array(webSites.enumerated()), id: \.offset) { index, site in
                                        HStack {
                                            VStack {
                                                WebViewContainer(
                                                    urlString: site,
                                                    openInApp: openInApp[index],
                                                    reloadWebView: $reloadWebView,
                                                    index: index,
                                                    currentWebViewIndex: $currentWebViewIndex,
                                                    totalWebViews: webSites.count // ここで総数を渡す
                                                )
                                                .offset(x: currentWebViewIndex == index ? 0 : geometry.size.width * (index > currentWebViewIndex ? 1 : -1))
                                                .opacity(currentWebViewIndex == index || index == currentWebViewIndex - 1 || index == currentWebViewIndex + 1 ? 1 : 0)
                                                .zIndex(Double(index == currentWebViewIndex ? 1 : 0)) // 表示順序を制御
                                                .animation(.easeOut(duration:0.1), value: currentWebViewIndex)
                                                .frame(height: geometry.size.height-26)
                                                //.clipShape(RoundedCorners(radius: 20, corners: [.topRight, .topLeft]))
                                                //.edgesIgnoringSafeArea(.top)
                                                
                                                Spacer()
                                                
                                            }
                                            
                                        }
                                    }
                                }

                                // ドットとジェスチャー判定部分を表示
                                VStack {
                                    Spacer()
                                    
                                    HStack(spacing: 0) {
                                        Color.clear
                                            .contentShape(Rectangle())
                                            .frame(width: geometry.size.width, height: 50)
                                            .gesture(DragGesture()
                                                .onEnded { value in
                                                    let minimumDistance: CGFloat = 50 // フリックと判定する最小距離
                                                    let minimumSpeed: CGFloat = 50   // フリックと判定する最小速度
                                                    
                                                    let translation = value.translation
                                                    let velocity = value.predictedEndTranslation
                                                    
                                                    if abs(translation.width) > minimumDistance && abs(velocity.width) > minimumSpeed {
                                                                if translation.width > 0 {
                                                                    goToPreviousBySwipe()
                                                                    lastTranslation = value.translation.width
                                                                } else {
                                                                    goToNextBySwipe()
                                                                    lastTranslation = value.translation.width
                                                                }
                                                            }
                                                }
                                            )
                                            .highPriorityGesture(TapGesture(count: 2)
                                                .onEnded{
                                                    reloadWebView = true
                                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                                        reloadWebView = false
                                                    }
                                                }
                                            )
                                    }
                                    .offset(y: 20)
                                
                                    // ドット表示
                                    HStack(spacing: 10) {
                                        ForEach(0..<webSites.count, id: \.self) { index in
                                            Circle()
                                                .fill(index == currentWebViewIndex ? Color.white : Color.white.opacity(0.5))
                                                .frame(width: 10, height: 10)
                                                //.offset(y: 20)
                                                .onTapGesture {
                                                    withAnimation {
                                                        currentWebViewIndex = index
                                                    }
                                                }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    VStack {
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
    
    // goToPrevious関数を修正: 0番目の場合は一番右のWebViewに遷移
    private func goToPreviousBySwipe() {
        if currentWebViewIndex > 0 {
            currentWebViewIndex -= 1
        } else {
            currentWebViewIndex = webSites.count
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
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
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
