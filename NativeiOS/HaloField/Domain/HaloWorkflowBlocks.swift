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

    // Mirror the isolated Node v1 contract. These checks protect local drafts;
    // the backend remains the only authority for publishing or execution.
    private static func validIdentifier(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$"#,
                    options: .regularExpression) != nil
    }

    private static func validConfig(_ block: Block) -> Bool {
        if block.config.count > 8 { return false }
        let allowed: Set<String>
        switch block.kind {
        case .assignment: allowed = ["allowSelfAssign"]
        case .location: allowed = ["radiusMeters"]
        case .checklist: allowed = ["minChecks"]
        case .photoProof: allowed = ["minPhotos"]
        case .pricing: allowed = ["currencyCode", "requireApprovedQuote"]
        case .approval: allowed = ["minApprovers"]
        case .messaging: allowed = ["channel"]
        case .closeout: allowed = ["requireVerifiedEvidence"]
        }
        for (key, value) in block.config {
            if !allowed.contains(key) || value.utf16.count > 128 { return false }
            switch key {
            case "allowSelfAssign", "requireApprovedQuote", "requireVerifiedEvidence":
                if value != "true" && value != "false" { return false }
            case "currencyCode":
                if value.range(of: #"^[A-Z]{3}$"#, options: .regularExpression) == nil { return false }
            case "channel":
                if value.range(of: #"^[a-z][a-z0-9_-]{0,63}$"#, options: .regularExpression) == nil { return false }
            case "radiusMeters", "minChecks", "minPhotos", "minApprovers":
                if value.range(of: #"^(0|[1-9][0-9]*)$"#, options: .regularExpression) == nil ||
                    value.utf8.count > 15 { return false }
                guard let number = Int(value) else { return false }
                let range: ClosedRange<Int>
                switch key {
                case "radiusMeters": range = 1...50_000
                case "minChecks": range = 0...100
                case "minPhotos": range = 1...20
                default: range = 1...10
                }
                if !range.contains(number) { return false }
            default: return false
            }
        }
        return true
    }

    static func validate(_ layout: Layout) -> Result<Layout, ValidationError> {
        guard layout.schemaVersion == supportedSchemaVersion else {
            return .failure(.unsupportedSchema)
        }
        guard validIdentifier(layout.templateID), layout.templateVersion > 0,
              validIdentifier(layout.tenantID), validIdentifier(layout.industryID) else {
            return .failure(.invalidIdentity)
        }
        guard layout.blocks.count <= maxBlocks else { return .failure(.tooManyBlocks) }
        var ids = Set<String>()
        var orders = Set<Int>()
        for block in layout.blocks {
            guard validIdentifier(block.id),
                  !block.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  block.title.utf16.count <= 160,
                  block.order >= 0, block.visibleToRoles.count >= 1,
                  block.visibleToRoles.count <= 16,
                  block.visibleToRoles.allSatisfy(validIdentifier),
                  Set(block.visibleToRoles).count == block.visibleToRoles.count,
                  validConfig(block) else {
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
