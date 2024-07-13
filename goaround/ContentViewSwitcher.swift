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
        if isSettingsCompleted {
            ContentView()
        } else {
            SettingsView()
        }
    }
}

struct ContentViewSwitcher_Previews: PreviewProvider {
    static var previews: some View {
        ContentViewSwitcher()
    }
}
