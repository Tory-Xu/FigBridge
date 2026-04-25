import SwiftUI
import FigBridgeCore

struct GeneratePage: View {
    @ObservedObject var viewModel: GenerateViewModel

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                Text("工作台")
                    .font(.title2.bold())
                Picker("Agent", selection: $viewModel.selectedAgentID) {
                    Text("未选择").tag(String?.none)
                    ForEach(viewModel.availableAgents) { agent in
                        Text(agent.provider.displayName).tag(String?.some(agent.id))
                    }
                }
                TextEditor(text: $viewModel.promptTemplate)
                    .font(.body.monospaced())
                    .frame(minHeight: 140)
                HStack {
                    TextField("输出目录", text: $viewModel.outputDirectoryPath)
                    Button("选择") {
                        viewModel.chooseOutputDirectory()
                    }
                }
                Picker("模式", selection: $viewModel.mode) {
                    Text("逐个").tag(GenerationMode.sequential)
                    Text("并发").tag(GenerationMode.parallel)
                }
                Stepper("并发数 \(viewModel.parallelism)", value: $viewModel.parallelism, in: 1...8)
                TextEditor(text: $viewModel.inputText)
                    .font(.body.monospaced())
                    .frame(minHeight: 240)
                HStack {
                    Button("添加") {
                        viewModel.addInput()
                    }
                    Button("重置") {
                        viewModel.resetWorkspace()
                    }
                    Button("生成") {
                        Task {
                            await viewModel.generate()
                        }
                    }
                    .disabled(!viewModel.canGenerate)
                    if viewModel.isGenerating {
                        Button("取消") {
                            viewModel.cancelGeneration()
                        }
                    }
                }
                if viewModel.isGenerating {
                    ProgressView(value: Double(viewModel.completedCount), total: Double(max(viewModel.items.count, 1)))
                    Text(viewModel.progressText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !viewModel.validationMessage.isEmpty {
                    Text(viewModel.validationMessage)
                        .foregroundStyle(.red)
                }
                Spacer()
            }
            .frame(minWidth: 360)

            VStack(alignment: .leading, spacing: 12) {
                Text("待处理链接")
                    .font(.title3.bold())
                List(selection: $viewModel.selectedItemID) {
                    ForEach(viewModel.items) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title ?? item.nodeName ?? item.nodeId)
                                .font(.headline)
                            Text("\(item.fileKey) / \(item.nodeId)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(item.generationStatus.rawValue)
                                .font(.caption)
                            if let logSummary = item.logSummary {
                                Text(logSummary)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(item.id)
                    }
                }
            }
            .frame(minWidth: 320)

            VStack(alignment: .leading, spacing: 12) {
                Text("详情")
                    .font(.title3.bold())
                if let item = viewModel.selectedItem {
                    Text(item.nodeName ?? item.title ?? item.nodeId)
                        .font(.headline)
                    Text(item.url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("预览状态: \(item.previewStatus.rawValue)")
                    Text("资源状态: \(item.resourceStatus.rawValue)")
                    Text("生成状态: \(item.generationStatus.rawValue)")
                    if let previewImagePath = item.previewImagePath,
                       let image = NSImage(contentsOfFile: previewImagePath) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    if let errorMessage = item.errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                    if let yamlPath = item.generatedYAMLPath {
                        Text("YAML: \(yamlPath)")
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                    if !item.resourceItems.isEmpty {
                        List(item.resourceItems) { resource in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(resource.name)
                                    Text(resource.format.rawValue.uppercased())
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("导出") {
                                    viewModel.exportResource(resource)
                                }
                            }
                        }
                        HStack {
                            if item.previewImagePath != nil {
                                Button("导出预览图") {
                                    viewModel.exportPreviewImage()
                                }
                            }
                            Button("导出全部资源") {
                                viewModel.exportAllResources()
                            }
                        }
                    } else {
                        Spacer()
                    }
                } else {
                    ContentUnavailableView("未选择条目", systemImage: "sidebar.right")
                }
            }
            .frame(minWidth: 360)
        }
        .overlay(alignment: .bottomTrailing) {
            if !viewModel.exportMessage.isEmpty {
                Text(viewModel.exportMessage)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding()
            }
        }
        .task {
            await viewModel.bootstrap()
        }
        .task(id: viewModel.selectedItemID) {
            await viewModel.loadSelectedItemPreviewIfNeeded()
        }
    }
}
