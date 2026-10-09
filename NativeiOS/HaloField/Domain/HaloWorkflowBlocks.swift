import Foundation

/// Presentation-only workflow layout. Never conveys server permissions.
enum HaloWorkflowBlocks {
    enum Kind: String, Codable, CaseIterable {
        case assignment, location, checklist, photoProof
        case pricing, approval, messaging, closeout
    }

    struct Block: Codable, Equatable, Identifiable {
        let id: String
        let kind: Kind
        let title: String
        let order: Int
        let required: Bool
        let visibleToRoles: [String]
        let config: [String: String]
    }

    struct Layout: Codable, Equatable {
        let schemaVersion: Int
        let templateID: String
        let templateVersion: Int
        let tenantID: String
        let industryID: String
        let blocks: [Block]
    }

    enum ValidationError: Error, Equatable {
        case unsupportedSchema
        case invalidIdentity
        case duplicateBlockID
        case duplicateOrder
        case invalidBlock
        case tooManyBlocks
    }

    static let supportedSchemaVersion = 1
    static let maxBlocks = 100

    static func validate(_ layout: Layout) -> Result<Layout, ValidationError> {
        guard layout.schemaVersion == supportedSchemaVersion else {
            return .failure(.unsupportedSchema)
        }
        guard !layout.templateID.isEmpty, layout.templateVersion > 0,
              !layout.tenantID.isEmpty, !layout.industryID.isEmpty else {
            return .failure(.invalidIdentity)
        }
        guard layout.blocks.count <= maxBlocks else { return .failure(.tooManyBlocks) }
        var ids = Set<String>()
        var orders = Set<Int>()
        for block in layout.blocks {
            guard !block.id.isEmpty, !block.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  block.order >= 0, !block.visibleToRoles.isEmpty,
                  block.visibleToRoles.allSatisfy({ !$0.isEmpty }),
                  block.config.keys.allSatisfy({ !$0.isEmpty }) else {
                return .failure(.invalidBlock)
            }
            guard ids.insert(block.id).inserted else { return .failure(.duplicateBlockID) }
            guard orders.insert(block.order).inserted else { return .failure(.duplicateOrder) }
        }
        return .success(layout)
    }

    /// Stable ordering; authorization must be independently enforced by the API.
    static func visibleBlocks(in layout: Layout, roles: Set<String>) -> [Block] {
        guard case .success = validate(layout) else { return [] }
        return layout.blocks
            .filter { !roles.isDisjoint(with: Set($0.visibleToRoles)) }
            .sorted { $0.order < $1.order }
    }

    /// Role-scoped reorder: hidden blocks retain their original slots.
    /// The client cannot edit blocks its current role cannot see.
    static func reorderedVisible(
        _ layout: Layout,
        roles: Set<String>,
        orderedVisibleIDs: [String]
    ) -> Result<Layout, ValidationError> {
        guard case .success = validate(layout) else { return validate(layout) }
        let visible = visibleBlocks(in: layout, roles: roles).map(\.id)
        guard orderedVisibleIDs.count == visible.count,
              Set(orderedVisibleIDs).count == visible.count,
              Set(orderedVisibleIDs) == Set(visible) else {
            return .failure(.invalidBlock)
        }
        let visibleIDs = Set(visible)
        var iterator = orderedVisibleIDs.makeIterator()
        let fullOrder = layout.blocks.sorted { $0.order < $1.order }.map { block in
            visibleIDs.contains(block.id) ? (iterator.next() ?? block.id) : block.id
        }
        return reordered(layout, orderedIDs: fullOrder)
    }

    /// Reorder is a local editor draft. Publishing requires backend validation.
    static func reordered(_ layout: Layout, orderedIDs: [String]) -> Result<Layout, ValidationError> {
        guard case .success = validate(layout) else { return validate(layout) }
        guard orderedIDs.count == layout.blocks.count,
              Set(orderedIDs).count == orderedIDs.count,
              Set(orderedIDs) == Set(layout.blocks.map(\.id)) else {
            return .failure(.invalidBlock)
        }
        let byID = Dictionary(uniqueKeysWithValues: layout.blocks.map { ($0.id, $0) })
        let blocks = orderedIDs.enumerated().compactMap { index, id -> Block? in
            guard let block = byID[id] else { return nil }
            return Block(id: block.id, kind: block.kind, title: block.title,
                         order: index, required: block.required,
                         visibleToRoles: block.visibleToRoles, config: block.config)
        }
        return .success(Layout(schemaVersion: layout.schemaVersion,
                               templateID: layout.templateID,
                               templateVersion: layout.templateVersion,
                               tenantID: layout.tenantID, industryID: layout.industryID,
                               blocks: blocks))
    }
}
