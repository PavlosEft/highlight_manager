package com.example.highlight_manager

import android.app.Activity
import android.content.ContentUris
import android.content.Intent
import android.net.Uri
import android.provider.MediaStore
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
            when (call.method) {
                "pickVideos" -> {
                    pendingResult = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "video/*"
                        putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                    }
                    startActivityForResult(intent, PICK_VIDEO_REQUEST_CODE)
                }
                "checkFileExists" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        try {
                            val uri = Uri.parse(path)
                            // Προσπαθούμε να ανοίξουμε το stream για να δούμε αν το URI ισχύει ακόμα
                            val inputStream = contentResolver.openInputStream(uri)
                            inputStream?.close()
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    } else {
                        result.success(false)
                    }
                }
                "findVideo" -> {
                    val name = call.argument<String>("name")
                    val duration = call.argument<Int>("duration") // σε ms
                    val size = call.argument<Int>("size") // σε bytes

                    if (name != null) {
                        val projection = arrayOf(
                            MediaStore.Video.Media._ID,
                            MediaStore.Video.Media.DISPLAY_NAME,
                            MediaStore.Video.Media.DURATION,
                            MediaStore.Video.Media.SIZE
                        )

                        // Ψάχνουμε στη βάση δεδομένων του Android (MediaStore) για το αρχείο
                        val selection = "${MediaStore.Video.Media.DISPLAY_NAME} = ?"
                        val selectionArgs = arrayOf(name)
                        val query = contentResolver.query(
                            MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                            projection,
                            selection,
                            selectionArgs,
                            null
                        )

                        var foundUri: String? = null

                        query?.use { cursor ->
                            val idColumn = cursor.getColumnIndexOrThrow(MediaStore.Video.Media._ID)
                            val durationColumn = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.DURATION)
                            val sizeColumn = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.SIZE)

                            while (cursor.moveToNext()) {
                                val fileId = cursor.getLong(idColumn)
                                val fileDuration = cursor.getLong(durationColumn)
                                val fileSize = cursor.getLong(sizeColumn)

                                // Έλεγχος ταύτισης: Ίδιο όνομα ΚΑΙ Διάρκεια (απόκλιση έως 1.5s) ΚΑΙ Μέγεθος
                                val durationMatch = duration == null || Math.abs(fileDuration - duration) < 1500
                                val sizeMatch = size == null || size == 0 || fileSize == size.toLong()

                                if (durationMatch && sizeMatch) {
                                    val contentUri = ContentUris.withAppendedId(
                                        MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                                        fileId
                                    )
                                    foundUri = contentUri.toString()
                                    break 
                                }
                            }
                        }
                        result.success(foundUri)
                    } else {
                        result.error("INVALID_ARGUMENTS", "Name is null", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
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