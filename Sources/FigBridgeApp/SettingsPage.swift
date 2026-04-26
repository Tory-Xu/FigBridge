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
            Picker("默认导出格式", selection: $viewModel.settings.defaultExportFormat) {
                Text("PNG").tag(ExportFormat.png)
                Text("SVG").tag(ExportFormat.svg)
            }
            Picker("默认生成模式", selection: $viewModel.settings.defaultGenerationMode) {
                Text("逐个").tag(GenerationMode.sequential)
                Text("并发").tag(GenerationMode.parallel)
            }
            Picker("默认调用策略", selection: $viewModel.settings.defaultAgentCallStrategy) {
                Text(AgentCallStrategy.singlePerLink.displayName).tag(AgentCallStrategy.singlePerLink)
                Text(AgentCallStrategy.singleForBatch.displayName).tag(AgentCallStrategy.singleForBatch)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .formStyle(.grouped)
        .task {
            await viewModel.bootstrap()
        }
    }
}
