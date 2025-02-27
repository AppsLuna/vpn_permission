package com.example.vpn_permission

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry

class VpnPermissionPlugin : FlutterPlugin, MethodCallHandler, ActivityAware,
    PluginRegistry.ActivityResultListener {
    private lateinit var channel: MethodChannel
    private var activity: Activity? = null
    private var pendingResult: Result? = null
    private val vpnRequestCode = 1435

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "vpn_permission")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "checkVpnPermission" -> checkVpnPermission(result)
            "requestVpnPermission" -> {
                pendingResult = result
                requestVpnPermission()
            }
            else -> result.notImplemented()
        }
    }

    private fun checkVpnPermission(result: Result) {
        val hasPermission = VpnService.prepare(activity) == null
        result.success(hasPermission)
    }

    private fun requestVpnPermission() {
        val intent = VpnService.prepare(activity)
        if (intent != null) {
            activity?.startActivityForResult(intent, vpnRequestCode)
        } else {
            pendingResult?.success(true)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == vpnRequestCode) {
            val granted = resultCode == Activity.RESULT_OK
            pendingResult?.success(granted)
            pendingResult = null
            return true
        }
        return false
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        onDetachedFromActivity()
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}