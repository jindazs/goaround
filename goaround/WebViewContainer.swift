//
//  WebViewContainer.swift
//  goaround
//
//  Created by Yuki Jin on 2024/07/15.
//

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

        // ダブルタップで戻る動作
        let doubleTapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        doubleTapGesture.delegate = context.coordinator
        webView.addGestureRecognizer(doubleTapGesture)

        // トリプルタップでgearshapeのダブルタップと同じ動作
        let tripleTapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTripleTap(_:)))
        tripleTapGesture.numberOfTapsRequired = 3
        tripleTapGesture.delegate = context.coordinator
        webView.addGestureRecognizer(tripleTapGesture)

        // ダブルタップとトリプルタップの競合を避ける
        doubleTapGesture.require(toFail: tripleTapGesture)

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if reloadWebView && currentWebViewIndex == index {
            loadURL(uiView)
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

        @objc func handleDoubleTap(_ sender: UITapGestureRecognizer) {
            if parent.currentWebViewIndex == parent.index, let webView = sender.view as? WKWebView {
                if webView.canGoBack {
                    webView.goBack()
                }
            }
        }

        @objc func handleTripleTap(_ sender: UITapGestureRecognizer) {
            if parent.currentWebViewIndex == parent.index {
                parent.reloadWebView = true
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
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
