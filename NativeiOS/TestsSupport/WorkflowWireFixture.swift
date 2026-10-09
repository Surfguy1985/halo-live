import Foundation

/// Compiled with the production Swift domain models in macOS CI.
@main
struct WorkflowWireFixture {
    static func main() throws {
        let layout = HaloWorkflowBlocks.Layout(
            schemaVersion: 1,
            templateID: "construction-dispatch",
            templateVersion: 1,
            tenantID: "staging-tenant",
            industryID: "construction",
            blocks: [
                .init(id: "assign", kind: .assignment, title: "Assign crew",
                      order: 0, required: true,
                      visibleToRoles: ["dispatcher"], config: ["allowSelfAssign": "false"]),
                .init(id: "proof", kind: .photoProof, title: "Photo proof",
                      order: 1, required: true,
                      visibleToRoles: ["crew"], config: ["minPhotos": "2"])
            ]
        )
        let requestID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        guard case .success(let proposal) = HaloTemplatePublishing.prepare(
            layout: layout, expectedRevision: 0,
            actorID: "staging-admin", requestID: requestID
        ) else {
            fatalError("Swift fixture failed client-side validation")
        }
        FileHandle.standardOutput.write(try JSONEncoder().encode(proposal))
    }
}
