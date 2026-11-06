import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var selection: Tab = .models

    enum Tab: Hashable {
        case translation
        case models
        case settings
        case meetings
    }

    var body: some View {
        TabView(selection: $selection) {
            TranslationTabView()
                .tabItem { Label("翻译", systemImage: "character.bubble") }
                .tag(Tab.translation)

            ModelsView()
                .tabItem { Label("模型", systemImage: "square.stack.3d.up") }
                .tag(Tab.models)

            AppSettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
                .tag(Tab.settings)

            MeetingsView()
                .tabItem { Label("会议", systemImage: "waveform") }
                .tag(Tab.meetings)
        }
        .frame(minWidth: 880, minHeight: 580)
        .alert(
            "出错了",
            isPresented: Binding(
                get: { environment.lastError != nil },
                set: { if !$0 { environment.clearError() } }
            ),
            presenting: environment.lastError
        ) { _ in
            Button("好") { environment.clearError() }
        } message: { message in
            Text(message)
        }
    }
}
