package com.vespermovies.app

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.VideoSize
import androidx.media3.common.text.CueGroup
import androidx.media3.database.StandaloneDatabaseProvider
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.cache.CacheDataSource
import androidx.media3.datasource.cache.LeastRecentlyUsedCacheEvictor
import androidx.media3.datasource.cache.SimpleCache
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.io.File
import java.net.InetAddress
import java.util.concurrent.TimeUnit
import okhttp3.Dns
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.dnsoverhttps.DnsOverHttps

object VesperNet {
    private val bootstrap: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(4, TimeUnit.SECONDS)
        .callTimeout(6, TimeUnit.SECONDS)
        .build()

    private val cloudflare: DnsOverHttps = DnsOverHttps.Builder()
        .client(bootstrap)
        .url("https://1.1.1.1/dns-query".toHttpUrl())
        .bootstrapDnsHosts(InetAddress.getByName("1.1.1.1"), InetAddress.getByName("1.0.0.1"))
        .includeIPv6(false)
        .build()

    private val google: DnsOverHttps = DnsOverHttps.Builder()
        .client(bootstrap)
        .url("https://8.8.8.8/dns-query".toHttpUrl())
        .bootstrapDnsHosts(InetAddress.getByName("8.8.8.8"), InetAddress.getByName("8.8.4.4"))
        .includeIPv6(false)
        .build()

    private val secureDns: Dns = object : Dns {
        override fun lookup(hostname: String): List<InetAddress> {
            for (resolver in listOf(cloudflare, google)) {
                try {
                    val found = resolver.lookup(hostname)
                    if (found.isNotEmpty()) return found
                } catch (_: Exception) {
                }
            }
            return Dns.SYSTEM.lookup(hostname)
        }
    }

    private val base: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .followRedirects(true)
        .followSslRedirects(true)
        .retryOnConnectionFailure(true)
        .build()

    private val secureClient: OkHttpClient by lazy { base.newBuilder().dns(secureDns).build() }

    fun client(secure: Boolean): OkHttpClient = if (secure) secureClient else base

    @Volatile
    private var cache: SimpleCache? = null

    fun cache(context: Context): SimpleCache {
        cache?.let { return it }
        synchronized(this) {
            cache?.let { return it }
            val dir = File(context.cacheDir, "exo-stream-cache")
            val created = SimpleCache(
                dir,
                LeastRecentlyUsedCacheEvictor(1024L * 1024L * 1024L),
                StandaloneDatabaseProvider(context),
            )
            cache = created
            return created
        }
    }
}

class VesperExoPlayer(
    private val context: Context,
    messenger: BinaryMessenger,
    textures: TextureRegistry,
) : Player.Listener, TextureRegistry.SurfaceProducer.Callback {

    private val producer: TextureRegistry.SurfaceProducer = textures.createSurfaceProducer()
    val id: Long = producer.id()

    private val handler = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private val events = EventChannel(messenger, "vesper/exo/$id")

    private val trackSelector = DefaultTrackSelector(context)

    private val player: ExoPlayer = ExoPlayer.Builder(context)
        .setTrackSelector(trackSelector)
        .setLoadControl(
            DefaultLoadControl.Builder()
                .setBufferDurationsMs(60_000, 600_000, 3_000, 10_000)
                .setTargetBufferBytes(160 * 1024 * 1024)
                .setPrioritizeTimeOverSizeThresholds(false)
                .setBackBuffer(30_000, true)
                .build(),
        )
        .setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(C.USAGE_MEDIA)
                .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
                .build(),
            true,
        )
        .setHandleAudioBecomingNoisy(true)
        .build()

    private val ticker = object : Runnable {
        override fun run() {
            sendState()
            handler.postDelayed(this, 250)
        }
    }

    init {
        events.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                sink = events
                sendState()
                sendTracks(player.currentTracks)
            }

            override fun onCancel(arguments: Any?) {
                sink = null
            }
        })
        producer.setCallback(this)
        player.addListener(this)
        player.setVideoSurface(producer.surface)
        handler.post(ticker)
    }

    override fun onSurfaceAvailable() {
        player.setVideoSurface(producer.surface)
    }

    override fun onSurfaceCleanup() {
        player.setVideoSurface(null)
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "open" -> {
                    open(call)
                    result.success(null)
                }
                "play" -> {
                    player.play()
                    result.success(null)
                }
                "pause" -> {
                    player.pause()
                    result.success(null)
                }
                "seek" -> {
                    val ms = (call.argument<Number>("ms") ?: 0).toLong()
                    player.seekTo(ms.coerceAtLeast(0))
                    result.success(null)
                }
                "volume" -> {
                    val value = (call.argument<Number>("value") ?: 1.0).toFloat()
                    player.volume = value.coerceIn(0f, 1f)
                    result.success(null)
                }
                "rate" -> {
                    val value = (call.argument<Number>("value") ?: 1.0).toFloat()
                    player.playbackParameters = PlaybackParameters(value.coerceIn(0.25f, 3f))
                    result.success(null)
                }
                "maxHeight" -> {
                    applyMaxHeight(call.argument<Number>("value")?.toInt() ?: 0)
                    result.success(null)
                }
                "select" -> {
                    select(call.argument<String>("type") ?: "", call.argument<String>("id") ?: "auto")
                    result.success(null)
                }
                "stop" -> {
                    player.stop()
                    player.clearMediaItems()
                    result.success(null)
                }
                "dispose" -> {
                    release()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            result.error("exo_error", error.message, null)
        }
    }

    private fun open(call: MethodCall) {
        val url = call.argument<String>("url") ?: throw IllegalArgumentException("url missing")
        val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()
        val startMs = (call.argument<Number>("startMs") ?: 0).toLong()
        val secureDns = call.argument<Boolean>("secureDns") ?: true
        val subtitles = call.argument<List<Map<String, String>>>("subtitles") ?: emptyList()
        applyMaxHeight(call.argument<Number>("maxHeight")?.toInt() ?: 0)

        val userAgent = headers.entries.firstOrNull { it.key.equals("User-Agent", true) }?.value
        val requestHeaders = headers.filterKeys { !it.equals("User-Agent", true) }

        val http = OkHttpDataSource.Factory(VesperNet.client(secureDns))
            .setDefaultRequestProperties(requestHeaders)
        if (userAgent != null) http.setUserAgent(userAgent)

        val cached = CacheDataSource.Factory()
            .setCache(VesperNet.cache(context))
            .setUpstreamDataSourceFactory(http)
            .setFlags(CacheDataSource.FLAG_IGNORE_CACHE_ON_ERROR)

        val dataSource = DefaultDataSource.Factory(context, cached)

        val lower = url.lowercase()
        val mime = when {
            lower.contains(".m3u8") || lower.startsWith("data:application/vnd.apple.mpegurl") ->
                MimeTypes.APPLICATION_M3U8
            lower.contains(".mpd") -> MimeTypes.APPLICATION_MPD
            else -> null
        }

        val subtitleConfigs = subtitles.mapIndexedNotNull { index, entry ->
            val subUrl = entry["url"] ?: return@mapIndexedNotNull null
            MediaItem.SubtitleConfiguration.Builder(Uri.parse(subUrl))
                .setId("ext:$index")
                .setMimeType(subtitleMime(subUrl))
                .setLabel(entry["name"] ?: "Subtitle ${index + 1}")
                .setSelectionFlags(0)
                .build()
        }

        val item = MediaItem.Builder()
            .setUri(url)
            .apply { if (mime != null) setMimeType(mime) }
            .setSubtitleConfigurations(subtitleConfigs)
            .build()

        val source = DefaultMediaSourceFactory(dataSource).createMediaSource(item)
        player.setMediaSource(source, startMs.coerceAtLeast(0))
        player.playWhenReady = call.argument<Boolean>("play") ?: false
        player.prepare()
    }

    private fun subtitleMime(url: String): String {
        val path = url.substringBefore('?').lowercase()
        return when {
            path.endsWith(".vtt") -> MimeTypes.TEXT_VTT
            path.endsWith(".ass") || path.endsWith(".ssa") -> MimeTypes.TEXT_SSA
            path.endsWith(".ttml") || path.endsWith(".xml") -> MimeTypes.APPLICATION_TTML
            else -> MimeTypes.APPLICATION_SUBRIP
        }
    }

    private fun applyMaxHeight(height: Int) {
        val builder = player.trackSelectionParameters.buildUpon()
        if (height > 0) {
            builder.setMaxVideoSize(Int.MAX_VALUE, height)
        } else {
            builder.clearVideoSizeConstraints()
        }
        player.trackSelectionParameters = builder.build()
    }

    private fun trackType(type: String): Int = when (type) {
        "audio" -> C.TRACK_TYPE_AUDIO
        "video" -> C.TRACK_TYPE_VIDEO
        else -> C.TRACK_TYPE_TEXT
    }

    private fun trackId(groupIndex: Int, trackIndex: Int, format: Format): String {
        val formatId = format.id
        return if (formatId != null && formatId.startsWith("ext:")) formatId else "$groupIndex:$trackIndex"
    }

    private fun select(type: String, id: String) {
        val trackType = trackType(type)
        val builder = player.trackSelectionParameters.buildUpon()
        when (id) {
            "no" -> builder.setTrackTypeDisabled(trackType, true)
            "auto" -> builder.clearOverridesOfType(trackType).setTrackTypeDisabled(trackType, false)
            else -> {
                val groups = player.currentTracks.groups
                for ((groupIndex, group) in groups.withIndex()) {
                    if (group.type != trackType) continue
                    for (trackIndex in 0 until group.length) {
                        if (trackId(groupIndex, trackIndex, group.getTrackFormat(trackIndex)) == id) {
                            builder.setTrackTypeDisabled(trackType, false)
                            builder.setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, trackIndex))
                        }
                    }
                }
            }
        }
        player.trackSelectionParameters = builder.build()
    }

    private fun sendState() {
        val out = sink ?: return
        val duration = player.duration
        out.success(
            mapOf(
                "type" to "state",
                "position" to player.currentPosition,
                "duration" to if (duration == C.TIME_UNSET) 0L else duration,
                "buffered" to player.bufferedPosition,
                "playing" to player.isPlaying,
                "buffering" to (player.playbackState == Player.STATE_BUFFERING),
                "completed" to (player.playbackState == Player.STATE_ENDED),
                "rate" to player.playbackParameters.speed.toDouble(),
                "volume" to player.volume.toDouble(),
            ),
        )
    }

    private fun describe(format: Format): Map<String, Any?> = mapOf(
        "title" to format.label,
        "language" to format.language,
        "width" to format.width.takeIf { it > 0 },
        "height" to format.height.takeIf { it > 0 },
        "bitrate" to format.bitrate.takeIf { it > 0 },
        "codec" to (format.codecs ?: format.sampleMimeType),
        "channels" to format.channelCount.takeIf { it > 0 },
    )

    private fun sendTracks(tracks: Tracks) {
        val out = sink ?: return
        val audio = mutableListOf<Map<String, Any?>>()
        val video = mutableListOf<Map<String, Any?>>()
        val text = mutableListOf<Map<String, Any?>>()
        var selectedAudio: String? = null
        var selectedVideo: String? = null
        var selectedText: String? = null

        for ((groupIndex, group) in tracks.groups.withIndex()) {
            for (trackIndex in 0 until group.length) {
                if (!group.isTrackSupported(trackIndex)) continue
                val format = group.getTrackFormat(trackIndex)
                val id = trackId(groupIndex, trackIndex, format)
                val entry = describe(format) + ("id" to id)
                val selected = group.isTrackSelected(trackIndex)
                when (group.type) {
                    C.TRACK_TYPE_AUDIO -> {
                        audio.add(entry)
                        if (selected) selectedAudio = id
                    }
                    C.TRACK_TYPE_VIDEO -> {
                        video.add(entry)
                        if (selected) selectedVideo = id
                    }
                    C.TRACK_TYPE_TEXT -> {
                        text.add(entry)
                        if (selected) selectedText = id
                    }
                }
            }
        }

        val textDisabled = player.trackSelectionParameters.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT)
        out.success(
            mapOf(
                "type" to "tracks",
                "audio" to audio,
                "video" to video,
                "subtitle" to text,
                "selectedAudio" to selectedAudio,
                "selectedVideo" to selectedVideo,
                "selectedSubtitle" to (if (textDisabled) "no" else selectedText),
            ),
        )
    }

    override fun onTracksChanged(tracks: Tracks) {
        sendTracks(tracks)
    }

    override fun onCues(cueGroup: CueGroup) {
        val text = cueGroup.cues.mapNotNull { it.text?.toString() }.joinToString("\n")
        sink?.success(mapOf("type" to "cues", "text" to text))
    }

    override fun onVideoSizeChanged(videoSize: VideoSize) {
        if (videoSize.width > 0 && videoSize.height > 0 &&
            (producer.width != videoSize.width || producer.height != videoSize.height)
        ) {
            producer.setSize(videoSize.width, videoSize.height)
            player.setVideoSurface(producer.surface)
        }
        sink?.success(
            mapOf(
                "type" to "video",
                "width" to videoSize.width,
                "height" to videoSize.height,
                "ratio" to videoSize.pixelWidthHeightRatio.toDouble(),
            ),
        )
    }

    override fun onPlaybackStateChanged(playbackState: Int) {
        sendState()
    }

    override fun onIsPlayingChanged(isPlaying: Boolean) {
        sendState()
    }

    override fun onPlayerError(error: PlaybackException) {
        val cause = error.cause?.javaClass?.simpleName ?: ""
        sink?.success(
            mapOf(
                "type" to "error",
                "code" to error.errorCodeName,
                "message" to "${error.errorCodeName} $cause".trim(),
                "fatal" to true,
            ),
        )
    }

    fun release() {
        handler.removeCallbacks(ticker)
        events.setStreamHandler(null)
        sink = null
        player.removeListener(this)
        player.release()
        producer.release()
    }
}

class VesperExoPlugin(
    private val context: Context,
    private val messenger: BinaryMessenger,
    private val textures: TextureRegistry,
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "vesper/exo")
    private val players = HashMap<Long, VesperExoPlayer>()

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "create") {
            try {
                val created = VesperExoPlayer(context, messenger, textures)
                players[created.id] = created
                result.success(created.id)
            } catch (error: Exception) {
                result.error("exo_create", error.message, null)
            }
            return
        }

        val id = call.argument<Number>("id")?.toLong()
        val target = if (id == null) null else players[id]
        if (target == null) {
            result.error("exo_missing", "no player $id", null)
            return
        }
        target.handle(call, result)
        if (call.method == "dispose") players.remove(id)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        players.values.forEach { it.release() }
        players.clear()
    }
}
