import Foundation

/// Fires on the second release: a second press that becomes Option+key never triggers a peek.
struct OptionTapRecognizer: Sendable {
    /// Longest a single tap may be held down.
    let maxHold: TimeInterval = 0.35
    /// Longest pause between releasing the first tap and pressing the second.
    let maxGap: TimeInterval = 0.4
    private var downAt: TimeInterval?
    private var firstRelease: TimeInterval?
    private var invalid = false

    mutating func cancel() {
        downAt = nil
        firstRelease = nil
        invalid = true
    }

    mutating func keyChanged(leftOptionDown: Bool, otherModifiers: Bool, at time: TimeInterval) -> Bool {
        if otherModifiers { cancel(); return false }
        if leftOptionDown {
            guard downAt == nil else { return false }
            if let firstRelease, time - firstRelease > maxGap { self.firstRelease = nil }
            downAt = time
            invalid = false
            return false
        }
        guard let downAt else { return false }
        self.downAt = nil
        guard !invalid, time - downAt <= maxHold else { firstRelease = nil; return false }
        if firstRelease != nil {
            firstRelease = nil
            return true
        }
        firstRelease = time
        return false
    }
}
