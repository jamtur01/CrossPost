import SwiftUI

struct FeedPostView: View {
    let post: FeedPost
    let onReply: () -> Void
    let onLike: () -> Void
    let onRepost: () -> Void
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                AsyncImage(url: post.avatarURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(.quaternary)
                }
                .frame(width: 36, height: 36)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text(post.authorName).font(.subheadline.bold()).lineLimit(1)
                    Text(post.authorHandle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(post.date, format: .relative(presentation: .numeric))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Text(post.text).font(.body).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !post.images.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(post.images) { image in
                            AsyncImage(url: image.url) { img in
                                img.resizable().scaledToFill()
                            } placeholder: {
                                Rectangle().fill(.quaternary)
                            }
                            .frame(width: 120, height: 90)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .accessibilityLabel(image.altText)
                        }
                    }
                }
            }

            HStack(spacing: 18) {
                Button(action: onReply) { Image(systemName: "arrowshape.turn.up.left") }
                    .help("Reply")
                Button(action: onLike) {
                    Image(systemName: post.isLiked ? "heart.fill" : "heart")
                        .foregroundStyle(post.isLiked ? .red : .secondary)
                }.help("Like")
                Button(action: onRepost) {
                    Image(systemName: "arrow.2.squarepath")
                        .foregroundStyle(post.isReposted ? .green : .secondary)
                }.help("Repost")
                Spacer()
                Button(action: onOpen) { Image(systemName: "safari") }.help("Open in browser")
            }
            .buttonStyle(.borderless)
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }
}
