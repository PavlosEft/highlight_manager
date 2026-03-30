package com.example.highlight_manager

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.highlight_manager/native_picker"
    private val PICK_VIDEO_REQUEST_CODE = 1001
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "pickVideos") {
                pendingResult = result
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "video/*"
                    putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                }
                startActivityForResult(intent, PICK_VIDEO_REQUEST_CODE)
            } else if (call.method == "checkFileExists") {
                val path = call.argument<String>("path")
                if (path != null) {
                    try {
                        val uri = Uri.parse(path)
                        contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                            result.success(cursor.moveToFirst())
                        } ?: result.success(false)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                } else {
                    result.success(false)
                }
            } else if (call.method == "getFileSize") {
                val path = call.argument<String>("path")
                if (path != null) {
                    try {
                        val uri = Uri.parse(path)
                        var size: Long? = null
                        contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                            if (cursor.moveToFirst()) {
                                val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                                if (sizeIndex != -1 && !cursor.isNull(sizeIndex)) {
                                    size = cursor.getLong(sizeIndex)
                                }
                            }
                        }
                        result.success(size)
                    } catch (e: Exception) {
                        result.success(null)
                    }
                } else {
                    result.success(null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun getFileName(uri: Uri): String {
        var result: String? = null
        if (uri.scheme == "content") {
            contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (index != -1) {
                        result = cursor.getString(index)
                    }
                }
            }
        }
        if (result == null) {
            result = uri.path?.substringAfterLast('/')
        }
        return result ?: "video_file"
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == PICK_VIDEO_REQUEST_CODE) {
            if (resultCode == Activity.RESULT_OK) {
                val fileList = mutableListOf<Map<String, String>>()
                data?.clipData?.let { clipData ->
                    for (i in 0 until clipData.itemCount) {
                        val uri = clipData.getItemAt(i).uri
                        contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        fileList.add(mapOf("path" to uri.toString(), "name" to getFileName(uri)))
                    }
                } ?: data?.data?.let { uri ->
                    contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    fileList.add(mapOf("path" to uri.toString(), "name" to getFileName(uri)))
                }
                pendingResult?.success(fileList)
            } else {
                pendingResult?.success(emptyList<Map<String, String>>())
            }
            pendingResult = null
        }
    }
}
