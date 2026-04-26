import SwiftUI
import FigBridgeCore

struct GeneratePage: View {
    @ObservedObject var viewModel: GenerateViewModel
    @FocusState private var focusedRenamingItemID: UUID?

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                Text("工作台")
                    .font(.title2.bold())
                HStack(alignment: .center, spacing: 8) {
                    Picker("Agent", selection: $viewModel.selectedAgentID) {
                        Text("未选择").tag(String?.none)
                        ForEach(viewModel.availableAgents) { agent in
                            Text(agent.provider.displayName).tag(String?.some(agent.id))
                        }
                    }
                    Button {
                        Task {
                            await viewModel.refreshAgents()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if viewModel.isRefreshingAgents {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(viewModel.isRefreshingAgents ? "刷新中..." : "刷新")
                        }
                    }
                    .disabled(viewModel.isRefreshingAgents)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Prompt")
                            .font(.headline)
                        Spacer()
                        Button("同步默认 Prompt") {
                            viewModel.syncPromptFromSettings()
                        }
                        .padding(.trailing, 6)
                    }
                    TextEditor(text: $viewModel.promptTemplate)
                        .font(.body.monospaced())
                        .frame(minHeight: 140)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("输出目录")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(viewModel.outputDirectoryPath)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                Picker("模式", selection: $viewModel.mode) {
                    Text("逐个").tag(GenerationMode.sequential)
                    Text("并发").tag(GenerationMode.parallel)
                }
                Picker("调用策略", selection: $viewModel.callStrategy) {
                    Text(AgentCallStrategy.singlePerLink.displayName).tag(AgentCallStrategy.singlePerLink)
                    Text(AgentCallStrategy.singleForBatch.displayName).tag(AgentCallStrategy.singleForBatch)
                }
                Stepper("并发数 \(viewModel.parallelism)", value: $viewModel.parallelism, in: 1...8)
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $viewModel.inputText)
                        .font(.body.monospaced())
                        .frame(minHeight: 240)
                    if viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("请输入要添加的信息")
                            .font(.body.monospaced())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
                HStack {
                    Button("添加") {
                        viewModel.addInput()
                    }
                    Button("新建批次") {
                        viewModel.startNewBatch()
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
                    ProgressView(value: Double(viewModel.completedCount), total: Double(max(viewModel.pendingItems.count, 1)))
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .frame(minWidth: 360)

            VStack(alignment: .leading, spacing: 12) {
                itemSection(title: "待处理链接", items: viewModel.pendingItems, showsGeneratedState: false)
                itemSection(title: "已处理链接", items: viewModel.processedItems, showsGeneratedState: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .frame(minWidth: 320)
            .onSubmit {
                if viewModel.renamingItemID != nil {
                    viewModel.commitRename()
                }
            }
            .onChange(of: viewModel.renamingItemID) { _, newValue in
                focusedRenamingItemID = newValue
            }

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
                    Text("资源状态: \(viewModel.selectedItemResourceStatusText)")
                        .foregroundStyle(viewModel.shouldHighlightSelectedItemResourceStatus ? .red : .primary)
                    Text("生成状态: \(viewModel.selectedItemGenerationStatusText)")
                        .foregroundStyle(viewModel.shouldHighlightSelectedItemGenerationStatus ? .red : .primary)
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
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("运行过程")
                            .font(.headline)
                        if let runLog = viewModel.selectedRunLog {
                            if runLog.isShared {
                                Text("批量单次调用共享日志")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text("状态: \(runLog.status.rawValue)")
                                .font(.caption)
                            if let executablePath = runLog.executablePath {
                                Text("执行文件: \(executablePath)")
                                    .font(.caption2)
                                    .textSelection(.enabled)
                            }
                            if !runLog.arguments.isEmpty {
                                Text("参数: \(runLog.arguments.joined(separator: " "))")
                                    .font(.caption2)
                                    .textSelection(.enabled)
                            }
                            if let exitCode = runLog.exitCode {
                                Text("退出码: \(exitCode)")
                                    .font(.caption2)
                            }
                            ScrollView {
                                Text(runLog.combinedConsoleText.isEmpty ? "暂无日志输出" : runLog.combinedConsoleText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .font(.body.monospaced())
                                    .textSelection(.enabled)
                            }
                            .frame(minHeight: 120, maxHeight: 220)
                        } else {
                            Text("暂无运行日志")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let yamlPath = item.generatedYAMLPath {
                        Text("YAML: \(yamlPath)")
                            .font(.caption)
                            .textSelection(.enabled)
                        if let yamlText = viewModel.selectedYAMLText {
                            ScrollView {
                                Text(yamlText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .font(.body.monospaced())
                                    .textSelection(.enabled)
                            }
                            .frame(minHeight: 120, maxHeight: 220)
                        } else {
                            Text("未找到 YAML")
                                .foregroundStyle(.secondary)
                        }
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .frame(minWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
    }

    @ViewBuilder
    private func itemSection(title: String, items: [FigmaLinkItem], showsGeneratedState: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(title) (\(items.count))")
                    .font(.title3.bold())
                Spacer()
            }
            List(items, selection: $viewModel.selectedItemID) { item in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        if viewModel.renamingItemID == item.id {
                            HStack(spacing: 8) {
                                TextField("", text: $viewModel.renamingTitle)
                                    .textFieldStyle(.roundedBorder)
                                    .focused($focusedRenamingItemID, equals: item.id)
                                    .onChange(of: focusedRenamingItemID) { _, newValue in
                                        if viewModel.renamingItemID == item.id, newValue != item.id {
                                            viewModel.finishRenameOnBlur()
                                        }
                                    }
                                Button("取消编辑") {
                                    viewModel.cancelRename()
                                }
                                .buttonStyle(.borderless)
                            }
                        } else {
                            Text(item.title ?? item.nodeName ?? item.nodeId)
                                .font(.headline)
                        }
                        Text("\(item.fileKey) / \(item.nodeId)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(item.generationStatus.rawValue)
                            .font(.caption)
                        Text("资源: \(viewModel.canRefreshResources(for: item) && item.resourceStatus != .failed ? "token 未设置" : item.resourceStatus.rawValue)")
                            .font(.caption2)
                            .foregroundStyle(viewModel.canRefreshResources(for: item) ? .red : .secondary)
                        if viewModel.canRefreshResources(for: item) {
                            if let errorMessage = item.errorMessage, !errorMessage.isEmpty {
                                Text(errorMessage)
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                                    .lineLimit(2)
                            }
                        }
                        if showsGeneratedState {
                            Text("YAML 已生成")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if let logSummary = item.logSummary {
                            Text(logSummary)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        if viewModel.canRefreshResources(for: item) {
                            itemActionButton(
                                "刷新",
                                systemImage: "arrow.clockwise",
                                role: .none
                            ) {
                                viewModel.reloadResources(for: item.id)
                            }
                        }
                        itemActionButton(
                            "删除",
                            systemImage: "trash",
                            role: .destructive
                        ) {
                            viewModel.deleteItem(id: item.id)
                        }
                    }
                }
                .tag(item.id)
            }
            .onKeyPress(.return) {
                guard viewModel.renamingItemID == nil,
                      viewModel.selectedItemID != nil else {
                    return .ignored
                }
                viewModel.beginRenamingSelectedItem()
                return .handled
            }
            .onKeyPress(.escape) {
                guard viewModel.renamingItemID != nil else {
                    return .ignored
                }
                viewModel.cancelRename()
                return .handled
            }
        }
    }

    @ViewBuilder
    private func itemActionButton(
        _ title: String,
        systemImage: String,
        role: ButtonRole?,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.bold())
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(minWidth: 72)
        }
        .buttonStyle(.plain)
        .foregroundStyle(role == .destructive ? .red : .primary)
        .background(
            role == .destructive
            ? Color.red.opacity(0.10)
            : Color.secondary.opacity(0.10),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .stroke(
                    role == .destructive
                    ? Color.red.opacity(0.22)
                    : Color.secondary.opacity(0.18),
                    lineWidth: 1
                )
        }
    }
}
