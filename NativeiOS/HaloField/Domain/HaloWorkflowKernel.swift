import Foundation

/// Pure, side-effect-free local workflow evaluator.
/// The server remains authoritative for authorization and persistence.
enum HaloWorkflowKernel {
    struct Context: Equatable {
        let tenantID: String
        let industryID: String
        let actorID: String
        let roles: Set<String>
        let evidenceKeys: Set<String>
    }

    struct Transition: Equatable {
        let id: String
        let fromState: String
        let toState: String
        let allowedRoles: Set<String>
        let requiredEvidenceKeys: Set<String>
    }

    struct Template: Equatable {
        let id: String
        let version: Int
        let tenantID: String
        let industryID: String
        let initialState: String
        let terminalStates: Set<String>
        let transitions: [Transition]
    }

    struct WorkItem: Equatable {
        let id: String
        let tenantID: String
        let industryID: String
        let templateID: String
        let templateVersion: Int
        let state: String
    }

    enum Rejection: Error, Equatable {
        case invalidTemplate
        case tenantMismatch
        case industryMismatch
        case templateMismatch
        case actorUnidentified
        case invalidTransition
        case forbidden
        case missingEvidence(Set<String>)
        case terminalState
    }

    static func validate(_ template: Template) -> Bool {
        guard !template.id.isEmpty, template.version > 0,
              !template.tenantID.isEmpty, !template.industryID.isEmpty,
              !template.initialState.isEmpty, !template.transitions.isEmpty else { return false }
        let states = Set(template.transitions.flatMap { [$0.fromState, $0.toState] })
        guard states.contains(template.initialState),
              template.terminalStates.isSubset(of: states),
              !template.terminalStates.isEmpty else { return false }
        var seen = Set<String>()
        for transition in template.transitions {
            guard !transition.id.isEmpty, !transition.fromState.isEmpty,
                  !transition.toState.isEmpty, transition.fromState != transition.toState,
                  !transition.allowedRoles.isEmpty,
                  !template.terminalStates.contains(transition.fromState),
                  seen.insert(transition.id).inserted else { return false }
        }
        return true
    }

    /// Caller must enforce the returned decision on the backend too.
    static func evaluate(
        template: Template,
        item: WorkItem,
        transitionID: String,
        context: Context
    ) -> Result<String, Rejection> {
        guard validate(template) else { return .failure(.invalidTemplate) }
        guard !context.actorID.isEmpty else { return .failure(.actorUnidentified) }
        guard template.tenantID == item.tenantID,
              item.tenantID == context.tenantID else { return .failure(.tenantMismatch) }
        guard template.industryID == item.industryID,
              item.industryID == context.industryID else { return .failure(.industryMismatch) }
        guard template.id == item.templateID,
              template.version == item.templateVersion else { return .failure(.templateMismatch) }
        guard !template.terminalStates.contains(item.state) else { return .failure(.terminalState) }
        guard let transition = template.transitions.first(where: {
            $0.id == transitionID && $0.fromState == item.state
        }) else { return .failure(.invalidTransition) }
        guard !transition.allowedRoles.isDisjoint(with: context.roles) else { return .failure(.forbidden) }
        let missing = transition.requiredEvidenceKeys.subtracting(context.evidenceKeys)
        guard missing.isEmpty else { return .failure(.missingEvidence(missing)) }
        return .success(transition.toState)
    }
}
