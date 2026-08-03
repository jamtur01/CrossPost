import SwiftUI

struct ProfileFollowMutation {
    let previousRelationship: AccountRelationship
    let previousFollowerCount: Int?

    var target: Bool {
        !previousRelationship.isFollowing
    }

    var optimisticRelationship: AccountRelationship {
        var relationship = previousRelationship
        relationship.isFollowing = target
        return relationship
    }

    var optimisticFollowerCount: Int? {
        previousFollowerCount.map { max(0, $0 + (target ? 1 : -1)) }
    }

    func restoredFollowerCount(current: Int?) -> Int? {
        current == optimisticFollowerCount ? previousFollowerCount : current
    }

    func rollback(currentFollowerCount: Int?) -> (
        relationship: AccountRelationship,
        followerCount: Int?
    ) {
        (
            relationship: previousRelationship,
            followerCount: restoredFollowerCount(current: currentFollowerCount)
        )
    }
}

extension ProfileView {
    @ViewBuilder
    var relationshipControls: some View {
        if let relationship = partialLoad.relationship {
            loadedRelationshipControls(relationship)
        } else {
            relationshipControlsPlaceholder
        }
    }

    private func loadedRelationshipControls(_ relationship: AccountRelationship) -> some View {
        HStack(spacing: 8) {
            Group {
                if relationship.isFollowing {
                    Button("Following") { startRelationshipAction(.follow) }
                        .buttonStyle(.bordered)
                } else {
                    Button(relationship.isFollowedBy ? "Follow back" : "Follow") {
                        startRelationshipAction(.follow)
                    }
                    .buttonStyle(.borderedProminent).tint(accent)
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .disabled(isUpdatingRelationship)

            Menu {
                Button(relationship.isMuting ? "Unmute" : "Mute") {
                    startRelationshipAction(.mute)
                }
                Button(relationship.isBlocking ? "Unblock" : "Block", role: .destructive) {
                    startRelationshipAction(.block)
                }
                Divider()
                Button("Report…", role: .destructive) { reportingAccount = true }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(.secondary)
            .disabled(isUpdatingRelationship)
        }
    }

    private var relationshipControlsPlaceholder: some View {
        HStack(spacing: 8) {
            Button("Relationship") {}
                .buttonStyle(.bordered)
            Button {} label: {
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .fixedSize()
        }
        .font(.system(size: 13, weight: .semibold))
        .disabled(true)
        .redacted(reason: .placeholder)
    }

    private enum RelationshipAction {
        case follow
        case mute
        case block
    }

    private func startRelationshipAction(_ action: RelationshipAction) {
        guard partialLoad.relationship != nil else { return }
        relationshipTask?.cancel()
        relationshipGeneration += 1
        let generation = relationshipGeneration
        isUpdatingRelationship = true
        relationshipTask = Task {
            guard relationshipGeneration == generation else { return }
            switch action {
            case .follow: await toggleFollow(generation: generation)
            case .mute: await toggleMute(generation: generation)
            case .block: await toggleBlock(generation: generation)
            }
        }
    }

    func invalidateRelationshipAction() {
        relationshipGeneration += 1
        relationshipTask?.cancel()
        relationshipTask = nil
        isUpdatingRelationship = false
    }

    private func finishRelationshipAction(generation: UInt) {
        guard relationshipGeneration == generation else { return }
        relationshipTask = nil
        isUpdatingRelationship = false
    }

    private func restoreFollowMutation(_ mutation: ProfileFollowMutation) {
        let rollback = mutation.rollback(currentFollowerCount: profile?.followers)
        partialLoad.relationship = rollback.relationship
        if let followerCount = rollback.followerCount {
            profile?.followers = followerCount
        }
    }

    private func toggleFollow(generation: UInt) async {
        guard let relationship = partialLoad.relationship else { return }
        let mutation = ProfileFollowMutation(
            previousRelationship: relationship,
            previousFollowerCount: profile?.followers
        )
        partialLoad.relationship = mutation.optimisticRelationship
        if let optimisticFollowerCount = mutation.optimisticFollowerCount {
            profile?.followers = optimisticFollowerCount
        }
        do {
            let updated = try await panel.setFollowing(
                mutation.target,
                for: accountID,
                current: mutation.previousRelationship
            )
            guard relationshipGeneration == generation else { return }
            partialLoad.relationship = updated
        } catch is CancellationError {
            guard relationshipGeneration == generation else { return }
            restoreFollowMutation(mutation)
        } catch {
            guard relationshipGeneration == generation else { return }
            restoreFollowMutation(mutation)
            panel.reportError(error.userMessage)
        }
        finishRelationshipAction(generation: generation)
    }

    private func toggleMute(generation: UInt) async {
        guard var relationship = partialLoad.relationship else { return }
        let target = !relationship.isMuting
        let previous = relationship
        relationship.isMuting = target
        partialLoad.relationship = relationship
        do {
            let updated = try await panel.setMuted(
                target,
                for: accountID,
                current: previous
            )
            guard relationshipGeneration == generation else { return }
            partialLoad.relationship = updated
        } catch is CancellationError {
            guard relationshipGeneration == generation else { return }
            partialLoad.relationship = previous
        } catch {
            guard relationshipGeneration == generation else { return }
            partialLoad.relationship = previous
            panel.reportError(error.userMessage)
        }
        finishRelationshipAction(generation: generation)
    }

    private func toggleBlock(generation: UInt) async {
        guard var relationship = partialLoad.relationship else { return }
        let target = !relationship.isBlocking
        let previous = relationship
        relationship.isBlocking = target
        partialLoad.relationship = relationship
        do {
            let updated = try await panel.setBlocked(
                target,
                for: accountID,
                current: previous
            )
            guard relationshipGeneration == generation else { return }
            partialLoad.relationship = updated
        } catch is CancellationError {
            guard relationshipGeneration == generation else { return }
            partialLoad.relationship = previous
        } catch {
            guard relationshipGeneration == generation else { return }
            partialLoad.relationship = previous
            panel.reportError(error.userMessage)
        }
        finishRelationshipAction(generation: generation)
    }

    var accent: Color {
        panel.target.accent
    }

    var accountID: String {
        profile?.id ?? ref.id
    }
}
