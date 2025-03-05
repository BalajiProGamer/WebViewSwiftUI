//
//  WebView.swift
//  Nexum
//
//  Created by Balaji Balamurugan on 3/5/25.
//

import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let request = URLRequest(url: url)
        webView.load(request)
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebView

        init(_ parent: WebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url {
                // If URL is a Google login page, open in Safari
                if url.absoluteString.contains("accounts.google.com") {
                    UIApplication.shared.open(url)
                    decisionHandler(.cancel) // Cancel loading in WebView
                    return
                }
            }
            decisionHandler(.allow) // Allow all other navigation
        }
    }
}
