import Foundation

public enum BlueskyThreadRef {
    /// The (uri,cid) to store as a post's thread root so replies thread correctly:
    /// the post's own ref if it is top-level, otherwise the existing thread root.
    public static func root(postURI: String, postCID: String,
                            replyRoot: (uri: String, cid: String)?) -> (uri: String, cid: String) {
        replyRoot ?? (uri: postURI, cid: postCID)
    }
}
