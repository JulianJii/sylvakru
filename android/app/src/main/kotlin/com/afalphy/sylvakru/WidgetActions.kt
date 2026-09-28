package com.afalphy.sylvakru

import android.content.ComponentName
import android.content.Context
import android.support.v4.media.MediaBrowserCompat
import android.support.v4.media.session.MediaControllerCompat
import androidx.glance.GlanceId
import androidx.glance.action.ActionParameters
import androidx.glance.appwidget.action.ActionCallback
import es.antonborri.home_widget.HomeWidgetPlugin
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

private enum class WidgetPlaybackAction {
  TOGGLE_PLAY,
  SKIP_TO_PREVIOUS,
  TOGGLE_FAVORITE,
  SKIP_TO_NEXT,
}

/**
 * Controls playback by binding to the audio_service session and issuing transport controls. The
 * service keeps the process alive while media is loaded, so this works without opening the app.
 *
 * MediaBrowserCompat must be created on a thread with a Looper, while Glance runs action callbacks
 * on a worker thread, so this hops to the main thread first.
 */
private suspend fun triggerPlaybackAction(context: Context, action: WidgetPlaybackAction) =
    withContext(Dispatchers.Main) {
      val appContext = context.applicationContext
      var browser: MediaBrowserCompat? = null

      val callback =
          object : MediaBrowserCompat.ConnectionCallback() {
            override fun onConnected() {
              try {
                val controller = MediaControllerCompat(appContext, browser!!.sessionToken)
                val controls = controller.transportControls
                val playing = HomeWidgetPlugin.getData(appContext).getBoolean("is_playing", false)

                when (action) {
                  WidgetPlaybackAction.TOGGLE_PLAY ->
                      if (playing) controls.pause() else controls.play()
                  WidgetPlaybackAction.SKIP_TO_PREVIOUS -> controls.skipToPrevious()
                  WidgetPlaybackAction.SKIP_TO_NEXT -> controls.skipToNext()
                  WidgetPlaybackAction.TOGGLE_FAVORITE ->
                      controls.sendCustomAction("toggleFavorite", null)
                }
              } catch (_: Exception) {
              } finally {
                runCatching { browser?.disconnect() }
              }
            }

            override fun onConnectionFailed() {
              runCatching { browser?.disconnect() }
            }
          }

      browser =
          MediaBrowserCompat(
              appContext,
              ComponentName(appContext, "com.ryanheise.audioservice.AudioService"),
              callback,
              null,
          )
      browser.connect()
    }

class TogglePlayAction : ActionCallback {
  override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
    triggerPlaybackAction(context, WidgetPlaybackAction.TOGGLE_PLAY)
  }
}

class SkipToPreviousAction : ActionCallback {
  override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
    triggerPlaybackAction(context, WidgetPlaybackAction.SKIP_TO_PREVIOUS)
  }
}

class SkipToNextAction : ActionCallback {
  override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
    triggerPlaybackAction(context, WidgetPlaybackAction.SKIP_TO_NEXT)
  }
}

class ToggleFavoriteAction : ActionCallback {
  override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
    triggerPlaybackAction(context, WidgetPlaybackAction.TOGGLE_FAVORITE)
  }
}
