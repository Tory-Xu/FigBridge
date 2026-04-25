import SwiftUI
import FigBridgeCore

struct ViewerPage: View {
    @ObservedObject var viewModel: ViewerViewModel

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("批次")
                        .font(.title3.bold())
                    Spacer()
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            viewerActionButton("导入目录", systemImage: "folder.badge.plus") {
                                viewModel.importBatchDirectoryUsingPanel()
                            }
                            viewerActionButton("导入 Zip", systemImage: "shippingbox") {
                                viewModel.importBatchZipUsingPanel()
                            }
                            viewerActionButton("导出批次", systemImage: "square.and.arrow.up") {
                                viewModel.exportSelectedBatch()
                            }
                            viewerActionButton("打开目录", systemImage: "folder") {
                                viewModel.openSelectedBatchInFinder()
                            }
                            viewerActionButton("删除批次", systemImage: "trash") {
                                viewModel.deleteSelectedBatch()
                            }
                            viewerActionButton("重新扫描", systemImage: "arrow.clockwise") {
                                viewModel.reload()
                            }
                        }

                        Menu {
                            Button("导入目录", systemImage: "folder.badge.plus") {
                                viewModel.importBatchDirectoryUsingPanel()
                            }
                            Button("导入 Zip", systemImage: "shippingbox") {
                                viewModel.importBatchZipUsingPanel()
                            }
                            Button("导出批次", systemImage: "square.and.arrow.up") {
                                viewModel.exportSelectedBatch()
                            }
                            Button("打开目录", systemImage: "folder") {
                                viewModel.openSelectedBatchInFinder()
                            }
                            Button("删除批次", systemImage: "trash") {
                                viewModel.deleteSelectedBatch()
                            }
                            Divider()
                            Button("重新扫描", systemImage: "arrow.clockwise") {
                                viewModel.reload()
                            }
                        } label: {
                            Label("批次操作", systemImage: "ellipsis.circle")
                                .labelStyle(.titleAndIcon)
                        }
                        .menuStyle(.borderlessButton)
                    }
                }
                List(selection: $viewModel.selectedBatchID) {
                    ForEach(viewModel.batches, id: \.summary.id) { batch in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(batch.summary.id)
                            Text("\(batch.summary.agent.displayName) · \(batch.summary.items.count) 项")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(batch.summary.id)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .frame(minWidth: 280)

            VStack(alignment: .leading, spacing: 12) {
                if let batch = viewModel.selectedBatch {
                    Text("批次详情")
                        .font(.title3.bold())
                    Text("输出目录")
                        .font(.headline)
                    Text(batch.summary.outputDirectory)
                        .font(.caption)
                        .textSelection(.enabled)
                    Text("原始输入")
                        .font(.headline)
                    ScrollView {
                        Text(viewModel.selectedSourceInputText ?? batch.summary.sourceInputText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                    }
                    Text("Prompt")
                        .font(.headline)
                    ScrollView {
                        Text(batch.summary.promptSnapshot)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    Text("条目")
                        .font(.headline)
                    List(batch.summary.items, selection: $viewModel.selectedItemID) { item in
                        HStack {
                            Text(item.title ?? item.nodeName ?? item.nodeId)
                            Spacer()
                            if item.generatedYAMLPath != nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        .tag(item.id)
                    }
                    Button("Copy Prompt") {
                        viewModel.copyPrompt()
                    }
                    .disabled(!viewModel.canCopyPrompt)
                } else {
                    ContentUnavailableView("暂无批次", systemImage: "archivebox")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .frame(minWidth: 400)

            VStack(alignment: .leading, spacing: 12) {
                Text("条目详情")
                    .font(.title3.bold())
                if let item = viewModel.selectedItem {
                    Text(item.nodeName ?? item.title ?? item.nodeId)
                        .font(.headline)
                    Text("\(item.fileKey) / \(item.nodeId)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let previewImagePath = item.previewImagePath,
                       let image = NSImage(contentsOfFile: previewImagePath) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    if let yamlPath = item.generatedYAMLPath {
                        Text(yamlPath)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                    if !item.resourceItems.isEmpty {
                        Text("资源")
                            .font(.headline)
                        List(item.resourceItems) { resource in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(resource.name)
                                Text(resource.localPath ?? resource.remoteURL ?? "")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        .frame(minHeight: 120, maxHeight: 180)
                    }
                    if let yamlText = viewModel.selectedYAMLText {
                        ScrollView {
                            Text(yamlText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .font(.body.monospaced())
                                .textSelection(.enabled)
                        }
                    } else {
                        Text("未找到 YAML")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ContentUnavailableView("未选择条目", systemImage: "doc.text")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            viewModel.reload()
        }
        .overlay(alignment: .bottomTrailing) {
            if !viewModel.message.isEmpty {
                Text(viewModel.message)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding()
            }
        }
    }

    private func viewerActionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .help(title)
        }
        .buttonStyle(.bordered)
    }
}
