//
//  PDFViewer.swift
//  Srishty
//
//  Created by Balaji on 2025-11-14.
//

import SwiftUI
import PDFKit

struct PDFViewer: View {
    let url: URL
    @Environment(\.presentationMode) var presentationMode

    @State private var localURL: URL? = nil
    @State private var loading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var progress: Double = 0.0

    var body: some View {
        NavigationView {
            Group {
                if loading {
                    VStack {
                        ProgressView(value: progress)
                            .progressViewStyle(LinearProgressViewStyle())
                            .padding()
                        Text("Downloading PDF...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else if let local = localURL {
                    PDFKitView(url: local)
                        .edgesIgnoringSafeArea(.all)
                } else if let err = errorMessage {
                    VStack {
                        Text("Unable to open PDF")
                            .font(.headline)
                        Text(err)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }.padding()
                } else {
                    Text("Preparing PDF...")
                }
            }
            .navigationBarTitle(Text(url.lastPathComponent), displayMode: .inline)
            .navigationBarItems(trailing:
                Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
            .onAppear {
                loadIfNeeded()
            }
        }
    }

    private func loadIfNeeded() {
        if url.isFileURL {
            localURL = url
            return
        }

        if let cached = cachedTempURL(for: url) {
            localURL = cached
            return
        }

        downloadRemotePDF(from: url)
    }

    private func cachedTempURL(for remote: URL) -> URL? {
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let name = "srishty_cached_\(remote.lastPathComponent)"
        let maybe = tmpDir.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: maybe.path) ? maybe : nil
    }

    private func downloadRemotePDF(from remote: URL) {
        loading = true
        progress = 0.0
        errorMessage = nil

        let req = URLRequest(url: remote, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        let task = URLSession.shared.downloadTask(with: req) { tempURL, resp, err in
            DispatchQueue.main.async {
                self.loading = false
                if let err = err {
                    self.errorMessage = err.localizedDescription
                    return
                }
                guard let tempURL = tempURL else {
                    self.errorMessage = "No data downloaded."
                    return
                }
                do {
                    let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
                    let dest = tmpDir.appendingPathComponent("srishty_cached_\(remote.lastPathComponent)")
                    if FileManager.default.fileExists(atPath: dest.path) {
                        try FileManager.default.removeItem(at: dest)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: dest)
                    self.localURL = dest
                } catch {
                    self.errorMessage = error.localizedDescription
                }
            }
        }

        let observation = task.progress.observe(\.fractionCompleted) { prog, _ in
            DispatchQueue.main.async { self.progress = prog.fractionCompleted }
        }

        task.resume()
        // observation will live until task finishes
    }
}

struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.usePageViewController(true, withViewOptions: nil)
        pdfView.backgroundColor = .systemBackground
        if let doc = PDFDocument(url: url) {
            pdfView.document = doc
        } else if let data = try? Data(contentsOf: url), let doc = PDFDocument(data: data) {
            pdfView.document = doc
        }
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}
