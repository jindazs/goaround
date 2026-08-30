import SwiftUI
@preconcurrency import WebKit

struct WebViewContainer: UIViewRepresentable {
    let urlString: String
    let openInApp: Bool
    let hideXBottomMenu: Bool
    let resetAllWebViewsTrigger: Int
    let index: Int
    @Binding var currentWebViewIndex: Int
    let totalWebViews: Int // WebViewの総数
    
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        
        // 動画・音声の自動再生をオフにする設定
        configuration.mediaTypesRequiringUserActionForPlayback = [.video, .audio]
        // インライン再生を許可する設定を追加
        configuration.allowsInlineMediaPlayback = true
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.xBottomMenuScript(initiallyHidden: hideXBottomMenu),
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )
        
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
        context.coordinator.attach(webView: webView)
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.index = index
        context.coordinator.setXBottomMenuHidden(hideXBottomMenu, in: uiView)

        if context.coordinator.lastResetAllWebViewsTrigger != resetAllWebViewsTrigger {
            context.coordinator.lastResetAllWebViewsTrigger = resetAllWebViewsTrigger
            loadURL(uiView, coordinator: context.coordinator)

            return
        }

        if context.coordinator.loadedURL != targetURL {
            loadURL(uiView, coordinator: context.coordinator)
        } else if uiView.url == nil {
            loadURL(uiView, coordinator: context.coordinator)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    private var targetURL: URL? {
        var trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { return nil }

        if URLComponents(string: trimmedURL)?.scheme == nil {
            trimmedURL = "https://\(trimmedURL)"
        }

        guard let url = URL(string: trimmedURL),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return nil
        }

        return url
    }

    private func loadURL(_ webView: WKWebView, coordinator: Coordinator) {
        guard let targetURL else {
            coordinator.loadedURL = nil
            webView.stopLoading()
            webView.loadHTMLString("", baseURL: nil)
            return
        }

        coordinator.loadedURL = targetURL
        webView.load(URLRequest(url: targetURL))
    }

    private static func xBottomMenuScript(initiallyHidden: Bool) -> String {
        let initialValue = initiallyHidden ? "true" : "false"

        return """
        (() => {
            const apiName = "__goaroundSetXBottomMenuHidden";
            const marker = "data-goaround-hidden-x-bottom-menu";
            const styleID = "goaround-x-bottom-menu-style";
            let enabled = \(initialValue);
            let framePending = false;

            if (typeof window[apiName] === "function") {
                window[apiName](enabled);
                return;
            }

            const isX = () => location.hostname === "x.com" || location.hostname.endsWith(".x.com");

            const ensureStyle = () => {
                if (document.getElementById(styleID)) return;
                const style = document.createElement("style");
                style.id = styleID;
                style.textContent = `[${marker}] { display: none !important; }`;
                (document.head || document.documentElement).appendChild(style);
            };

            const restore = () => {
                document.querySelectorAll(`[${marker}]`).forEach(element => {
                    element.removeAttribute(marker);
                });
            };

            const hideBottomNavigation = () => {
                if (!enabled || !isX()) {
                    restore();
                    return;
                }

                ensureStyle();
                document.querySelectorAll('a[data-testid^="AppTabBar_"]').forEach(link => {
                    const navigation = link.closest("nav");
                    if (!navigation) return;

                    const navigationRect = navigation.getBoundingClientRect();
                    const isNearBottom = navigationRect.top > window.innerHeight * 0.45
                        && navigationRect.bottom >= window.innerHeight - 120;
                    if (!isNearBottom) return;

                    navigation.setAttribute(marker, "");

                    let ancestor = navigation.parentElement;
                    while (ancestor && ancestor !== document.body) {
                        const rect = ancestor.getBoundingClientRect();
                        const position = getComputedStyle(ancestor).position;
                        if (position === "fixed"
                            && rect.bottom >= window.innerHeight - 10
                            && rect.height <= 200) {
                            ancestor.setAttribute(marker, "");
                            break;
                        }
                        ancestor = ancestor.parentElement;
                    }
                });
            };

            const scheduleUpdate = () => {
                if (framePending) return;
                framePending = true;
                requestAnimationFrame(() => {
                    framePending = false;
                    hideBottomNavigation();
                });
            };

            window[apiName] = value => {
                enabled = Boolean(value);
                hideBottomNavigation();
            };

            new MutationObserver(scheduleUpdate).observe(document.documentElement, {
                childList: true,
                subtree: true
            });
            window.addEventListener("resize", scheduleUpdate, { passive: true });
            hideBottomNavigation();
        })();
        """
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: WebViewContainer
        var index: Int
        var loadedURL: URL?
        weak var webView: WKWebView?
        var observers: [NSObjectProtocol] = []
        var lastResetAllWebViewsTrigger: Int

        init(_ parent: WebViewContainer) {
            self.parent = parent
            self.index = parent.index
            self.lastResetAllWebViewsTrigger = parent.resetAllWebViewsTrigger
        }

        func attach(webView: WKWebView) {
            self.webView = webView

            guard observers.isEmpty else { return }

            let backObs = NotificationCenter.default.addObserver(forName: .goBackInWebView, object: nil, queue: .main) { [weak self] notification in
                guard let self = self, let webView = self.webView else { return }

                guard self.receives(notification: notification) else { return }

                if webView.canGoBack {
                    webView.goBack()
                }
            }
            observers.append(backObs)

        }

        deinit {
            for obs in observers {
                NotificationCenter.default.removeObserver(obs)
            }
        }

        private func receives(notification: Notification) -> Bool {
            guard let notifiedIndex = notification.userInfo?["index"] as? Int else { return false }
            return notifiedIndex == index
        }

        func setXBottomMenuHidden(_ hidden: Bool, in webView: WKWebView) {
            let value = hidden ? "true" : "false"
            webView.evaluateJavaScript("window.__goaroundSetXBottomMenuHidden?.(\(value));")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            setXBottomMenuHidden(parent.hideXBottomMenu, in: webView)
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
                if let url = navigationAction.request.url, !parent.openInApp {
                    UIApplication.shared.open(url)
                } else {
                    webView.load(navigationAction.request)
                }
            }
            return nil
        }

        func webViewDidClose(_ webView: WKWebView) {
            // 必要に応じてUIを更新
        }
    }
}
