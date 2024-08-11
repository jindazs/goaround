import SwiftUI
import WebKit

struct WebViewContainer: UIViewRepresentable {
    let urlString: String
    let openInApp: Bool
    @Binding var reloadWebView: Bool
    let index: Int
    @Binding var currentWebViewIndex: Int

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

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

        init(_ parent: WebViewContainer) {
            self.parent = parent
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
