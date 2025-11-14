//
//  WebView.swift
//  Srishty
//
//  Created by Balaji on 2025-11-14.
//  Updated: adds pull-to-refresh and auto-hide-on-scroll support.
//

import SwiftUI
import WebKit
import UniformTypeIdentifiers
import PhotosUI
import AuthenticationServices
import PDFKit
import UIKit

struct WebView: UIViewRepresentable {
    let url: URL
    @ObservedObject var store: WebViewStore

    var onOpenPDF: ((URL) -> Void)? = nil
    var startGoogleSignIn: ((_ authURL: URL, _ callbackScheme: String, _ completion: @escaping (URL?, Error?) -> Void) -> Void)? = nil

    func makeUIView(context: Context) -> WKWebView {
        let webpagePrefs = WKWebpagePreferences()
        webpagePrefs.allowsContentJavaScript = true

        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences = webpagePrefs
        config.allowsInlineMediaPlayback = true

        let userController = WKUserContentController()
        let js = """
        (function() {
            var meta = document.querySelector('meta[name=viewport]');
            if (!meta) {
                meta = document.createElement('meta');
                meta.setAttribute('name','viewport');
                document.getElementsByTagName('head')[0].appendChild(meta);
            }
            meta.setAttribute('content','width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no');

            function attachFileInterceptors() {
                document.querySelectorAll('input[type=file]').forEach(function(el) {
                    if (el._srishty_hook_attached) return;
                    el._srishty_hook_attached = true;
                    el.addEventListener('click', function(e) {
                        try {
                            var info = { accept: el.accept || '', multiple: el.multiple || false, capture: el.capture || '' };
                            window.webkit.messageHandlers.srishtyFilePicker.postMessage(info);
                            e.preventDefault();
                            e.stopPropagation();
                        } catch (err) {}
                    }, true);
                });
            }

            attachFileInterceptors();
            var obs = new MutationObserver(function() { attachFileInterceptors(); });
            obs.observe(document.documentElement || document.body, { childList: true, subtree: true });
        })();
        """
        let script = WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        userController.addUserScript(script)
        userController.add(context.coordinator, name: "srishtyFilePicker")

        config.userContentController = userController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.bounces = true

        // Attach refresh control
        if context.coordinator.refreshControl == nil {
            let rc = UIRefreshControl()
            rc.addTarget(context.coordinator, action: #selector(Coordinator.handleRefreshControl(_:)), for: .valueChanged)
            context.coordinator.refreshControl = rc
        }
        webView.scrollView.refreshControl = context.coordinator.refreshControl

        // set scroll delegate for auto-hide
        webView.scrollView.delegate = context.coordinator

        // wire coordinator / store
        context.coordinator.parent = self
        context.coordinator.currentWebView = webView
        context.coordinator.store = store

        store.webView = webView
        store.startDownloadHandler = { url in context.coordinator.startDownload(from: url) }

        // load request
        webView.load(URLRequest(url: url))

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // no-op
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject,
                             WKNavigationDelegate,
                             WKUIDelegate,
                             WKScriptMessageHandler,
                             UIDocumentPickerDelegate,
                             UIImagePickerControllerDelegate,
                             UINavigationControllerDelegate,
                             PHPickerViewControllerDelegate,
                             URLSessionDownloadDelegate,
                             UIScrollViewDelegate {

        var parent: WebView?
        weak var currentWebView: WKWebView?
        weak var store: WebViewStore?

        // refresh control for pull-to-refresh
        var refreshControl: UIRefreshControl?

        // used for scroll detection
        private var lastContentOffsetY: CGFloat = 0
        private var hideWorkItem: DispatchWorkItem?

        // file pickers
        private var fileUploadCompletion: (([URL]?) -> Void)?
        private var imagePicker: UIImagePickerController?
        private var photoPicker: PHPickerViewController?

        // downloads
        private var downloadSession: URLSession?
        private var activeDownloadTask: URLSessionDownloadTask?

        override init() {
            super.init()
            let cfg = URLSessionConfiguration.default
            downloadSession = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
        }

        // MARK: - Refresh control handler
        @objc func handleRefreshControl(_ sender: UIRefreshControl) {
            guard let web = currentWebView else {
                sender.endRefreshing()
                return
            }
            // indicate refreshing in store
            DispatchQueue.main.async { self.store?.isRefreshing = true }

            // reload
            web.reload()
            // will end refreshing in didFinish/didFail delegate
        }

        // MARK: - UIScrollViewDelegate (auto-hide-on-scroll)
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let currentY = scrollView.contentOffset.y
            let dy = currentY - lastContentOffsetY

            // small threshold to avoid jitter
            let threshold: CGFloat = 6.0

            if dy > threshold {
                // scrolled down -> hide bar
                setBarHidden(true)
            } else if dy < -threshold {
                // scrolled up -> show bar
                setBarHidden(false)
            }
            lastContentOffsetY = currentY
        }

        private func setBarHidden(_ hidden: Bool) {
            // Debounce rapid toggles slightly
            hideWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        self?.store?.isBarHidden = hidden
                    }
                }
            }
            hideWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: item)
        }

        // MARK: - WKNavigationDelegate (update store & end refresh)
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.store?.isLoading = true
                self.store?.currentURL = webView.url
                self.store?.canGoBack = webView.canGoBack
                self.store?.canGoForward = webView.canGoForward
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.store?.isLoading = false
                self.store?.currentURL = webView.url
                self.store?.canGoBack = webView.canGoBack
                self.store?.canGoForward = webView.canGoForward

                // End refresh control if active
                if let rc = self.refreshControl, rc.isRefreshing {
                    rc.endRefreshing()
                    self.store?.isRefreshing = false
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.store?.isLoading = false
                if let rc = self.refreshControl, rc.isRefreshing {
                    rc.endRefreshing()
                    self.store?.isRefreshing = false
                }
            }
        }

        // other existing navigation/JS/file-upload/download methods follow...
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {

            guard let url = navigationAction.request.url else { decisionHandler(.allow); return }
            let absolute = url.absoluteString.lowercased()

            // PDF detection
            if url.pathExtension.lowercased() == "pdf" {
                DispatchQueue.main.async { self.parent?.onOpenPDF?(url) }
                decisionHandler(.cancel); return
            }

            // Google sign-in heuristics -> ASWebAuth
            if absolute.contains("accounts.google.com") || absolute.contains("/oauth2/") ||
                (absolute.contains("signin") && absolute.contains("google")) {

                if let start = parent?.startGoogleSignIn {
                    let callbackScheme = Bundle.main.bundleIdentifier.map { $0 + ".oauth" } ?? "srishty-oauth"
                    start(url, callbackScheme) { callbackURL, error in
                        if let cb = callbackURL {
                            DispatchQueue.main.async { webView.load(URLRequest(url: cb)) }
                        } else if let err = error { print("ASWebAuth error: \(err.localizedDescription)") }
                    }
                    decisionHandler(.cancel); return
                } else {
                    UIApplication.shared.open(url)
                    decisionHandler(.cancel); return
                }
            }

            decisionHandler(.allow)
        }

        // navigation response interception for downloads
        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {

            if let response = navigationResponse.response as? HTTPURLResponse,
               let url = response.url {

                if let contentDisposition = response.allHeaderFields["Content-Disposition"] as? String,
                   contentDisposition.lowercased().contains("attachment") {
                    decisionHandler(.cancel); startDownload(from: url); return
                }

                if let mime = response.mimeType?.lowercased() {
                    let downloadableTypes: Set<String> = [
                        "application/pdf", "application/zip", "application/octet-stream",
                        "application/msword",
                        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                        "application/vnd.ms-excel",
                        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                        "image/png", "image/jpeg"
                    ]
                    if downloadableTypes.contains(mime) {
                        if mime == "application/pdf" {
                            DispatchQueue.main.async { self.parent?.onOpenPDF?(url) }
                            decisionHandler(.cancel); return
                        } else {
                            decisionHandler(.cancel); startDownload(from: url); return
                        }
                    }
                }
            }
            decisionHandler(.allow)
        }

        // UIDelegate for iOS 18.4+ open panel
        @available(iOS 18.4, *)
        func webView(_ webView: WKWebView,
                     runOpenPanelWith parameters: WKOpenPanelParameters,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping ([URL]?) -> Void) {
            presentFileActionSheet(for: webView, allowsMultiple: parameters.allowsMultipleSelection, completion: completionHandler)
        }

        // JS fallback for file inputs
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "srishtyFilePicker" else { return }
            if let dict = message.body as? [String: Any] {
                let allowsMultiple = dict["multiple"] as? Bool ?? false
                presentFileActionSheet(for: nil, allowsMultiple: allowsMultiple) { [weak self] urls in
                    guard let self = self, let urls = urls else { return }
                    let urlStrings = urls.map { $0.absoluteString }
                    let js = "window.dispatchEvent(new CustomEvent('srishty:selectedFiles', {detail: \(self.jsonEncode(urlStrings))}));"
                    DispatchQueue.main.async { self.currentWebView?.evaluateJavaScript(js, completionHandler: nil) }
                }
            }
        }

        private func jsonEncode(_ arr: [String]) -> String {
            guard let data = try? JSONEncoder().encode(arr),
                  let s = String(data: data, encoding: .utf8) else { return "[]" }
            return s
        }

        // Present pickers (Camera / Photo / Files)
        private func presentFileActionSheet(for webView: WKWebView?, allowsMultiple: Bool, completion: @escaping ([URL]?) -> Void) {
            guard let top = Self.findTopViewController() else { completion(nil); return }
            let alert = UIAlertController(title: "Choose file", message: nil, preferredStyle: .actionSheet)

            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                alert.addAction(UIAlertAction(title: "Camera", style: .default, handler: { _ in self.presentCamera(on: top, completion: completion) }))
            }

            alert.addAction(UIAlertAction(title: "Photo Library", style: .default, handler: { _ in self.presentPhotoPicker(on: top, allowsMultiple: allowsMultiple, completion: completion) }))

            alert.addAction(UIAlertAction(title: "Files", style: .default, handler: { _ in self.presentDocumentPicker(on: top, allowsMultiple: allowsMultiple, completion: completion) }))

            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in completion(nil) }))

            alert.popoverPresentationController?.sourceView = top.view
            alert.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
            top.present(alert, animated: true, completion: nil)
        }

        private func presentCamera(on vc: UIViewController, completion: @escaping ([URL]?) -> Void) {
            DispatchQueue.main.async {
                let picker = UIImagePickerController()
                picker.delegate = self
                picker.sourceType = .camera
                picker.modalPresentationStyle = .fullScreen
                self.imagePicker = picker
                self.fileUploadCompletion = completion
                vc.present(picker, animated: true, completion: nil)
            }
        }

        private func presentPhotoPicker(on vc: UIViewController, allowsMultiple: Bool, completion: @escaping ([URL]?) -> Void) {
            var config = PHPickerConfiguration(photoLibrary: PHPhotoLibrary.shared())
            config.selectionLimit = allowsMultiple ? 0 : 1
            config.filter = .any(of: [.images, .videos])
            let picker = PHPickerViewController(configuration: config)
            picker.delegate = self
            picker.modalPresentationStyle = .popover
            self.photoPicker = picker
            self.fileUploadCompletion = completion
            vc.present(picker, animated: true, completion: nil)
        }

        private func presentDocumentPicker(on vc: UIViewController, allowsMultiple: Bool, completion: @escaping ([URL]?) -> Void) {
            let docPicker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.item], asCopy: true)
            docPicker.delegate = self
            docPicker.allowsMultipleSelection = allowsMultiple
            self.fileUploadCompletion = completion
            vc.present(docPicker, animated: true, completion: nil)
        }

        // UIImagePickerControllerDelegate
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true) {
                self.fileUploadCompletion?(nil)
                self.fileUploadCompletion = nil
                self.imagePicker = nil
            }
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            picker.dismiss(animated: true) {
                guard let image = info[.originalImage] as? UIImage else {
                    self.fileUploadCompletion?(nil)
                    self.fileUploadCompletion = nil
                    self.imagePicker = nil
                    return
                }
                if let url = self.saveImageToTempFile(image: image) {
                    self.fileUploadCompletion?([url])
                } else {
                    self.fileUploadCompletion?(nil)
                }
                self.fileUploadCompletion = nil
                self.imagePicker = nil
            }
        }

        private func saveImageToTempFile(image: UIImage) -> URL? {
            guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
            let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            let filename = "srishty_img_\(UUID().uuidString).jpg"
            let fileURL = tmpDir.appendingPathComponent(filename)
            do {
                try data.write(to: fileURL)
                return fileURL
            } catch {
                print("Failed to write image: \(error)")
                return nil
            }
        }

        // PHPicker delegate
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true) {
                guard !results.isEmpty else {
                    self.fileUploadCompletion?(nil)
                    self.fileUploadCompletion = nil
                    self.photoPicker = nil
                    return
                }
                var urls: [URL] = []
                let group = DispatchGroup()

                for result in results {
                    group.enter()
                    if result.itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                        result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, error in
                            if let url = url { if let tmp = self.copyProviderURLToTemp(url: url) { urls.append(tmp) } }
                            group.leave()
                        }
                    } else {
                        result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.item.identifier) { url, error in
                            if let url = url { if let tmp = self.copyProviderURLToTemp(url: url) { urls.append(tmp) } }
                            group.leave()
                        }
                    }
                }

                group.notify(queue: .main) {
                    self.fileUploadCompletion?(urls.isEmpty ? nil : urls)
                    self.fileUploadCompletion = nil
                    self.photoPicker = nil
                }
            }
        }

        private func copyProviderURLToTemp(url: URL) -> URL? {
            let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            let dest = tmpDir.appendingPathComponent(url.lastPathComponent)
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: url, to: dest)
                return dest
            } catch {
                print("copy error: \(error)")
                return nil
            }
        }

        // Document picker
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            controller.dismiss(animated: true) {
                self.fileUploadCompletion?(urls)
                self.fileUploadCompletion = nil
            }
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            controller.dismiss(animated: true) {
                self.fileUploadCompletion?(nil)
                self.fileUploadCompletion = nil
            }
        }

        // Downloads
        func startDownload(from url: URL) {
            guard url.scheme == "http" || url.scheme == "https" else { return }
            DispatchQueue.main.async { self.store?.downloadProgress = 0.0 }
            let request = URLRequest(url: url)
            activeDownloadTask = downloadSession?.downloadTask(with: request)
            activeDownloadTask?.resume()
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            let suggested = downloadTask.response?.suggestedFilename ?? UUID().uuidString
            let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            let dest = tmpDir.appendingPathComponent(suggested)

            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.moveItem(at: location, to: dest)
                DispatchQueue.main.async {
                    self.store?.downloadProgress = 1.0
                    self.presentShareSheet(for: dest)
                }
            } catch {
                print("Download move error: \(error.localizedDescription)")
                DispatchQueue.main.async { self.store?.downloadProgress = 0.0 }
            }
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                        didWriteData bytesWritten: Int64,
                        totalBytesWritten: Int64,
                        totalBytesExpectedToWrite: Int64) {
            if totalBytesExpectedToWrite > 0 {
                let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
                DispatchQueue.main.async { self.store?.downloadProgress = progress }
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let err = error {
                print("Download error: \(err.localizedDescription)")
                DispatchQueue.main.async { self.store?.downloadProgress = 0.0 }
            }
        }

        private func presentShareSheet(for fileURL: URL) {
            guard let top = Self.findTopViewController() else { return }
            let vc = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
            vc.popoverPresentationController?.sourceView = top.view
            vc.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
            top.present(vc, animated: true, completion: nil)
        }

        // Utility: find top view controller (scene-safe)
        private static func findTopViewController() -> UIViewController? {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let active = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
            guard let window = active?.windows.first(where: { $0.isKeyWindow }) ?? active?.windows.first else { return nil }
            return findTop(window.rootViewController)
        }

        private static func findTop(_ root: UIViewController?) -> UIViewController? {
            guard let root = root else { return nil }
            if let presented = root.presentedViewController { return findTop(presented) }
            if let nav = root as? UINavigationController { return findTop(nav.visibleViewController) }
            if let tab = root as? UITabBarController { return findTop(tab.selectedViewController) }
            return root
        }
    } // Coordinator end
}
