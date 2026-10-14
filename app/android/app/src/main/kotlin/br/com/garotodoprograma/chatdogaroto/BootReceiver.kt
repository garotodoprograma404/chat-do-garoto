package br.com.garotodoprograma.chatdogaroto

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/** Reconnects after the phone is turned on and unlocked. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        val service = Intent(context, ConnectionService::class.java)
            .putExtra(ConnectionService.EXTRA_SOURCE, ConnectionService.SOURCE_BOOT)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(service)
        } else {
            context.startService(service)
        }
    }
}
