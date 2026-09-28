import SwiftUI

struct QuotaPost: Identifiable {
    let id: String
    let date: Date?
    let text: String
    let reply: String?
    let url: URL?
    let isReset: Bool
}

struct QuotaPostsView: View {
    let posts: [QuotaPost]
    @State private var expanded = false
    @State private var resetOnly = false
    private var filtered: [QuotaPost] { (resetOnly ? posts.filter(\.isReset) : posts).sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) } }
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Posts", selection: $resetOnly) {
                    Text("All posts").tag(false)
                    Text("Reset updates").tag(true)
                }.pickerStyle(.segmented)
                if filtered.isEmpty { Text("No recent posts in this view.").font(.subheadline).foregroundStyle(.secondary) }
                ForEach(filtered) { post in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(post.text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                            if let reply = post.reply, !reply.isEmpty {
                                Text(reply).font(.system(size: 11)).foregroundStyle(.secondary)
                                    .padding(.leading, 10).overlay(alignment: .leading) { Rectangle().fill(Color.white.opacity(0.18)).frame(width: 2) }
                            }
                            if let url = post.url { Link("Open on X ↗", destination: url).font(.system(size: 12, weight: .medium)).padding(.vertical, 4) }
                        }.padding(.vertical, 10)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            if let date = post.date {
                                Text(date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                                    .font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            Text(post.text).font(.system(size: 13, weight: .medium)).lineLimit(2)
                        }.padding(.vertical, 4)
                    }
                    if post.id != filtered.last?.id { Divider().opacity(0.5) }
                }
            }.padding(.top, 15)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Tibo posts", systemImage: "text.bubble").font(.system(size: 15, weight: .semibold, design: .rounded))
                    Spacer()
                    Text("\(posts.count)").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                if !expanded, let post = posts.first {
                    Text(post.text).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
    }
}
