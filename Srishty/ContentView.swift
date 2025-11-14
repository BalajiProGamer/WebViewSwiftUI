//
// ContentView.swift
// Srishty
//
// Replaced  — compact top bar with Back button INSIDE it (small, true visible height).
//

import SwiftUI

struct ContentView: View {
    @StateObject private var store = WebViewStore()
    private let startURL = URL(string: "https://srishty.bharathuniv.ac.in")!

    @State private var showingPDF: Bool = false
    @State private var pdfURL: URL?

    // visible bar height (excluding safe top area). Make smaller/larger here.
    private let barHeight: CGFloat = 28

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {

                // 1) Reserve status area (system background) so black bar's visible size is correct
                Color(.systemBackground)
                    .frame(height: safeTopPadding())
                    .edgesIgnoringSafeArea(.top)

                // 2) Compact black bar with Back button INSIDE it (left)
                HStack(spacing: 8) {
                    Button(action: {
                        DispatchQueue.main.async {
                            if let web = store.webView, web.canGoBack {
                                web.goBack()
                            }
                        }
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            // keep small horizontal padding but fixed height so it's vertically centered
                            .padding(.horizontal, 10)
                            .frame(height: barHeight)
                    }
                    .disabled(!(store.webView?.canGoBack ?? false))
                    .opacity((store.webView?.canGoBack ?? false) ? 1.0 : 0.5)

                    Spacer()
                }
                .padding(.horizontal, 6)
                .frame(height: barHeight)
                .background(Color.black.opacity(0.88))
                .opacity(store.isBarHidden ? 0.0 : 1.0)
                .animation(.easeInOut(duration: 0.20), value: store.isBarHidden)
                // keep the bar inline (not overlapping web content) — web content starts below.

                // 3) thin progress indicator (optional)
                if store.isLoading {
                    ProgressView()
                        .progressViewStyle(LinearProgressViewStyle())
                        .frame(height: 2)
                } else {
                    Color.clear.frame(height: 2)
                }

                // 4) web view fills remaining area
                WebView(
                    url: startURL,
                    store: store,
                    onOpenPDF: { url in
                        self.pdfURL = url
                        self.showingPDF = true
                    },
                    startGoogleSignIn: { authURL, callback, completion in
                        ASWebAuthCoordinator.shared.startAuthentication(
                            authURL: authURL,
                            callbackScheme: callback
                        ) { cb, err in
                            completion(cb, err)
                        }
                    }
                )
                .edgesIgnoringSafeArea(.bottom)
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingPDF) {
                if let url = pdfURL { PDFViewer(url: url) } else { EmptyView() }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    // MARK: - Helpers
    private func safeTopPadding() -> CGFloat {
        // scene-aware safe top inset
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let active = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let window = active?.windows.first(where: { $0.isKeyWindow }) ?? active?.windows.first
        return window?.safeAreaInsets.top ?? 20
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
