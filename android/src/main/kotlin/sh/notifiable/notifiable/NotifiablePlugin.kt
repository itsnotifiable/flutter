package sh.notifiable.notifiable

import android.Manifest
import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.util.Locale
import java.util.TimeZone

class NotifiablePlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {
    private lateinit var channel: MethodChannel
    private var applicationContext: Context? = null
    private var activity: Activity? = null
    private var binding: ActivityPluginBinding? = null
    private var pendingPermission: MethodChannel.Result? = null
    private var registrationError: String? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "sh.notifiable/notifiable")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        applicationContext = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        this.binding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        binding?.removeRequestPermissionsResultListener(this)
        activity = null
        binding = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        onDetachedFromActivityForConfigChanges()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "permissionStatus" -> {
                prepareDefaultChannel()
                result.success(permissionStatus())
            }
            "requestPermission" -> requestPermission(result)
            "getToken" -> token(result)
            "registrationError" -> result.success(registrationError)
            "deviceProfile" -> result.success(deviceProfile())
            "openUrl" -> {
                openUrl(call.arguments as? String)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != requestCodePermission) {
            return false
        }

        markAsked()
        pendingPermission?.success(permissionStatus())
        pendingPermission = null
        return true
    }

    private fun requestPermission(result: MethodChannel.Result) {
        val context = applicationContext

        if (context == null) {
            result.success("not_determined")
            return
        }

        prepareDefaultChannel()

        if (permissionStatus() == "granted") {
            result.success("granted")
            return
        }

        val current = activity

        if (Build.VERSION.SDK_INT < 33) {
            if (current != null && permissionStatus() == "denied") {
                openNotificationSettings(current)
            }
            result.success(permissionStatus())
            return
        }

        if (current == null) {
            result.success(permissionStatus())
            return
        }

        if (hasPostNotificationsPermission(context) && !notificationsEnabled(context)) {
            openNotificationSettings(current)
            result.success("denied")
            return
        }

        val status = permissionStatus()
        if (
            status == "denied" &&
            !ActivityCompat.shouldShowRequestPermissionRationale(
                current,
                Manifest.permission.POST_NOTIFICATIONS,
            )
        ) {
            openNotificationSettings(current)
            result.success("denied")
            return
        }

        val previous = pendingPermission
        if (previous != null) {
            previous.success(permissionStatus())
            pendingPermission = null
        }

        pendingPermission = result
        ActivityCompat.requestPermissions(
            current,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            requestCodePermission,
        )
    }

    private fun permissionStatus(): String {
        val context = applicationContext ?: return "not_determined"

        if (Build.VERSION.SDK_INT < 33) {
            return if (notificationsEnabled(context)) {
                "granted"
            } else {
                "denied"
            }
        }

        if (hasPostNotificationsPermission(context) && notificationsEnabled(context)) {
            return "granted"
        }

        if (hasPostNotificationsPermission(context) && !notificationsEnabled(context)) {
            return "denied"
        }

        val asked = context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
            .getBoolean("asked", false)
        return if (asked) "denied" else "not_determined"
    }

    private fun hasPostNotificationsPermission(context: Context): Boolean {
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun notificationsEnabled(context: Context): Boolean {
        return NotificationManagerCompat.from(context).areNotificationsEnabled()
    }

    private fun prepareDefaultChannel() {
        if (Build.VERSION.SDK_INT < 26) {
            return
        }

        val context = applicationContext ?: return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(defaultChannelId) != null) {
            return
        }

        manager.createNotificationChannel(
            NotificationChannel(
                defaultChannelId,
                defaultChannelName,
                NotificationManager.IMPORTANCE_DEFAULT,
            ),
        )
    }

    private fun openNotificationSettings(activity: Activity) {
        val context = applicationContext ?: return
        val intent = if (Build.VERSION.SDK_INT >= 26) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
            }
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.fromParts("package", context.packageName, null)
            }
        }

        try {
            activity.startActivity(intent)
        } catch (_: Exception) {
            try {
                context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            } catch (_: Exception) {
                return
            }
        }
    }

    private fun token(result: MethodChannel.Result) {
        val context = applicationContext

        if (context == null) {
            result.success(null)
            return
        }

        try {
            if (FirebaseApp.getApps(context).isEmpty()) {
                FirebaseApp.initializeApp(context)
            }
        } catch (error: Exception) {
            registrationError = error.message
            result.success(null)
            return
        }

        if (FirebaseApp.getApps(context).isEmpty()) {
            result.success(null)
            return
        }

        FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
            if (!task.isSuccessful) {
                registrationError = task.exception?.message
                result.success(null)
                return@addOnCompleteListener
            }

            val value = task.result?.trim().orEmpty()
            result.success(if (value.isEmpty()) null else value)
        }
    }

    private fun deviceProfile(): Map<String, Any?> {
        val context = applicationContext ?: return emptyMap()
        val version = try {
            context.packageManager.getPackageInfo(context.packageName, 0).versionName
        } catch (_: Exception) {
            null
        }

        return mapOf(
            "osVersion" to Build.VERSION.RELEASE,
            "locale" to Locale.getDefault().toLanguageTag(),
            "timezone" to TimeZone.getDefault().id,
            "model" to Build.MODEL,
            "manufacturer" to Build.MANUFACTURER,
            "appVersion" to version,
            "applicationId" to context.packageName,
            "isSimulator" to false,
        )
    }

    private fun openUrl(url: String?) {
        if (url.isNullOrEmpty()) {
            return
        }

        val context = activity ?: applicationContext ?: return
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))

        if (context !is Activity) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        try {
            context.startActivity(intent)
        } catch (_: Exception) {
        }
    }

    private fun markAsked() {
        applicationContext
            ?.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
            ?.edit()
            ?.putBoolean("asked", true)
            ?.apply()
    }

    companion object {
        private const val requestCodePermission = 41018
        private const val preferencesName = "notifiable.push"
        private const val defaultChannelId = "default"
        private const val defaultChannelName = "Default"
    }
}
