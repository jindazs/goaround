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
                    Color(red: 0.15, green: 0.15, blue: 0.15)
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
                                                //.padding(.bottom, 40)
                                                .opacity(currentWebViewIndex == index ? 1 : 0)
                                                .animation(.easeInOut, value: currentWebViewIndex)
                                                .frame(width: geometry.size.width - 4, height: geometry.size.height-40)
                                                //.position(x: 0 + geometry.safeAreaInsets.leading)
                                                //.offset(x:-2)
                                                .clipShape(RoundedCorners(radius: 20, corners: [.topRight, .bottomRight]))
                                                
                                                Spacer()
                                            }
                                            
                                            Spacer()
                                        }
                                    }
                                }
       
                                

                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(width: geometry.size.width, height: geometry.size.height)
                                    .contentShape(Rectangle())
                                    .gesture(DragGesture(minimumDistance: 10, coordinateSpace: .local)
                                        .onEnded { value in
                                            let threshold: CGFloat = 0.1
                                            let startX = value.startLocation.x / geometry.size.width

                                            if startX < threshold {
                                                //goToPrevious()
                                                goBack()
                                            } else if startX > 1 - threshold {
                                                goToNextBySwipe()
                                            }
                                        }
                                    )

                                // ドットとジェスチャー判定部分を表示
                                VStack {
                                    Spacer()
                                    HStack {
                                        Spacer()

                                        ZStack {
                                            // 半透明の黒い判定領域
                                            Rectangle()
                                                .fill(Color.black.opacity(0.01))
                                                .frame(width: geometry.size.width * 0.6, height: 40)
                                                .gesture(DragGesture()
                                                    .onChanged { value in
                                                        let dragThreshold: CGFloat = 16
                                                        let dragAmount = value.translation.width - lastTranslation

                                                        if dragAmount < -dragThreshold {
                                                            goToPrevious()
                                                            lastTranslation = value.translation.width
                                                        } else if dragAmount > dragThreshold {
                                                            goToNext()
                                                            lastTranslation = value.translation.width
                                                        }
                                                    }
                                                    .onEnded { _ in
                                                        lastTranslation = 0
                                                    }
                                                )
                                                .onTapGesture(count: 2) {
                                                    reloadWebView = true
                                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                                        reloadWebView = false
                                                    }
                                                }

                                            // ドット表示
                                            HStack(spacing: 10) {
                                                ForEach(0..<webSites.count, id: \.self) { index in
                                                    Circle()
                                                        .fill(index == currentWebViewIndex ? Color.white : Color.gray.opacity(0.5))
                                                        .frame(width: 10, height: 10)
                                                        .onTapGesture {
                                                            withAnimation {
                                                                currentWebViewIndex = index
                                                            }
                                                        }
                                                }
                                            }
                                        }

                                        Spacer()
                                    }
                                    .padding(.bottom, 30)
                                    .offset(y: 35)
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
                                    .frame(width: 25, height: 25)
                                    .padding(10)
                                    .background(Color.white.opacity(0.8))
                                    .clipShape(Circle())
                                    .shadow(radius: 10)
                            }
                            .padding()
                            .offset(y: 25)

                            Spacer()

                            NavigationLink(destination: SettingsView()) {
                                Image(systemName: "gearshape")
                                    .resizable()
                                    .frame(width: 25, height: 25)
                                    .padding(10)
                                    .background(Color.white.opacity(0.8))
                                    .clipShape(Circle())
                                    .shadow(radius: 10)
                            }
                            .padding()
                            .offset(y: 25)
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
