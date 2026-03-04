import SwiftUI

@main
struct AssistantApp: App {
    @StateObject private var session = ApplicationSession()

    var body: some Scene {
        WindowGroup {
            RootContainerView()
                .environmentObject(session.accountStore)
                .environmentObject(session.chatStore)
                .environmentObject(session.shellAgentService)
        }
        #if os(macOS)
        MenuBarExtra("Assistant", systemImage: "message.fill") {
            MenuBarContentView()
                .environmentObject(session.accountStore)
                .environmentObject(session.chatStore)
                .environmentObject(session.shellAgentService)
                .frame(width: 340, height: 420)
                .padding(.vertical)
        }
        .menuBarExtraStyle(.window)
        #endif
        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(session.accountStore)
                .environmentObject(session.chatStore)
                .environmentObject(session.shellAgentService)
        }
        #endif
    }
}
