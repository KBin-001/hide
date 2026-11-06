/// Moves one setting between the app's two stores without leaving a stale copy.
enum RestrictionStoreRouting {
    enum Location: String { case defaultStore, legacy }

    static func submit<Value: Hashable>(
        _ desired: Set<Value>, write: (Location, Set<Value>) -> Bool
    ) -> Bool {
        let defaultMatches = write(.defaultStore, desired)
        if defaultMatches || desired.isEmpty {
            let legacyCleared = write(.legacy, [])
            return defaultMatches && legacyCleared
        }

        guard write(.legacy, desired) else { return false }
        return write(.defaultStore, [])
    }
}
