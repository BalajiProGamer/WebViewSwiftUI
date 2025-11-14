//
//  ASWebAuthCoordinator.swift
//  Srishty
//
//  Created by Balaji on 2025-11-14.
//

import Foundation
import AuthenticationServices
import UIKit

final class ASWebAuthCoordinator: NSObject {
    static let shared = ASWebAuthCoordinator()

    private var session: ASWebAuthenticationSession?
    private var completionHandler: ((URL?, Error?) -> Void)?

    private override init() {
        super.init()
    }

    func startAuthentication(authURL: URL,
                             callbackScheme: String,
                             prefersEphemeralSession: Bool = false,
                             completion: @escaping (URL?, Error?) -> Void) {
        // Cancel previous if present
        if session != nil {
            session?.cancel()
            session = nil
            completionHandler?(nil, NSError(domain: "ASWebAuthCoordinator", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cancelled previous auth session."]))
            completionHandler = nil
        }

        completionHandler = completion

        session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: callbackScheme) { [weak self] callbackURL, error in
            defer {
                self?.session = nil
                self?.completionHandler = nil
            }
            completion(callbackURL, error)
        }

        session?.presentationContextProvider = self
        session?.prefersEphemeralWebBrowserSession = prefersEphemeralSession

        let started = session?.start() ?? false
        if !started {
            let err = NSError(domain: "ASWebAuthCoordinator", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to start ASWebAuthenticationSession."])
            completion(nil, err)
            session = nil
            completionHandler = nil
        }
    }

    func cancel() {
        session?.cancel()
        session = nil
        if let cb = completionHandler {
            cb(nil, NSError(domain: "ASWebAuthCoordinator", code: -3, userInfo: [NSLocalizedDescriptionKey: "Auth cancelled by app."]))
            completionHandler = nil
        }
    }
}

extension ASWebAuthCoordinator: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let preferredScene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        if let anchor = preferredScene?.windows.first(where: { $0.isKeyWindow }) {
            return anchor
        }
        if let fallback = scenes.first?.windows.first {
            return fallback
        }
        return ASPresentationAnchor()
    }
}
