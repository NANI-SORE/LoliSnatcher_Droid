package com.noaisu.loliSnatcher

import android.Manifest
import android.app.*
import android.app.job.*
import android.content.*
import android.content.pm.PackageManager
import android.net.NetworkRequest
import android.net.NetworkCapabilities
import android.os.*
import android.text.format.Formatter
import androidx.core.app.NotificationCompat
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import java.util.Locale

/** One process-wide worker. Activities only attach a command endpoint. */
object DownloadHost {
    const val JOB = 7401
    const val NOTIFICATION = 7402
    private const val CHANNEL = "durable_downloads"
    private const val ALERTS = "download_attention"
    private var engine: FlutterEngine? = null
    private var worker: MethodChannel? = null
    private var ready = false
    private var desiredRunning = false
    private var completion: (() -> Unit)? = null
    private var owner: Any? = null
    private var wake: PowerManager.WakeLock? = null
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private var lastNotification = 0L
    private var summary: Map<*, *> = emptyMap<Any, Any>()
    private var pendingOpen: Map<String, String>? = null
    fun openFromIntent(intent: Intent?) {
        if (intent?.getBooleanExtra("downloads", false) == true) {
            pendingOpen = mapOf("batchId" to (intent.getStringExtra("downloadBatch") ?: ""))
            intent.removeExtra("downloads")
        }
    }

    fun root(context: Context) = File(context.noBackupFilesDir, "downloads").apply { mkdirs() }
    private fun prefs(context: Context) = context.getSharedPreferences("download_execution", Context.MODE_PRIVATE)

    fun attach(context: Context, flutterEngine: FlutterEngine) {
        val app = context.applicationContext
        channels(app)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lolisnatcher/downloads").setMethodCallHandler { call, result ->
            when (call.method) {
                "runtimeDirectory" -> result.success(root(app).absolutePath)
                "notificationLocale" -> {
                    prefs(app).edit().putString("notificationLocale", call.arguments as? String).apply()
                    channels(app)
                    if (desiredRunning) {
                        try { app.getSystemService(NotificationManager::class.java).notify(NOTIFICATION, notification(app)) }
                        catch (_: SecurityException) {}
                    }
                    result.success(null)
                }
                "cookieGeneration" -> {
                    prefs(app).edit().putString("cookieGeneration", call.arguments as? String).apply()
                    result.success(null)
                }
                "cookies" -> {
                    val url = call.arguments as? String ?: ""
                    try { result.success(android.webkit.CookieManager.getInstance().getCookie(url) ?: "") }
                    catch (_: Exception) { result.error("authentication", "The system cookie store is unavailable", null) }
                }
                "setCookies" -> {
                    val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                    if (args["generation"] != prefs(app).getString("cookieGeneration", null)) result.success(false)
                    else {
                        var replied = false
                        fun failed() {
                            if (!replied) { replied = true; result.error("authentication", "The system cookie store is unavailable", null) }
                        }
                        try {
                        val cookies = args["cookies"] as? List<*> ?: emptyList<Any>()
                        val manager = android.webkit.CookieManager.getInstance()
                        var remaining = cookies.size
                        if (remaining == 0) result.success(true)
                        else for (cookie in cookies) manager.setCookie(args["url"] as String, cookie as String) {
                            remaining--
                            if (remaining == 0 && !replied) {
                                try { manager.flush(); replied = true; result.success(true) }
                                catch (_: Exception) { failed() }
                            }
                        }
                        } catch (_: Exception) { failed() }
                    }
                }
                "consumeOpen" -> { result.success(pendingOpen); pendingOpen = null }
                "start" -> result.success(schedule(app))
                "executionState" -> result.success(executionState(app))
                "workerReady" -> {
                    if (engine !== flutterEngine) { result.success(false); return@setMethodCallHandler }
                    ready = true
                    result.success(desiredRunning)
                }
                "workerUnavailable" -> {
                    if (engine === flutterEngine) {
                        stop(app, true)
                        // A failed entrypoint cannot respond to resume. Recreate
                        // it on the next explicit start, after replying here.
                        main.post { discardFailedEngine(flutterEngine) }
                    }
                    result.success(null)
                }
                "refresh" -> { if (ready && desiredRunning) worker?.invokeMethod("resume", null); result.success(null) }
                "quiesce" -> {
                    stop(app, false)
                    if (engine == null) result.success(null)
                    else if (!ready) result.error("workerStarting", "The download worker is still starting. Retry the restore.", null)
                    else worker?.invokeMethod("quiesce", null, result)
                }
                "progress" -> {
                    if (engine !== flutterEngine || !ready) { result.success(null); return@setMethodCallHandler }
                    summary = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                    progress(app)
                    result.success(null)
                }
                "alert" -> {
                    val values = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                    alert(app, values["id"]?.toString() ?: "downloads", values["complete"] == true,
                        values["batchId"]?.toString(), values["progress"] as? Map<*, *>)
                    result.success(null)
                }
                "hasLocalNetworkPermission" -> result.success(Build.VERSION.SDK_INT < 37 ||
                    app.checkSelfPermission(Manifest.permission.ACCESS_LOCAL_NETWORK) == PackageManager.PERMISSION_GRANTED)
                "scan" -> {
                    val path = call.argument<String>("path")
                    if (path != null) android.media.MediaScannerConnection.scanFile(app, arrayOf(path), null, null)
                    result.success(null)
                }
                "exists", "publish" -> {
                    val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                    io.execute {
                        try {
                            val publisher = DownloadPublisher(app)
                            val value: Any = if (call.method == "exists") publisher.exists(args) else publisher.publish(args)
                            main.post { result.success(value) }
                        } catch (error: Exception) {
                            val code = if (error.message == "publicationAmbiguous") "publicationAmbiguous" else "storage"
                            main.post { result.error(code, "Storage access or publication needs attention", null) }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    fun schedule(context: Context): String {
        if (desiredRunning) {
            if (ready) worker?.invokeMethod("wake", null)
            return if (ready) "running" else "starting"
        }
        summary = emptyMap<Any, Any>()
        lastNotification = 0L
        // Called only for a foreground user's enqueue/resume action. Let the
        // platform decide eligibility, including permission-dialog transitions
        // and allowed launch exemptions; Activity.onPause is too restrictive.
        return try {
            if (Build.VERSION.SDK_INT >= 34) {
                val scheduler = context.getSystemService(JobScheduler::class.java)
                // This is a fresh user request, not an automatic retry. Replace
                // an older pending job so its system backoff cannot hide new work.
                // Running jobs are handled above and retain the same executor.
                val network = NetworkRequest.Builder()
                    .removeCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
                    .build()
                val job = JobInfo.Builder(JOB, ComponentName(context, DownloadJob::class.java))
                    .setUserInitiated(true).setPersisted(true)
                    .setRequiredNetwork(network)
                    .build()
                if (scheduler.schedule(job) != JobScheduler.RESULT_SUCCESS) throw IllegalStateException()
            } else {
                val intent = Intent(context, DownloadService::class.java)
                if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent) else context.startService(intent)
            }
            prefs(context).edit().putBoolean("resumeRequired", false).apply()
            "scheduled"
        } catch (_: Exception) {
            prefs(context).edit().putBoolean("resumeRequired", true).apply()
            "resumeRequired"
        }
    }

    private fun executionState(context: Context): String {
        if (desiredRunning) return if (ready) "running" else "starting"
        if (prefs(context).getBoolean("resumeRequired", false)) return "resumeRequired"
        if (Build.VERSION.SDK_INT >= 34) {
            val scheduler = context.getSystemService(JobScheduler::class.java)
            if (scheduler.getPendingJob(JOB) != null) {
                return if (scheduler.getPendingJobReason(JOB) == JobScheduler.PENDING_JOB_REASON_CONSTRAINT_CONNECTIVITY)
                    "waitingNetwork" else "waitingSystem"
            }
        }
        return "idle"
    }

    private fun discardFailedEngine(failed: FlutterEngine) {
        if (engine !== failed) return
        ready = false
        worker = null
        engine = null
        failed.destroy()
    }

    fun begin(context: Context, token: Any, finish: () -> Unit) {
        owner = token
        completion = finish
        desiredRunning = true
        // Leave a durable recovery hint if the process disappears before stop.
        prefs(context).edit().putBoolean("resumeRequired", true).apply()
        if (Build.VERSION.SDK_INT < 34) {
            wake = (context.getSystemService(Context.POWER_SERVICE) as PowerManager)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "LoliSnatcher:downloads").apply {
                    setReferenceCounted(false); acquire(10 * 60 * 1000L)
                }
        }
        if (engine == null) {
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(context)
            loader.ensureInitializationComplete(context, null)
            val created = FlutterEngine(context.applicationContext)
            engine = created
            attach(context, created)
            worker = MethodChannel(created.dartExecutor.binaryMessenger, "lolisnatcher/downloads/worker")
            created.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "downloadMain"))
            main.postDelayed({
                if (engine === created && !ready) {
                    stop(context, true)
                    discardFailedEngine(created)
                }
            }, 60_000L)
        } else if (ready) worker?.invokeMethod("resume", null)
    }

    fun stopped(context: Context, token: Any) {
        if (owner !== token) return
        completion = null
        stop(context, true)
    }

    fun stop(context: Context, resumeRequired: Boolean) {
        desiredRunning = false
        owner = null
        if (ready) worker?.invokeMethod("suspend", null)
        if (wake?.isHeld == true) wake?.release()
        wake = null
        prefs(context).edit().putBoolean("resumeRequired", resumeRequired).apply()
        val finish = completion
        completion = null
        finish?.invoke()
    }

    private fun progress(context: Context) {
        if (!desiredRunning) return
        val pending = listOf("queued", "prepared", "transferring", "finalizing", "waitingNetwork", "waitingRate", "discovery")
            .sumOf { (summary[it] as? Number)?.toInt() ?: 0 }
        if (SystemClock.elapsedRealtime() - lastNotification > 2000) {
            lastNotification = SystemClock.elapsedRealtime()
            try { context.getSystemService(NotificationManager::class.java).notify(NOTIFICATION, notification(context)) } catch (_: SecurityException) {}
            if (wake != null) wake?.acquire(10 * 60 * 1000L)
        }
        if (pending == 0) stop(context, false)
    }

    private fun notificationContext(context: Context): Context {
        val tag = prefs(context).getString("notificationLocale", null) ?: return context
        val configuration = android.content.res.Configuration(context.resources.configuration)
        configuration.setLocale(Locale.forLanguageTag(tag))
        return context.createConfigurationContext(configuration)
    }

    private fun channels(context: Context) {
        if (Build.VERSION.SDK_INT >= 26) {
            val strings = notificationContext(context)
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(NotificationChannel(CHANNEL, strings.getString(R.string.download_notification_progress_channel), NotificationManager.IMPORTANCE_LOW))
            manager.createNotificationChannel(NotificationChannel(ALERTS, strings.getString(R.string.download_notification_attention_channel), NotificationManager.IMPORTANCE_DEFAULT))
        }
    }

    private fun openIntent(context: Context, batchId: String? = null): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("downloads", true)
            putExtra("downloadBatch", batchId)
        }
        return PendingIntent.getActivity(context, batchId?.hashCode() ?: 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    fun notification(context: Context): Notification {
        channels(context)
        val strings = notificationContext(context)
        val progress = summary["notificationProgress"] as? Map<*, *> ?: emptyMap<Any, Any>()
        fun count(key: String) = ((progress[key] as? Number)?.toLong() ?: 0L).coerceAtLeast(0L)
        val total = count("total")
        val done = count("done").coerceAtMost(total)
        val active = count("active")
        val received = count("received")
        val bytesTotal = count("bytesTotal")
        val discovering = ((summary["discovery"] as? Number)?.toInt() ?: 0) > 0
        val knownSize = bytesTotal > 0 && count("unknownSize") == 0L
        val percent = if (knownSize) (received.toDouble() / bytesTotal * 100).toInt().coerceIn(0, 100) else 0
        val files = strings.getString(R.string.download_notification_progress)
            .replace("{done}", done.toString()).replace("{total}", total.toString())
        val current = when {
            active > 0 && knownSize -> strings.getString(R.string.download_notification_transfer_progress)
                .replace("{percent}", percent.toString())
                .replace("{received}", Formatter.formatShortFileSize(strings, received))
                .replace("{total}", Formatter.formatShortFileSize(strings, bytesTotal))
            active > 0 -> strings.getString(R.string.download_notification_transfer_unknown)
                .replace("{received}", Formatter.formatShortFileSize(strings, received))
            count("saving") > 0 -> strings.getString(R.string.download_notification_saving)
            ((summary["waitingNetwork"] as? Number)?.toInt() ?: 0) > 0 -> strings.getString(R.string.download_notification_waiting_network)
            ((summary["waitingRate"] as? Number)?.toInt() ?: 0) > 0 -> strings.getString(R.string.download_notification_waiting_rate)
            else -> null
        }
        val discovery = if (discovering) strings.getString(R.string.download_notification_discovery_progress)
            .replace("{selected}", (summary["discoverySelected"] ?: 0).toString())
            .replace("{requested}", (summary["discoveryRequested"] ?: 0).toString()) else null
        val text = current ?: discovery ?: if (total > 0) files else strings.getString(R.string.download_notification_in_progress)
        // Bytes describe the current transfers; the file counter describes the batches.
        val indeterminate = when {
            active > 0 -> !knownSize
            count("saving") > 0 || discovering -> true
            else -> total == 0L
        }
        val fraction = if (active > 0 && knownSize) received.toDouble() / bytesTotal
            else if (total > 0) done.toDouble() / total else 0.0
        val bar = (fraction.coerceIn(0.0, 1.0) * 1000).toInt()
        val batches = strings.getString(R.string.download_notification_batches).replace("{count}", count("batches").toString())
        val details = listOfNotNull(if (total > 0) files else null, current, discovery,
            if (count("batches") > 1) batches else null).joinToString("\n")
        val batchId = if (count("batches") == 1L) progress["batchId"] as? String else null
        val builder = NotificationCompat.Builder(context, CHANNEL).setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(strings.getString(R.string.download_notification_title))
            .setContentText(text).setSubText(if (total > 0) files else null)
            .setStyle(NotificationCompat.BigTextStyle().bigText(details.ifEmpty { text }))
            .setProgress(1000, bar, indeterminate).setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setShowWhen(false)
            .setOngoing(true).setOnlyAlertOnce(true).setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setContentIntent(openIntent(context, batchId))
            .setPublicVersion(NotificationCompat.Builder(context, CHANNEL)
                .setSmallIcon(android.R.drawable.stat_sys_download)
                .setContentTitle(strings.getString(R.string.download_notification_in_progress))
                .setContentText(text).setProgress(1000, bar, indeterminate).setShowWhen(false).build())
        for (command in listOf("pause", "cancel")) {
            val intent = Intent(context, DownloadActionReceiver::class.java).putExtra("command", command)
            val action = PendingIntent.getBroadcast(context, command.hashCode(), intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            builder.addAction(0, strings.getString(if (command == "pause")
                R.string.download_notification_pause else R.string.download_notification_cancel), action)
        }
        return builder.build()
    }

    private fun alert(context: Context, id: String, complete: Boolean, batchId: String?, progress: Map<*, *>?) {
        channels(context)
        val strings = notificationContext(context)
        val action = strings.getString(if (complete) R.string.download_notification_complete_body else R.string.download_notification_attention_body)
        val counts = progress?.let { values ->
            var text = strings.getString(R.string.download_notification_result_progress)
            for (key in listOf("saved", "skipped", "failed")) {
                text = text.replace("{$key}", ((values[key] as? Number)?.toLong() ?: 0L).coerceAtLeast(0L).toString())
            }
            text
        }
        val notification = NotificationCompat.Builder(context, ALERTS)
            .setSmallIcon(if (complete) android.R.drawable.stat_sys_download_done else android.R.drawable.stat_notify_error)
            .setContentTitle(strings.getString(if (complete) R.string.download_notification_complete_title else R.string.download_notification_attention_title))
            .setContentText(counts ?: action)
            .setStyle(NotificationCompat.BigTextStyle().bigText(listOfNotNull(counts, action).joinToString("\n")))
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE).setAutoCancel(true).setGroup("download_results")
            .setContentIntent(openIntent(context, batchId)).build()
        try { context.getSystemService(NotificationManager::class.java).notify(id.hashCode(), notification) } catch (_: SecurityException) {}
    }

    fun action(context: Context, command: String, done: () -> Unit) {
        io.execute {
            try {
                val file = File(root(context), "downloads.db")
                if (file.exists()) {
                    android.database.sqlite.SQLiteDatabase.openDatabase(file.path, null, android.database.sqlite.SQLiteDatabase.OPEN_READWRITE).use { db ->
                        db.beginTransaction()
                        try {
                            val state = if (command == "cancel") "cancelled" else "paused"
                            db.execSQL("UPDATE batches SET state = ?, generation = generation + 1", arrayOf(state))
                            db.execSQL("UPDATE tasks SET state = ?, generation = generation + 1 WHERE state NOT IN ('completed','skipped','cancelled','finalizing')", arrayOf(state))
                            db.setTransactionSuccessful()
                        } finally { db.endTransaction() }
                    }
                }
            } finally {
                main.post {
                    // Finalization may still be running. Its durable journal is
                    // reconciled on the next start even if Android kills us now.
                    stop(context, false)
                    context.getSystemService(JobScheduler::class.java).cancel(JOB)
                    done()
                }
            }
        }
    }
}

class DownloadJob : JobService() {
    private var current: JobParameters? = null
    override fun onStartJob(params: JobParameters): Boolean {
        current = params
        if (Build.VERSION.SDK_INT >= 34) setNotification(params, DownloadHost.NOTIFICATION,
            DownloadHost.notification(this), JOB_END_NOTIFICATION_POLICY_REMOVE)
        DownloadHost.begin(applicationContext, params) {
            if (current === params) { current = null; jobFinished(params, false) }
        }
        return true
    }
    override fun onStopJob(params: JobParameters): Boolean {
        if (current === params) current = null
        DownloadHost.stopped(applicationContext, params)
        return Build.VERSION.SDK_INT < 31 || (params.stopReason != JobParameters.STOP_REASON_USER &&
            params.stopReason != JobParameters.STOP_REASON_CANCELLED_BY_APP)
    }
}

class DownloadService : Service() {
    override fun onBind(intent: Intent?) = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(DownloadHost.NOTIFICATION, DownloadHost.notification(this))
        DownloadHost.begin(applicationContext, this) { stopForeground(STOP_FOREGROUND_REMOVE); stopSelf() }
        return START_NOT_STICKY
    }
    override fun onDestroy() {
        DownloadHost.stopped(applicationContext, this)
        super.onDestroy()
    }
}

class DownloadActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val command = intent.getStringExtra("command") ?: return
        if (command != "pause" && command != "cancel") return
        val pending = goAsync()
        DownloadHost.action(context.applicationContext, command) { pending.finish() }
    }
}
