struct ProfilePartialLoadState {
    var relationship: AccountRelationship?
    var relationshipError: String?
    var pinnedError: String?
    var isPinnedLoading = false

    mutating func beginRelationshipLoad() {
        relationship = nil
        relationshipError = nil
    }

    mutating func finishRelationship(_ result: Result<AccountRelationship, Error>) {
        switch result {
        case let .success(loaded):
            relationship = loaded
            relationshipError = nil
        case let .failure(error):
            relationship = nil
            relationshipError = error.userMessage
        }
    }

    mutating func beginPinnedLoad() {
        pinnedError = nil
        isPinnedLoading = true
    }

    mutating func finishPinned(
        _ result: Result<[FeedPost], Error>,
        posts: inout [FeedPost]
    ) {
        isPinnedLoading = false
        switch result {
        case let .success(loaded):
            posts = loaded
            pinnedError = nil
        case let .failure(error):
            pinnedError = error.userMessage
        }
    }
}
