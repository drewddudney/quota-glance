import SwiftUI

/// An independent panel keeps the post beside Codex without enlarging the strip
/// or intercepting clicks in the otherwise empty desktop around it.
struct ProviderTweetBubble: View {
    let tweet: TiboTweet
    @ObservedObject var summary: MenuBarSummaryModel
    @State private var showingPost = false
    @State private var showingFeed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "text.bubble.fill").foregroundStyle(DisplayProvider.codex.tint)
                Text("NEW TIBO POST").font(.system(size: 9, weight: .semibold))
                Spacer()
                Button(action: clear) {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
                        .frame(width: 22, height: 22).background(.white.opacity(0.08), in: Circle())
                }.buttonStyle(.plain).help("Clear new Tibo post").accessibilityLabel("Clear new Tibo post")
            }
            Button {
                showingFeed = false
                showingPost = true
            } label: {
                Text(tweet.text.replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 12, weight: .medium)).lineLimit(2)
                    .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).help("Open Tibo post")
            if let date = tweet.date {
                Text(date, style: .relative).font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(width: 244, height: 108, alignment: .topLeading)
        .foregroundStyle(.white.opacity(0.94))
        .background(Color(red: 0.06, green: 0.09, blue: 0.11), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(DisplayProvider.codex.tint.opacity(0.4), lineWidth: 0.7))
        .preferredColorScheme(.dark)
        .popover(isPresented: $showingPost, arrowEdge: .bottom) {
            if showingFeed {
                TiboTweetsPopover(tweets: summary.payload.tweets)
            } else {
                NewTweetAlertPopover(tweet: tweet, onOpenFeed: { showingFeed = true }, onClear: clear)
            }
        }
    }

    private func clear() {
        showingPost = false
        summary.onClearTweet?()
    }
}
