//
//  IntentProvider.swift
//  Hamster
//
//  Created by morse on 2023/9/25.
//

import AppIntents

@available(iOS 16.0, *)
struct IntentProvider: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    return [
      AppShortcut(intent: RimeSyncIntent(), phrases: ["RIME Sync in \(.applicationName)", "用\(.applicationName)同步 RIME"]),
      AppShortcut(intent: RimeDeployIntent(), phrases: ["RIME Deploy in \(.applicationName)", "用\(.applicationName)重新部署 RIME"]),
    ]
  }
}
