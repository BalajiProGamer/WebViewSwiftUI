//
//  ContentView.swift
//  Nexum
//
//  Created by Balaji Balamurugan on 2/19/25.
//

import SwiftUI

struct ContentView: View {
    private let urlString: String = "https://bharathuniv.tech"

    var body: some View {
        WebView(url: URL(string: urlString)!)
            .edgesIgnoringSafeArea(.all) // Makes it fullscreen
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
