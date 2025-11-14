//
//  WebViewStore.swift
//  Srishty
//
//  Created by Balaji on 2025-11-14.
//

import Foundation
import Combine
import WebKit

final class WebViewStore: ObservableObject {
    weak var webView: WKWebView?

    // UI state
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var currentURL: URL?
    @Published var isLoading: Bool = false

    // download progress (0.0 - 1.0)
    @Published var downloadProgress: Double = 0.0

    // whether the top bar should be hidden (auto-hide on scroll)
    @Published var isBarHidden: Bool = false

    // refresh control state (pull-to-refresh)
    @Published var isRefreshing: Bool = false

    // Download handler (WebView coordinator will set)
    var startDownloadHandler: ((_ url: URL) -> Void)?

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() { webView?.reload() }
    func downloadCurrent() { if let url = currentURL { startDownloadHandler?(url) } }
}
