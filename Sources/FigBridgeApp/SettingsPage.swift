import SwiftUI
import FigBridgeCore

struct SettingsPage: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            SecureField("Figma Token", text: $viewModel.settings.figmaToken)
            TextEditor(text: $viewModel.settings.promptTemplate)
                .font(.body.monospaced())
                .frame(minHeight: 160)
            TextField("默认输出目录", text: Binding(
                get: { viewModel.settings.outputDirectoryPath ?? "" },
                set: { viewModel.settings.outputDirectoryPath = $0.isEmpty ? nil : $0 }
            ))
            Button("选择默认输出目录") {
                viewModel.chooseDefaultOutputDirectory()
            }
            Picker("默认导出格式", selection: $viewModel.settings.defaultExportFormat) {
                Text("PNG").tag(ExportFormat.png)
                Text("SVG").tag(ExportFormat.svg)
            }
            Picker("默认生成模式", selection: $viewModel.settings.defaultGenerationMode) {
                Text("逐个").tag(GenerationMode.sequential)
                Text("并发").tag(GenerationMode.parallel)
            }
            Stepper("并发上限 \(viewModel.settings.parallelism)", value: $viewModel.settings.parallelism, in: 1...8)
            HStack {
                Button("刷新 Agent") {
                    Task {
                        await viewModel.refreshAgents()
                    }
                }
                Button("测试 Token") {
                    Task {
                        await viewModel.testToken()
                    }
                }
                Button("恢复默认 Prompt") {
                    viewModel.restoreDefaultPrompt()
                }
                Button("保存") {
                    viewModel.save()
                }
            }
            if !viewModel.message.isEmpty {
                Text(viewModel.message)
                    .foregroundStyle(viewModel.isError ? .red : .secondary)
            }
        }
        .formStyle(.grouped)
        .task {
            await viewModel.bootstrap()
        }
    }
}
