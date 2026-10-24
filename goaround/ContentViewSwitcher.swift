//
//  ContentViewSwitcher.swift
//  goaround
//
//  Created by Yuki Jin on 2024/07/13.
//

import SwiftUI

struct ContentViewSwitcher: View {
    @AppStorage("isSettingsCompleted") private var isSettingsCompleted: Bool = false

    var body: some View {
        TabView {
            Group {
                if isSettingsCompleted { ContentView() } else { SettingsView() }
            }
            .tabItem { Label("ページ", systemImage: "globe") }
            RSSView()
                .tabItem { Label("RSS", systemImage: "dot.radiowaves.left.and.right") }
        }
    }
}

struct ContentViewSwitcher_Previews: PreviewProvider {
    static var previews: some View {
        ContentViewSwitcher()
    }
}
