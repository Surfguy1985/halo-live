import SwiftUI
import UniformTypeIdentifiers

/// A calm, native workflow composer. All edits are local drafts.
/// Publishing requires server-side authorization and validation.
struct HaloWorkflowBlockEditor: View {
    let original: HaloWorkflowBlocks.Layout
    let roles: Set<String>
    @State private var draft: HaloWorkflowBlocks.Layout
    @State private var showingResetConfirmation = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(layout: HaloWorkflowBlocks.Layout, roles: Set<String>) {
        self.original = layout
        self.roles = roles
        _draft = State(initialValue: layout)
    }

    private var ordered: [HaloWorkflowBlocks.Block] {
        HaloWorkflowBlocks.visibleBlocks(in: draft, roles: roles)
    }

    private var isDirty: Bool { draft != original }
    private var hiddenCount: Int { draft.blocks.count - ordered.count }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Image(systemName: "square.stack.3d.up")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(HaloTheme.actionBlue)
                                .frame(width: 48, height: 48)
                                .background(HaloTheme.actionBlue.opacity(0.09), in: RoundedRectangle(cornerRadius: 15))
                            Spacer()
                            HaloStatusPill(text: "Local draft", tint: HaloTheme.actionBlue, icon: "lock.shield")
                        }

                        Text("Make work flow.")
                            .font(HaloType.display(30, weight: .bold))
                            .foregroundStyle(HaloTheme.ink)
                        Text("Arrange the steps your team sees. HALO keeps permissions and publishing on the server.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 12) {
                            Label("\(ordered.count) visible", systemImage: "square.grid.2x2")
                            if hiddenCount > 0 {
                                Label("\(hiddenCount) role-restricted", systemImage: "eye.slash")
                            }
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                        if isDirty {
                            Label("Unsaved preview changes", systemImage: "circle.dotted")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(HaloTheme.actionBlue)
                                .accessibilityAddTraits(.updatesFrequently)
                        }
                    }
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .contain)
                }
                .listRowBackground(HaloTheme.paper)

                Section {
                    ForEach(Array(ordered.enumerated()), id: \.element.id) { index, block in
                        HStack(spacing: 14) {
                            Text(String(format: "%02d", index + 1))
                                .font(.system(.caption, design: .monospaced).weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 27)
                            Image(systemName: icon(for: block.kind))
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(HaloTheme.actionBlue)
                                .frame(width: 44, height: 44)
                                .background(HaloTheme.actionBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(block.title)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(HaloTheme.ink)
                                Text(block.kind.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            if block.required {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(HaloTheme.success)
                                    .accessibilityLabel("Required step")
                            }
                        }
                        .padding(.vertical, 7)
                        .accessibilityElement(children: .combine)
                        .accessibilityHint("Reorder using the edit controls.")
                    }
                    .onMove(perform: move)
                } header: {
                    Text("Workflow sequence")
                } footer: {
                    Text("Only steps visible to your role can be rearranged. Restricted steps retain their positions in the full workflow.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(HaloTheme.paper)
            .navigationTitle("Workflow Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") { showingResetConfirmation = true }
                        .disabled(!isDirty)
                }
            }
            .confirmationDialog("Discard draft changes?", isPresented: $showingResetConfirmation) {
                Button("Discard changes", role: .destructive) {
                    withAnimation(HaloMotion.animation(reduceMotion: reduceMotion)) {
                        draft = original
                    }
                }
            } message: {
                Text("This only resets your local workflow preview.")
            }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var visible = ordered.map(\.id)
        visible.move(fromOffsets: source, toOffset: destination)
        if case let .success(next) = HaloWorkflowBlocks.reorderedVisible(
            draft, roles: roles, orderedVisibleIDs: visible
        ) {
            withAnimation(HaloMotion.animation(reduceMotion: reduceMotion)) { draft = next }
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
