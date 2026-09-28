import AppIntents
import SwiftUI
import WidgetKit

extension Color {
  init(argb: Int) {
    self.init(
      .sRGB,
      red: Double((argb >> 16) & 0xFF) / 255,
      green: Double((argb >> 8) & 0xFF) / 255,
      blue: Double(argb & 0xFF) / 255,
      opacity: Double((argb >> 24) & 0xFF) / 255
    )
  }
}

struct NowPlayingEntry: TimelineEntry {
  let date: Date
  let title: String
  let artist: String
  let album: String
  let coverPath: String
  let coverColor: Int
  let foregroundColor: Int
  let isPlaying: Bool
  let isFavorite: Bool
  let postion: Double
  let duration: Double
  let lyrics: String
  let lyricsIndex: Int
  let family: WidgetFamily

}

struct NowPlayingTimelineProvider: TimelineProvider {

  func placeholder(in context: Context) -> NowPlayingEntry {
    NowPlayingEntry(
      date: Date(),
      title: "Title",
      artist: "Artist",
      album: "Album",
      coverPath: "",
      coverColor: 0xFFFF_FFFF,
      foregroundColor: 0xFFFF_FFFF,
      isPlaying: false,
      isFavorite: false,
      postion: 0,
      duration: 0,
      lyrics: "Lyrics",
      lyricsIndex: 0,
      family: context.family
    )
  }

  func makeEntry(in context: Context) -> NowPlayingEntry {
    let sharedDefaults = UserDefaults(
      suiteName: "group.com.afalphy.sylvakru"
    )

    return NowPlayingEntry(
      date: Date(),
      title: sharedDefaults?.string(forKey: "title") ?? "",
      artist: sharedDefaults?.string(forKey: "artist") ?? "",
      album: sharedDefaults?.string(forKey: "album") ?? "",
      coverPath: sharedDefaults?.string(forKey: "coverPath") ?? "",
      coverColor: sharedDefaults?.integer(forKey: "coverColor") ?? 0xFFFF_FFFF,
      foregroundColor: sharedDefaults?.integer(forKey: "foregroundColor") ?? 0xFFFF_FFFF,
      isPlaying: sharedDefaults?.bool(forKey: "is_playing") ?? false,
      isFavorite: sharedDefaults?.bool(forKey: "is_favorite") ?? false,
      postion: 0,
      duration: 0,
      lyrics: sharedDefaults?.string(forKey: "lyrics") ?? "",
      lyricsIndex: sharedDefaults?.integer(forKey: "lyricsIndex") ?? 0,
      family: context.family
    )
  }

  func getSnapshot(
    in context: Context,
    completion: @escaping (NowPlayingEntry) -> Void
  ) {
    completion(makeEntry(in: context))
  }

  func getTimeline(
    in context: Context,
    completion: @escaping (Timeline<NowPlayingEntry>) -> Void
  ) {
    let entry = makeEntry(in: context)

    completion(
      Timeline(
        entries: [entry],
        policy: .atEnd
      )
    )
  }
}

struct NowPlayingWidgetEntryView: View {
  var entry: NowPlayingTimelineProvider.Entry

  var lyricsLines: [String] {
    entry.lyrics.components(separatedBy: "\n")
  }

  func lyricsView(fontSize: CGFloat, offset: CGFloat) -> some View {
    GeometryReader { geometry in
      let lineHeight = fontSize + 6

      let rawCount = max(1, Int(geometry.size.height / lineHeight))
      let visibleLineCount = rawCount % 2 == 0 ? rawCount + 1 : rawCount

      let halfCount = visibleLineCount / 2
      let start = entry.lyricsIndex - halfCount
      let end = start + visibleLineCount

      VStack(spacing: 6) {
        ForEach(start..<end, id: \.self) { index in
          let isValid = index >= 0 && index < lyricsLines.count
          let lineText = isValid ? lyricsLines[index] : ""
          let isCurrent = index == entry.lyricsIndex

          Text(lineText)
            .font(
              .system(
                size: isCurrent ? fontSize : fontSize - 3,
                weight: isCurrent ? .bold : .medium
              )
            )
            .foregroundColor(
              Color(argb: entry.foregroundColor)
                .opacity(isCurrent ? 1.0 : 0.5)
            )
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .frame(height: lineHeight)
            .opacity(isValid ? (isCurrent ? 1.0 : 0.5) : 0.0)
        }
      }
      .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
      .offset(y: offset)
      .clipped()
    }
  }

  var body: some View {
    Group {
      switch entry.family {
      case .systemSmall:
        smallView
      case .systemMedium:
        mediumView
      case .systemLarge:
        largeView
      case .systemExtraLarge, .systemExtraLargePortrait:
        extraLargeView
      @unknown default:
        smallView
      }
    }
    .containerBackground(
      Color(argb: entry.coverColor),
      for: .widget
    )
  }

  var smallView: some View {
    VStack {
      HStack(alignment: .top) {
        Group {
          if let uiImage = UIImage(contentsOfFile: entry.coverPath) {
            Image(uiImage: uiImage)
              .resizable()
              .aspectRatio(contentMode: .fill)
          } else {
            Image(systemName: "music.note")
              .resizable()
              .aspectRatio(contentMode: .fit)
              .padding(20)
          }
        }
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 6))

        Spacer()

        Button(intent: BackgroundIntent(function: "toggleFavorite")) {
          Image(systemName: entry.isFavorite ? "star.fill" : "star")
            .font(.system(size: 20))
            .foregroundColor(entry.isFavorite ? .red : Color(argb: entry.foregroundColor))
        }
        .buttonStyle(.plain)

      }
      .padding(.horizontal, 16)
      .padding(.top, 24)

      VStack(alignment: .leading, spacing: 2) {
        Text(entry.title)
          .font(.system(size: 12, weight: .bold))
          .foregroundColor(Color(argb: entry.foregroundColor))
          .lineLimit(1)

        Text(entry.artist)
          .font(.system(size: 10))
          .foregroundColor(Color(argb: entry.foregroundColor))
          .lineLimit(1)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.leading, 16)
      .padding(.trailing, 12)

      HStack(alignment: .bottom) {
        Spacer()

        Button(intent: BackgroundIntent(function: "togglePlay")) {
          Image(
            systemName: entry.isPlaying
              ? "pause.circle.fill"
              : "play.circle.fill"
          )
          .font(.system(size: 40))
          .foregroundColor(Color(argb: entry.foregroundColor))
        }
        .buttonStyle(.plain)
      }
      .padding(.trailing, 8)
      .padding(.bottom, 16)
    }

  }

  var mediumView: some View {
    HStack {
      if let uiImage = UIImage(contentsOfFile: entry.coverPath) {
        Image(uiImage: uiImage)
          .resizable()
          .aspectRatio(contentMode: .fill)
          .frame(width: 125, height: 125)
          .clipShape(RoundedRectangle(cornerRadius: 12))
          .padding(.leading, 16)
          .padding(.trailing, 4)
      }

      VStack(alignment: .leading) {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 4) {
            Text(entry.title)
              .font(.system(size: 14, weight: .bold))
              .foregroundColor(Color(argb: entry.foregroundColor))
              .lineLimit(1)

            Text(entry.artist)
              .font(.system(size: 12))
              .foregroundColor(Color(argb: entry.foregroundColor))
              .lineLimit(1)

            Text(entry.album)
              .font(.system(size: 12))
              .foregroundColor(Color(argb: entry.foregroundColor))
              .lineLimit(1)

          }

          Spacer()

          Button(intent: BackgroundIntent(function: "toggleFavorite")) {
            Image(systemName: entry.isFavorite ? "star.fill" : "star")
              .font(.system(size: 20))
              .foregroundColor(entry.isFavorite ? .red : Color(argb: entry.foregroundColor))
          }
          .buttonStyle(.plain)
        }

        Spacer()

        HStack {
          Button(intent: BackgroundIntent(function: "skipToPrevious")) {
            Image(systemName: "backward.fill")
              .font(.system(size: 25))
              .foregroundColor(Color(argb: entry.foregroundColor))

          }
          .buttonStyle(.plain)

          Spacer()

          Button(intent: BackgroundIntent(function: "togglePlay")) {
            Image(systemName: entry.isPlaying ? "pause.circle.fill" : "play.circle.fill")
              .font(.system(size: 40))
              .foregroundColor(Color(argb: entry.foregroundColor))

          }
          .buttonStyle(.plain)

          Spacer()

          Button(intent: BackgroundIntent(function: "skipToNext")) {
            Image(systemName: "forward.fill")
              .font(.system(size: 25))
              .foregroundColor(Color(argb: entry.foregroundColor))

          }
          .buttonStyle(.plain)
        }
      }
      .frame(height: 120)
      .padding(.trailing, 12)
    }

  }

  var largeView: some View {
    VStack {
      mediumView
        .frame(height: 140)
        .padding(.top, 10)

      Divider()
        .overlay(Color(argb: entry.foregroundColor).opacity(0.8))
        .padding(.horizontal, 10)

      lyricsView(fontSize: 16, offset: -16)
        .frame(maxHeight: .infinity)
        .padding(.horizontal)
    }
  }

  var extraLargeView: some View {
    VStack {
      mediumView
        .frame(height: 140)
        .padding(.top, 10)

      Divider()
        .overlay(Color(argb: entry.foregroundColor).opacity(0.8))
        .padding(.horizontal, 10)

      lyricsView(fontSize: 18, offset: -24)
        .frame(maxHeight: .infinity)
        .padding(.horizontal)
    }
  }
}

struct NowPlaying: Widget {
  let kind: String = "NowPlaying"

  var body: some WidgetConfiguration {
    StaticConfiguration(
      kind: kind,
      provider: NowPlayingTimelineProvider()
    ) { entry in
      NowPlayingWidgetEntryView(entry: entry)
    }
    .configurationDisplayName("Now Playing")
    .contentMarginsDisabled()
    .supportedFamilies(supportedFamilies)
  }

  private var supportedFamilies: [WidgetFamily] {
    if #available(iOS 27.0, *) {
      return [
        .systemSmall,
        .systemMedium,
        .systemLarge,
        .systemExtraLarge,
        .systemExtraLargePortrait,
      ]
    } else {
      return [
        .systemSmall,
        .systemMedium,
        .systemLarge,
        .systemExtraLarge,
      ]
    }
  }
}
