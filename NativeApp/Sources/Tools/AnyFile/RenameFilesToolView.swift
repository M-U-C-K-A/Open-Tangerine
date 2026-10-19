import SwiftUI

@MainActor
struct RenameFilesToolView: View {
    let session: ToolSession
    @State private var options = BatchRename.Options()

    private var items: [BatchRename.Item] { BatchRename.plan(session.files, options: options) }

    var body: some View {
        let items = items
        let problems = BatchRename.problems(items)
        let changing = items.filter(\.changes).count
        FormShell(session: session,
                  saveTitle: changing == 1 ? "Rename 1 item" : "Rename \(changing) items",
                  saveEnabled: problems.isEmpty && changing > 0,
                  onSave: { rename(items) }) {
            FormRow(title: "Name") {
                TextField("{name}", text: $options.pattern)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
            }
            HStack(spacing: 8) {
                ForEach([("Name", "{name}"), ("Number", "{n}"), ("Date", "{date}")], id: \.1) { title, token in
                    Button("+ \(title)") { options.pattern += options.pattern.isEmpty || options.pattern.hasSuffix(" ") ? token : " \(token)" }
                        .controlSize(.small)
                }
                Spacer()
                Button("Reset") { options = BatchRename.Options() }
                    .controlSize(.small)
            }
            FormHint("{name} is the current name, {n} counts up, {date} is the day each file was last changed. Extensions are kept.")

            HStack(spacing: 16) {
                FormRow(title: "Find") {
                    TextField("text", text: $options.find).textFieldStyle(.roundedBorder).frame(width: 150)
                }
                FormRow(title: "Replace with") {
                    TextField("text", text: $options.replace).textFieldStyle(.roundedBorder).frame(width: 150)
                }
            }
            HStack(spacing: 16) {
                FormRow(title: "Start at") {
                    TextField("1", value: $options.start, format: .number).textFieldStyle(.roundedBorder).frame(width: 64)
                }
                FormRow(title: "Digits") {
                    Stepper(value: $options.digits, in: 1...6) { Text("\(options.digits)").monospacedDigit() }
                }
                FormRow(title: "Case") {
                    SegmentedPicker(selection: $options.textCase, options: BatchRename.TextCase.allCases.map { ($0, $0.title) })
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(spacing: 10) {
                        Text(item.source.lastPathComponent)
                            .foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name.isEmpty ? "—" : item.name)
                                .fontWeight(item.changes ? .semibold : .regular)
                                .foregroundStyle(problems[index] == nil ? (item.changes ? Theme.accent : .secondary) : .red)
                                .lineLimit(1).truncationMode(.middle)
                            if let problem = problems[index] {
                                Text(problem.message).font(.caption).foregroundStyle(.red)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.callout)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 14)
                    if index < items.count - 1 { Divider() }
                }
            }
            .card()

            FormHint("Files are renamed where they are. Nothing is overwritten, and if one rename fails every file keeps its old name.")
        }
    }

    private func rename(_ items: [BatchRename.Item]) {
        ToolWindowManager.shared.close(session)
        JobRunner.shared.run(title: session.tool.progressTitle, detail: items.count == 1 ? items[0].source.lastPathComponent : "\(items.count) items", symbol: session.tool.symbol) { progress in
            let renamed = try BatchRename.apply(items)
            progress(1)
            return renamed
        }
    }
}
