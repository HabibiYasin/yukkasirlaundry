package com.yukkasir.yuk_kasir

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.content.ClipData
import android.net.Uri
import androidx.core.content.FileProvider
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "yuk_kasir/whatsapp_receipt")
            .setMethodCallHandler { call, result ->
                if (call.method != "sendReceipt") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val phone = call.argument<String>("phone") ?: ""
                val text = call.argument<String>("text") ?: ""
                if (!Regex("^[1-9][0-9]{7,14}$").matches(phone)) {
                    result.error("invalid_phone", "Nomor HP pelanggan tidak valid.", null)
                    return@setMethodCallHandler
                }
                val target = listOf("com.whatsapp", "com.whatsapp.w4b").firstOrNull {
                    packageManager.getLaunchIntentForPackage(it) != null
                }
                if (target == null) {
                    result.error("not_installed", "Pasang WhatsApp atau WhatsApp Business terlebih dahulu.", null)
                    return@setMethodCallHandler
                }
                try {
                    val image = call.argument<ByteArray>("image")
                    val intent = if (image == null) {
                        Intent(Intent.ACTION_VIEW, Uri.Builder()
                            .scheme("https").authority("wa.me").appendPath(phone)
                            .appendQueryParameter("text", text).build())
                    } else {
                        val directory = File(cacheDir, "whatsapp_receipts").apply { mkdirs() }
                        // Keep recent attachments available while WhatsApp reads them.
                        directory.listFiles()?.filter {
                            it.lastModified() < System.currentTimeMillis() - 86400000L
                        }?.forEach { it.delete() }
                        val file = File.createTempFile("nota-", ".png", directory)
                        file.writeBytes(image)
                        val uri = FileProvider.getUriForFile(this, "$packageName.receipts", file)
                        Intent(Intent.ACTION_SEND).apply {
                            type = "image/png"
                            putExtra(Intent.EXTRA_STREAM, uri)
                            // WhatsApp-specific recipient hint; support depends on the app version.
                            putExtra("jid", "$phone@s.whatsapp.net")
                            clipData = ClipData.newRawUri("Nota", uri)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                    }
                    intent.setPackage(target)
                    startActivity(intent)
                    result.success(null)
                } catch (e: Exception) {
                    result.error("launch_failed", "Gagal membuka nota di WhatsApp. Silakan coba lagi.", null)
                }
            }
    }
}
