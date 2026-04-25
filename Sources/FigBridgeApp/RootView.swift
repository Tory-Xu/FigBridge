import SwiftUI

struct RootView: View {
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        TabView {
            GeneratePage(viewModel: container.generateViewModel)
                .tabItem {
                    Label("生成", systemImage: "wand.and.stars")
                }

            ViewerPage(viewModel: container.viewerViewModel)
                .tabItem {
                    Label("查看", systemImage: "doc.text.image")
                }

            SettingsPage(viewModel: container.settingsViewModel)
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
        }
        .padding(16)
    }
}
