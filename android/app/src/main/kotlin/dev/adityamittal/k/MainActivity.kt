package dev.adityamittal.k

import dev.adityamittal.k.sms.SmsChannel
import dev.adityamittal.k.sms.SmsEventHub
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    private var smsChannel: SmsChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        smsChannel = SmsChannel(this, messenger)
        EventChannel(messenger, SmsChannel.EVENTS).setStreamHandler(SmsEventHub)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        smsChannel?.dispose()
        smsChannel = null
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, SmsChannel.EVENTS)
            .setStreamHandler(null)
        SmsEventHub.onCancel(null)
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
