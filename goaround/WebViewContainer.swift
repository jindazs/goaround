import SwiftUI
@preconcurrency import WebKit

struct WebViewContainer: UIViewRepresentable {
    let urlString: String
    let openInApp: Bool
    @Binding var reloadWebView: Bool
    let index: Int
    @Binding var currentWebViewIndex: Int
    let totalWebViews: Int // WebViewの総数
    
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        
        // 動画・音声の自動再生をオフにする設定
        configuration.mediaTypesRequiringUserActionForPlayback = [.video, .audio]
        // インライン再生を許可する設定を追加
        configuration.allowsInlineMediaPlayback = true
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        // デバイスの種類に応じてユーザーエージェントを設定
        if UIDevice.current.userInterfaceIdiom == .phone {
            // iPhone用のユーザーエージェント
            webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        } else {
            // iPad用のユーザーエージェント
            webView.customUserAgent = "Mozilla/5.0 (iPad; CPU OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Mobile/15E148 Safari/604.1"
        }

        // スワイプで進む・戻るを有効にする
        webView.allowsBackForwardNavigationGestures = true

        // 通知リスナーを追加
        NotificationCenter.default.addObserver(forName: .goBackInWebView, object: nil, queue: .main) { [weak webView] notification in
            if let userInfo = notification.userInfo, let notifiedIndex = userInfo["index"] as? Int, notifiedIndex == self.index {
                // 現在のWebViewが対象の場合のみ戻る操作を実行
                if webView?.canGoBack == true {
                    webView?.goBack()
                }
            }
        }
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        if reloadWebView && currentWebViewIndex == index {
            if uiView.canGoBack {
                uiView.goBack()
            } else {
                loadURL(uiView)
            }
            DispatchQueue.main.async {
                reloadWebView = false
            }
        } else if uiView.url == nil {
            loadURL(uiView)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    private func loadURL(_ webView: WKWebView) {
        if let url = URL(string: urlString) {
            let request = URLRequest(url: url)
            webView.load(request)
        }
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: WebViewContainer
        weak var webView: WKWebView?
        var observers: [NSObjectProtocol] = []

        init(_ parent: WebViewContainer) {
            self.parent = parent
        }

        func configure(webView: WKWebView, index: Int) {
            self.webView = webView
            // go back observer
            let backObs = NotificationCenter.default.addObserver(forName: .goBackInWebView, object: nil, queue: .main) { [weak self] notification in
                guard let self = self, let webView = self.webView else { return }
                if let userInfo = notification.userInfo, let notifiedIndex = userInfo["index"] as? Int, notifiedIndex == index {
                    if webView.canGoBack {
                        webView.goBack()
                    }
                }
            }
            observers.append(backObs)

            let pageObs = NotificationCenter.default.addObserver(forName: .pageDownInWebView, object: nil, queue: .main) { [weak self] notification in
                guard let self = self, let webView = self.webView else { return }
                if let userInfo = notification.userInfo, let notifiedIndex = userInfo["index"] as? Int, notifiedIndex == index {
                    let scrollView = webView.scrollView
                    let offset = CGPoint(x: 0, y: scrollView.contentOffset.y + scrollView.bounds.height)
                    scrollView.setContentOffset(offset, animated: true)
                }
            }
            observers.append(pageObs)
        }

        deinit {
            for obs in observers {
                NotificationCenter.default.removeObserver(obs)
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url, !parent.openInApp {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        func webViewDidClose(_ webView: WKWebView) {
            // 必要に応じてUIを更新
        }
    }
}
