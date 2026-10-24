//
//  goaroundApp.swift
//  goaround
//
//  Created by Yuki Jin on 2024/07/13.
//
import SwiftUI

@main
struct goaroundApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        WebSiteSettingsSync.shared.start()
        RSSStore.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentViewSwitcher()
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        WebSiteSettingsSync.shared.refresh()
                        RSSStore.shared.synchronize()
                    }
                }
        }
    }
}
