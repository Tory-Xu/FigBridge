import SwiftUI
import FigBridgeCore

struct SettingsPage: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var tokenFieldVisible = false

    var body: some View {
        Form {
            Section("Figma Token") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 12) {
                        Group {
                            if tokenFieldVisible {
                                TextField("请输入 Figma Personal Access Token", text: $viewModel.settings.figmaToken)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                SecureField("请输入 Figma Personal Access Token", text: $viewModel.settings.figmaToken)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        .font(.body.monospaced())

                        Button(tokenFieldVisible ? "隐藏" : "显示") {
                            tokenFieldVisible.toggle()
                        }

                        Button {
                            Task {
                                await viewModel.testToken()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                if viewModel.isTestingToken {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Text(viewModel.isTestingToken ? "测试中..." : "测试 Token")
                            }
                        }
                        .disabled(viewModel.isTestingToken)

                        Button("说明") {
                            viewModel.isShowingTokenHelp = true
                        }
                    }
                    Text("用于读取节点预览和资源，建议使用拥有只读权限的 Personal Access Token。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("默认 Prompt")
                            .font(.headline)
                        Spacer()
                        Button("恢复默认 Prompt") {
                            viewModel.restoreDefaultPrompt()
                        }
                    }
                    TextEditor(text: $viewModel.settings.promptTemplate)
                        .font(.body.monospaced())
                        .frame(minHeight: 160)
                }
            }

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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .formStyle(.grouped)
        .task {
            await viewModel.bootstrap()
        }
        .sheet(isPresented: $viewModel.isShowingTokenHelp) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Figma Token 获取方式")
                        .font(.title3.bold())
                    Spacer()
                    Button("关闭") {
                        viewModel.isShowingTokenHelp = false
                    }
                }
                ForEach(Array(SettingsViewModel.tokenHelpSteps.enumerated()), id: \.offset) { index, step in
                    Text("\(index + 1). \(step)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Link("打开官方说明", destination: SettingsViewModel.tokenHelpURL)
                Spacer()
            }
            .padding(24)
            .frame(minWidth: 420, minHeight: 240, alignment: .topLeading)
        }
        .overlay(alignment: .bottomTrailing) {
            if !viewModel.toastMessage.isEmpty {
                Text(viewModel.toastMessage)
                    .foregroundStyle(viewModel.isToastError ? .red : .primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding()
            }
        }
    }
}
