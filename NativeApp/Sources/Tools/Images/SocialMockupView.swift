import SwiftUI

/// The picture as it would appear on the network: a post in a feed, a full-screen story,
/// a video in a list or a shared card, with the name, title and caption typed beside it.
/// Drawn from scratch to give the feel of each layout; nothing is sent anywhere.
struct SocialMockupView: View {
    let format: SocialFormat
    let image: NSImage
    var account: String
    var title: String
    var caption: String
    var showCovered = true
    /// The room there is: the mockup shrinks to fit it whole.
    var available = CGSize(width: 10_000, height: 10_000)
    @Environment(\.colorScheme) private var scheme

    private var ratio: CGFloat { format.size.height / format.size.width }

    /// The mockup's width, at most its natural one, so that it fits whole in `available`.
    private var width: CGFloat {
        let h = available.height, w = available.width
        switch format.layout {
        case .feed: return max(200, min(380, w, (h - 175) / ratio))
        case .story: return max(160, min(300, w, h * 9 / 16))
        case .video: return max(240, min(440, w - 28, (h - 110) / ratio))
        case .card:
            if format == .pinterestPin { return max(160, min(260, w - 28, (h - 110) / ratio)) }
            return max(240, min(440, w - 28, (h - 190) / ratio))
        }
    }

    private var name: String { account.isEmpty ? "your.account" : account }
    private var ink: Color { scheme == .dark ? .white : .black }
    private var paper: Color { scheme == .dark ? Color(white: 0.07) : .white }

    var body: some View {
        Group {
            switch format.layout {
            case .feed: feed
            case .story: story
            case .video: video
            case .card: card
            }
        }
        .foregroundStyle(ink)
    }

    private var avatar: some View {
        Circle()
            .fill(LinearGradient(colors: [Theme.accent, .pink, .purple], startPoint: .bottomLeading, endPoint: .topTrailing))
            .overlay(Text(String(name.prefix(1)).uppercased()).font(.system(size: 13, weight: .bold)).foregroundStyle(.white))
    }

    private var picture: some View {
        Image(nsImage: image).resizable().interpolation(.high).aspectRatio(format.size, contentMode: .fit)
    }

    // A square-cornered post between a header and a row of actions.
    private var feed: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                avatar.frame(width: 30, height: 30)
                Text(name).font(.system(size: 13, weight: .semibold))
                Spacer()
                Image(systemName: "ellipsis")
            }
            .padding(10)
            picture
            HStack(spacing: 16) {
                Image(systemName: "heart"); Image(systemName: "bubble.right"); Image(systemName: "paperplane")
                Spacer()
                Image(systemName: "bookmark")
            }
            .font(.system(size: 19))
            .padding(.horizontal, 12).padding(.top, 10)
            Text("1,024 likes").font(.system(size: 13, weight: .semibold)).padding(.horizontal, 12).padding(.top, 6)
            (Text(name).fontWeight(.semibold) + Text(" ") + Text(caption.isEmpty ? "A few words about this picture" : caption))
                .font(.system(size: 13)).lineLimit(2).padding(.horizontal, 12).padding(.top, 3)
            Text("2 hours ago").font(.system(size: 11)).foregroundStyle(.secondary).padding(12)
        }
        .frame(width: width)
        .background(paper)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // Full screen, the app's buttons over the picture; the covered parts can be shown.
    private var story: some View {
        let width = self.width, height = width * 16 / 9
        return ZStack {
            Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                .frame(width: width, height: height).clipped()
            if showCovered {
                VStack(spacing: 0) {
                    Rectangle().fill(.red.opacity(0.22)).frame(height: height * format.coveredTop)
                    Spacer()
                    Rectangle().fill(.red.opacity(0.22)).frame(height: height * format.coveredBottom)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                if format == .instagramStory {
                    HStack(spacing: 3) { ForEach(0..<3) { index in Capsule().fill(.white.opacity(index == 0 ? 0.95 : 0.4)).frame(height: 2.5) } }
                    HStack(spacing: 8) {
                        avatar.frame(width: 28, height: 28)
                        Text(name).font(.system(size: 13, weight: .semibold))
                        Text("2 h").font(.system(size: 12)).opacity(0.75)
                        Spacer()
                        Image(systemName: "xmark")
                    }
                }
                Spacer()
                if format == .tiktok || format == .youtubeShort {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("@\(name)").font(.system(size: 14, weight: .semibold))
                            if format == .youtubeShort {
                                Text(title.isEmpty ? "The title of your Short" : title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                                if !caption.isEmpty { Text(caption).font(.system(size: 12)).lineLimit(1) }
                            } else {
                                Text(caption.isEmpty ? "A few words about this video" : caption).font(.system(size: 12)).lineLimit(2)
                                Label(title.isEmpty ? "original sound" : title, systemImage: "music.note").font(.system(size: 11)).lineLimit(1)
                            }
                        }
                        Spacer()
                        VStack(spacing: 16) {
                            avatar.frame(width: 38, height: 38)
                            ForEach([("heart.fill", "12.3K"), ("ellipsis.bubble.fill", "214"), ("bookmark.fill", "980"), ("arrowshape.turn.up.right.fill", "1.1K")], id: \.0) { icon, count in
                                VStack(spacing: 2) { Image(systemName: icon).font(.system(size: 22)); Text(count).font(.system(size: 10, weight: .semibold)) }
                            }
                        }
                    }
                } else {
                    if !caption.isEmpty {
                        Text(caption).font(.system(size: 13, weight: .medium)).lineLimit(2)
                    }
                    HStack(spacing: 10) {
                        Text("Send message").font(.system(size: 13)).padding(.horizontal, 14).padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(Capsule().strokeBorder(.white.opacity(0.7)))
                        Image(systemName: "heart"); Image(systemName: "paperplane")
                    }
                    .font(.system(size: 18))
                }
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 3)
            .padding(12)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    // A thumbnail in a list of videos, with its length, title and channel.
    private var video: some View {
        VStack(alignment: .leading, spacing: 10) {
            picture
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .bottomTrailing) {
                    Text("12:34").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 4)).padding(6)
                }
            HStack(alignment: .top, spacing: 10) {
                avatar.frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title.isEmpty ? "The title of your video" : title).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                    Text("\(name) · 12K views · 2 days ago").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "ellipsis").rotationEffect(.degrees(90))
            }
        }
        .frame(width: width)
        .padding(14)
        .background(paper)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // A post with its words above a rounded picture; a pin has its title below.
    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            if format == .pinterestPin {
                picture.clipShape(RoundedRectangle(cornerRadius: 16))
                Text(title.isEmpty ? "The title of your pin" : title).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                HStack(spacing: 6) { avatar.frame(width: 22, height: 22); Text(name).font(.system(size: 12)) }
            } else {
                HStack(spacing: 10) {
                    avatar.frame(width: 38, height: 38)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title.isEmpty ? name : title).font(.system(size: 14, weight: .semibold))
                        Text(format == .xPost ? "@\(name) · 2h" : "2 h · \(Image(systemName: "globe"))").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "ellipsis")
                }
                Text(caption.isEmpty ? "A few words about this picture" : caption).font(.system(size: 14)).lineLimit(3)
                picture.clipShape(RoundedRectangle(cornerRadius: format == .xPost ? 14 : 4))
                HStack {
                    ForEach(format == .xPost ? ["bubble.left", "arrow.2.squarepath", "heart", "chart.bar", "square.and.arrow.up"] : ["hand.thumbsup", "bubble.left", "arrow.2.squarepath", "paperplane"], id: \.self) { icon in
                        Image(systemName: icon)
                        if icon != (format == .xPost ? "square.and.arrow.up" : "paperplane") { Spacer() }
                    }
                }
                .font(.system(size: 15)).foregroundStyle(.secondary).padding(.horizontal, 6)
            }
        }
        .frame(width: width)
        .padding(14)
        .background(paper)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
