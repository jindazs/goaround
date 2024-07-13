//
//  File.swift
//  goaround
//
//  Created by Yuki Jin on 2024/07/13.
//

import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
    let urlString: String
    let openInApp: Bool

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if let url = URL(string: urlString) {
            let request = URLRequest(url: url)
            uiView.load(request)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self, openInApp: openInApp)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebView
        var openInApp: Bool

        init(_ parent: WebView, openInApp: Bool) {
            self.parent = parent
            self.openInApp = openInApp
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url, !openInApp {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
