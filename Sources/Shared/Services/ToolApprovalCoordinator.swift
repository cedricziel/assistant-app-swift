import Foundation

/// Coordinates tool call approvals between the AgentLoop and the UI.
///
/// The AgentLoop suspends on `requestApproval`, which publishes a
/// `pendingRequest` that the UI observes. When the user taps approve
/// or deny, the UI calls `resolve(_:)` which resumes the continuation.
@MainActor
final class ToolApprovalCoordinator: ObservableObject {
    /// The currently pending approval request, if any.
    @Published private(set) var pendingRequest: ToolApprovalRequest?

    private var continuation: CheckedContinuation<ToolApprovalRequest.Decision, Never>?

    /// Called by AgentLoop (via the approval handler closure) to request approval.
    /// Suspends until the user responds.
    func requestApproval(for request: ToolApprovalRequest) async -> ToolApprovalRequest.Decision {
        // If there's already a pending request, deny the new one to avoid deadlock.
        if pendingRequest != nil {
            return .denied
        }

        return await withCheckedContinuation { cont in
            self.continuation = cont
            self.pendingRequest = request
        }
    }

    /// Called by the UI when the user approves or denies.
    func resolve(_ decision: ToolApprovalRequest.Decision) {
        guard let cont = continuation else { return }
        continuation = nil
        pendingRequest = nil
        cont.resume(returning: decision)
    }
}
