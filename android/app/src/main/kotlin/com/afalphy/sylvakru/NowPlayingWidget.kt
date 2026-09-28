package com.afalphy.sylvakru

import android.content.Context
import android.graphics.BitmapFactory
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.ColorFilter
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalSize
import androidx.glance.action.Action
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.ContentScale
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxHeight
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.TextAlign
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import es.antonborri.home_widget.HomeWidgetPlugin

internal data class NowPlayingData(
  val title: String,
  val artist: String,
  val album: String,
  val coverBitmap: android.graphics.Bitmap?,
  val coverColor: Int,
  val foregroundColor: Int,
  val isPlaying: Boolean,
  val isFavorite: Boolean,
  val lyrics: List<String>,
  val lyricsIndex: Int,
)

internal fun readNowPlayingData(context: Context): NowPlayingData {
  val prefs = HomeWidgetPlugin.getData(context)

  // ARGB colors exceed int32 on the Dart side, so they arrive as Long
  fun intPref(key: String, default: Int): Int =
      when (val value = prefs.all[key]) {
        is Int -> value
        is Long -> value.toInt()
        else -> default
      }

  val coverPath = prefs.getString("coverPath", null)
  val coverBitmap = coverPath?.takeIf { it.isNotEmpty() }?.let { BitmapFactory.decodeFile(it) }

  return NowPlayingData(
    title = prefs.getString("title", "") ?: "",
    artist = prefs.getString("artist", "") ?: "",
    album = prefs.getString("album", "") ?: "",
    coverBitmap = coverBitmap,
    coverColor = intPref("coverColor", 0xFFFFFFFF.toInt()),
    foregroundColor = intPref("foregroundColor", 0xFFFFFFFF.toInt()),
    isPlaying = prefs.getBoolean("is_playing", false),
    isFavorite = prefs.getBoolean("is_favorite", false),
    lyrics = (prefs.getString("lyrics", "") ?: "").split('\n'),
    lyricsIndex = intPref("lyricsIndex", 0),
  )
}

class NowPlayingWidget : GlanceAppWidget() {

  override val sizeMode =
      SizeMode.Responsive(
          setOf(
              DpSize(160.dp, 160.dp), // small
              DpSize(320.dp, 150.dp), // medium
              DpSize(320.dp, 330.dp), // large
              DpSize(420.dp, 520.dp), // extra large
          ))

  override suspend fun provideGlance(context: Context, id: GlanceId) {
    val data = readNowPlayingData(context)

    provideContent {
      Box(GlanceModifier.fillMaxSize().background(ColorProvider(Color(data.coverColor)))) {
        val size = LocalSize.current
        when {
          size.width < 240.dp -> smallLayout(data)
          size.height < 240.dp ->
              mediumLayout(data, coverSize = (size.height.value - 32f).coerceIn(72f, 125f).dp)
          size.height < 420.dp -> largeLayout(data, lyricsFontSize = 15f)
          else -> largeLayout(data, lyricsFontSize = 18f)
        }
      }
    }
  }

  @Composable
  private fun smallLayout(data: NowPlayingData) {
    val fg = Color(data.foregroundColor)
    val size = LocalSize.current
    val coverSize = (size.width.value * 0.38f).coerceIn(40f, 56f).dp

    Column(GlanceModifier.fillMaxSize().padding(12.dp)) {
      Row(GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
        CoverImage(data, size = coverSize, corner = 6.dp)
        Spacer(GlanceModifier.defaultWeight())
        FavoriteButton(data)
      }

      Spacer(GlanceModifier.defaultWeight())

      Text(
          data.title,
          maxLines = 1,
          style =
              TextStyle(fontSize = 11.sp, fontWeight = FontWeight.Bold, color = ColorProvider(fg)),
      )
      Text(data.artist, maxLines = 1, style = TextStyle(fontSize = 10.sp, color = ColorProvider(fg)))

      Spacer(GlanceModifier.defaultWeight())

      Row(GlanceModifier.fillMaxWidth(), horizontalAlignment = Alignment.End) {
        PlayButton(data, size = 32.dp)
      }
    }
  }

  @Composable
  private fun mediumLayout(data: NowPlayingData, coverSize: Dp) {
    Box(GlanceModifier.fillMaxSize()) { mediumContent(data, coverSize = coverSize) }
  }

  @Composable
  private fun largeLayout(data: NowPlayingData, lyricsFontSize: Float) {
    val size = LocalSize.current
    val coverSize = (size.height.value * 0.38f).coerceIn(72f, 125f).dp

    Column(GlanceModifier.fillMaxSize()) {
      Box(GlanceModifier.fillMaxWidth().height(coverSize + 28.dp)) {
        mediumContent(data, coverSize = coverSize)
      }

      Spacer(GlanceModifier.height(10.dp))
      WidgetDivider(foregroundColor = data.foregroundColor)
      Spacer(GlanceModifier.height(10.dp))

      Box(GlanceModifier.fillMaxWidth().defaultWeight()) {
        LyricsContent(data, fontSize = lyricsFontSize)
      }
    }
  }

  @Composable
  private fun mediumContent(data: NowPlayingData, coverSize: Dp) {
    val fg = Color(data.foregroundColor)

    Row(
        GlanceModifier.fillMaxSize().padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
      if (data.coverBitmap != null) {
        CoverImage(data, size = coverSize, corner = 10.dp)
        Spacer(GlanceModifier.width(10.dp))
      }

      Column(GlanceModifier.defaultWeight().fillMaxHeight()) {
        Row(GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
          Column(GlanceModifier.defaultWeight()) {
            Text(
                data.title,
                maxLines = 1,
                style =
                    TextStyle(
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Bold,
                        color = ColorProvider(fg),
                    ),
            )
            Text(
                data.artist,
                maxLines = 1,
                style = TextStyle(fontSize = 11.sp, color = ColorProvider(fg)),
            )
            Text(
                data.album,
                maxLines = 1,
                style = TextStyle(fontSize = 11.sp, color = ColorProvider(fg)),
            )
          }

          FavoriteButton(data)
        }

        Spacer(GlanceModifier.defaultWeight())

        Row(GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
          Spacer(GlanceModifier.defaultWeight())
          TransportButton(
              icon = R.drawable.ic_widget_previous,
              contentDescription = "Previous",
              size = 22.dp,
              tint = Color(data.foregroundColor),
              action = actionRunCallback<SkipToPreviousAction>(),
          )
          Spacer(GlanceModifier.defaultWeight())
          PlayButton(data, size = 34.dp)
          Spacer(GlanceModifier.defaultWeight())
          TransportButton(
              icon = R.drawable.ic_widget_next,
              contentDescription = "Next",
              size = 22.dp,
              tint = Color(data.foregroundColor),
              action = actionRunCallback<SkipToNextAction>(),
          )
          Spacer(GlanceModifier.defaultWeight())
        }
      }
    }
  }

  @Composable
  private fun CoverImage(data: NowPlayingData, size: Dp, corner: Dp) {
    Box(modifier = GlanceModifier.size(size).cornerRadius(corner), contentAlignment = Alignment.Center) {
      if (data.coverBitmap != null) {
        Image(
            provider = ImageProvider(data.coverBitmap),
            contentDescription = null,
            modifier = GlanceModifier.fillMaxSize().cornerRadius(corner),
            contentScale = ContentScale.Crop,
        )
      } else {
        Image(
            provider = ImageProvider(R.drawable.ic_widget_music_note),
            contentDescription = null,
            modifier = GlanceModifier.size(size * 0.6f),
            colorFilter = ColorFilter.tint(ColorProvider(Color(data.foregroundColor))),
        )
      }
    }
  }

  @Composable
  private fun FavoriteButton(data: NowPlayingData) {
    Image(
        provider =
            ImageProvider(
                if (data.isFavorite) R.drawable.ic_widget_star_filled
                else R.drawable.ic_widget_star),
        contentDescription = "Favorite",
        modifier =
            GlanceModifier.size(18.dp)
                .clickable(onClick = actionRunCallback<ToggleFavoriteAction>()),
        colorFilter =
            ColorFilter.tint(
                ColorProvider(
                    if (data.isFavorite) Color(0xFFFF3040) else Color(data.foregroundColor))),
    )
  }

  @Composable
  private fun PlayButton(data: NowPlayingData, size: Dp) {
    TransportButton(
        icon = if (data.isPlaying) R.drawable.ic_widget_pause else R.drawable.ic_widget_play,
        contentDescription = if (data.isPlaying) "Pause" else "Play",
        size = size,
        tint = Color(data.foregroundColor),
        action = actionRunCallback<TogglePlayAction>(),
    )
  }

  @Composable
  private fun TransportButton(
      icon: Int,
      contentDescription: String,
      size: Dp,
      tint: Color,
      action: Action,
  ) {
    Image(
        provider = ImageProvider(icon),
        contentDescription = contentDescription,
        modifier = GlanceModifier.size(size).clickable(onClick = action),
        colorFilter = ColorFilter.tint(ColorProvider(tint)),
    )
  }

  @Composable
  private fun WidgetDivider(foregroundColor: Int) {
    Box(
        GlanceModifier.fillMaxWidth()
            .height(1.dp)
            .background(ColorProvider(Color(foregroundColor).copy(alpha = 0.5f)))) {}
  }
}

@Composable
internal fun LyricsContent(data: NowPlayingData, fontSize: Float) {
  val size = LocalSize.current

  val lineHeight = fontSize + 6f
  var visibleCount = (size.height.value / lineHeight).toInt().coerceAtLeast(1)
  if (visibleCount % 2 == 0) visibleCount += 1
  // RemoteViews limits each container to 10 children on API < 31
  if (visibleCount > 9) visibleCount = 9

  val halfCount = visibleCount / 2
  val start = data.lyricsIndex - halfCount

  Column(
      GlanceModifier.fillMaxSize(),
      horizontalAlignment = Alignment.CenterHorizontally,
      verticalAlignment = Alignment.CenterVertically,
  ) {
    for (offset in 0 until visibleCount) {
      val index = start + offset
      val isCurrent = index == data.lyricsIndex
      val line = data.lyrics.getOrNull(index) ?: ""

      Text(
          line,
          maxLines = 1,
          style =
              TextStyle(
                  fontSize = (if (isCurrent) fontSize else fontSize - 3f).sp,
                  fontWeight = if (isCurrent) FontWeight.Bold else FontWeight.Medium,
                  color =
                      ColorProvider(
                          Color(data.foregroundColor).copy(alpha = if (isCurrent) 1.0f else 0.5f)),
                  textAlign = TextAlign.Center,
              ),
          modifier = GlanceModifier.fillMaxWidth(),
      )
    }
  }
}
