/// Everything a ``SecureStoring`` can report, in Core's vocabulary.
///
/// A closed set, so a caller switches over it exhaustively. A payload never carries the
/// secret or anything derived from it: an error can end up in a log line or a crash
/// report.
///
/// There is no "not found" case: an absent secret is an answer, not a failure
/// (``SecureStoring/data(for:)`` returns `nil`). There is no cancellation case either —
/// the store is local and cannot observe the calling task's cancellation.
public enum SecureStoringError: Error, Equatable, Sendable {
    /// The store cannot be reached until the user unlocks the device: it has not been
    /// unlocked since it started. Not a lost secret — the caller keeps whatever state it
    /// has and asks again later, and never treats this as "signed out".
    case deviceLocked

    /// Any other failure, identified only by the platform's status code so a log or a bug
    /// report can name it. The caller knows the operation did not happen; branching on a
    /// specific `status` is a sign the case deserves a name of its own here.
    case storageFailure(status: Int)
}
