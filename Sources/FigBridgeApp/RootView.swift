import SwiftUI

struct RootView: View {
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        TabView(selection: $container.selectedTab) {
            GeneratePage(viewModel: container.generateViewModel)
                .tag(AppTab.generate)
                .tabItem {
                    Label("生成", systemImage: "wand.and.stars")
                }

            ViewerPage(viewModel: container.viewerViewModel)
                .tag(AppTab.viewer)
                .tabItem {
                    Label("查看", systemImage: "doc.text.image")
                }

            SettingsPage(viewModel: container.settingsViewModel)
                .tag(AppTab.settings)
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
    }
}
