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
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        // ユーザーエージェントをiPad用に設定
        webView.customUserAgent = "Mozilla/5.0 (iPad; CPU OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Mobile/15E148 Safari/604.1"

        // 通知リスナーを追加
        NotificationCenter.default.addObserver(forName: .goBackInWebView, object: nil, queue: .main) { [weak webView] notification in
            if let userInfo = notification.userInfo, let notifiedIndex = userInfo["index"] as? Int, notifiedIndex == self.index {
                // 現在のWebViewが対象の場合のみ戻る操作を実行
                if webView?.canGoBack == true {
                    webView?.goBack()
                }
            }
        }
        
        // エッジスワイプジェスチャーの追加
        let edgeSwipeGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleEdgeSwipeGesture(_:)))
        webView.addGestureRecognizer(edgeSwipeGesture)
        
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
    
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, UIGestureRecognizerDelegate {
        var parent: WebViewContainer
        var originalPosition: CGPoint?
        var transitioning = false

        init(_ parent: WebViewContainer) {
            self.parent = parent
        }

        // エッジスワイプジェスチャーのハンドラー
        @objc func handleEdgeSwipeGesture(_ gesture: UIPanGestureRecognizer) {
            guard let webView = gesture.view as? WKWebView else { return }
            let translation = gesture.translation(in: webView)
            _ = translation.x / webView.frame.width

            switch gesture.state {
            case .began:
                originalPosition = webView.frame.origin
                transitioning = false

            case .changed:
                if translation.x > 0, webView.canGoBack {
                    if let originalPosition = originalPosition {
                        let newX = max(translation.x + originalPosition.x, 0)
                        webView.frame.origin.x = newX
                    }
                } else if translation.x < 0, webView.canGoForward {
                    if let originalPosition = originalPosition {
                        let newX = min(translation.x + originalPosition.x, 0)
                        webView.frame.origin.x = newX
                    }
                }

            case .ended:
                let velocity = gesture.velocity(in: webView)
                if translation.x > 100 || velocity.x > 500 {
                    if webView.canGoBack {
                        UIView.animate(withDuration: 0.1, animations: {
                            webView.frame.origin.x = webView.frame.size.width
                        }, completion: { _ in
                            webView.goBack()
                            webView.frame.origin.x = 0
                        })
                    } else {
                        UIView.animate(withDuration: 0.1) {
                            webView.frame.origin.x = 0
                        }
                    }
                } else if translation.x < -100 || velocity.x < -500 {
                    if webView.canGoForward {
                        UIView.animate(withDuration: 0.1, animations: {
                            webView.frame.origin.x = -webView.frame.size.width
                        }, completion: { _ in
                            webView.goForward()
                            UIView.animate(withDuration: 0.1) {
                                webView.frame.origin.x = 0
                            }
                        })
                    } else {
                        UIView.animate(withDuration: 0.1) {
                            webView.frame.origin.x = 0
                        }
                    }
                } else {
                    UIView.animate(withDuration: 0.1) {
                        webView.frame.origin.x = 0
                    }
                }
                
                transitioning = false
                
            default:
                break
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
