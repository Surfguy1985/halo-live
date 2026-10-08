import SwiftUI
import UniformTypeIdentifiers

/// Local-only layout editor preview; publishing is intentionally not wired.
struct HaloWorkflowBlockEditor: View {
    let original: HaloWorkflowBlocks.Layout
    let roles: Set<String>
    @State private var draft: HaloWorkflowBlocks.Layout

    init(layout: HaloWorkflowBlocks.Layout, roles: Set<String>) {
        self.original = layout
        self.roles = roles
        _draft = State(initialValue: layout)
    }

    private var ordered: [HaloWorkflowBlocks.Block] {
        HaloWorkflowBlocks.visibleBlocks(in: draft, roles: roles)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Local preview only. Changes are not published.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Workflow blocks") {
                    ForEach(ordered) { block in
                        HStack(spacing: 12) {
                            Image(systemName: icon(for: block.kind))
                                .foregroundStyle(.tint)
                                .frame(width: 28)
                            VStack(alignment: .leading) {
                                Text(block.title).font(.headline)
                                Text(block.kind.rawValue).font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if block.required {
                                Text("Required").font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    .onMove(perform: move)
                }
            }
            .navigationTitle("Workflow designer")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") { draft = original }
                }
            }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var visible = ordered.map(\.id)
        visible.move(fromOffsets: source, toOffset: destination)
        // Preserve relative ordering of hidden blocks. A role-filtered client
        // cannot implicitly remove or rewrite blocks it cannot display.
        let visibleIDs = Set(visible)
        var iterator = visible.makeIterator()
        let fullOrder = draft.blocks.sorted(by: { $0.order < $1.order }).map { block in
            visibleIDs.contains(block.id) ? (iterator.next() ?? block.id) : block.id
        }
        if case let .success(next) = HaloWorkflowBlocks.reordered(draft, orderedIDs: fullOrder) {
            draft = next
        }
    }

    private func icon(for kind: HaloWorkflowBlocks.Kind) -> String {
        switch kind {
        case .assignment: return "person.2"
        case .location: return "mappin"
        case .checklist: return "checklist"
        case .photoProof: return "camera"
        case .pricing: return "dollarsign.circle"
        case .approval: return "checkmark.seal"
        case .messaging: return "bubble.left.and.bubble.right"
        case .closeout: return "flag.checkered"
        }
    }
}
