package com.example.last_native_pose_detection

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import androidx.annotation.NonNull
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarkerResult
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.util.Optional

class MainActivity : FlutterActivity(), PoseLandmarkerHelper.LandmarkerListener {
    private val CHANNEL = "com.example.last_native_pose_detection/pose_detection"
    private val TAG = "MainActivity"
    
    private var poseLandmarkerHelper: PoseLandmarkerHelper? = null
    private var imageProcessingResult: MethodChannel.Result? = null
    private var videoProcessingResult: MethodChannel.Result? = null
    private var cameraProcessingResult: MethodChannel.Result? = null
    
    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "processImage" -> {
                    val imagePath = call.argument<String>("imagePath")!!
                    processImage(imagePath, result)
                }
                "processVideo" -> {
                    val videoPath = call.argument<String>("videoPath")!!
                    processVideo(videoPath, result)
                }
                "processImageFromCamera" -> {
                    val width = call.argument<Int>("width")!!
                    val height = call.argument<Int>("height")!!
                    val format = call.argument<Int>("format")!!
                    val planes = call.argument<List<Map<String, Any>>>("planes")!!
                    processImageFromCamera(width, height, format, planes, result)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
    
    private fun setupPoseLandmarkerForImage(): PoseLandmarkerHelper {
        val options = PoseLandmarkerHelper(
            context = this,
            runningMode = RunningMode.IMAGE,
            poseLandmarkerHelperListener = this
        )
        
        return options
    }
    
    private fun setupPoseLandmarkerForVideo(): PoseLandmarkerHelper {
        val options = PoseLandmarkerHelper(
            context = this,
            runningMode = RunningMode.VIDEO,
            poseLandmarkerHelperListener = this
        )
        
        return options
    }
    
    private fun setupPoseLandmarkerForLiveStream(): PoseLandmarkerHelper {
        val options = PoseLandmarkerHelper(
            context = this,
            runningMode = RunningMode.LIVE_STREAM,
            poseLandmarkerHelperListener = this
        )
        
        return options
    }
    
    private fun processImage(imagePath: String, result: MethodChannel.Result) {
        try {
            // Store the Flutter result callback
            imageProcessingResult = result
            
            // Create PoseLandmarkerHelper for image mode
            poseLandmarkerHelper = setupPoseLandmarkerForImage()
            
            // Process the image
            val file = File(imagePath)
            val bitmap = BitmapFactory.decodeFile(file.absolutePath)
            
            if (bitmap != null) {
                val resultBundle = poseLandmarkerHelper?.detectImage(bitmap)
                if (resultBundle != null) {
                    handlePoseLandmarkerResult(resultBundle, result)
                } else {
                    result.error("DETECTION_ERROR", "Failed to process image with pose detector", null)
                }
            } else {
                result.error("BITMAP_ERROR", "Failed to decode bitmap from file", null)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error processing image: ${e.message}")
            result.error("PROCESSING_ERROR", "Error processing image: ${e.message}", null)
        } finally {
            poseLandmarkerHelper?.clearPoseLandmarker()
        }
    }
    
    private fun processVideo(videoPath: String, result: MethodChannel.Result) {
        try {
            // Store the Flutter result callback
            videoProcessingResult = result
            
            // Create PoseLandmarkerHelper for video mode
            poseLandmarkerHelper = setupPoseLandmarkerForVideo()
            
            // Process the video
            val resultBundle = poseLandmarkerHelper?.detectVideoFile(videoPath)
                    if (resultBundle != null) {
                        handlePoseLandmarkerResult(resultBundle, result)
                    } else {
                result.error("DETECTION_ERROR", "Failed to process video with pose detector", null)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error processing video: ${e.message}")
            result.error("PROCESSING_ERROR", "Error processing video: ${e.message}", null)
        } finally {
            poseLandmarkerHelper?.clearPoseLandmarker()
        }
    }
    
    private fun processImageFromCamera(width: Int, height: Int, format: Int, planes: List<Map<String, Any>>, result: MethodChannel.Result) {
        try {
            // Store the Flutter result callback
            cameraProcessingResult = result
            
            // Create PoseLandmarkerHelper for live stream mode
            if (poseLandmarkerHelper == null || poseLandmarkerHelper?.isClose() == true) {
                poseLandmarkerHelper = setupPoseLandmarkerForLiveStream()
            }
            
            // Convert YUV_420_888 image to Bitmap
            val bitmap = yuv420ToBitmap(width, height, planes)
            
            if (bitmap != null) {
                // Use front camera for selfie view - flip the image horizontally
                poseLandmarkerHelper?.detectLiveStream(bitmap, true)
                
                // We don't immediately return results as they will come through the listener
                // The result will be handled in onResults() callback
            } else {
                result.error("BITMAP_ERROR", "Failed to create bitmap from camera image", null)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error processing camera frame: ${e.message}")
            result.error("PROCESSING_ERROR", "Error processing camera frame: ${e.message}", null)
        }
    }
    
    private fun yuv420ToBitmap(width: Int, height: Int, planes: List<Map<String, Any>>): Bitmap? {
        try {
            val yBuffer = planes[0]["bytes"] as ByteArray
            val uBuffer = planes[1]["bytes"] as ByteArray
            val vBuffer = planes[2]["bytes"] as ByteArray
            
            val yRowStride = planes[0]["bytesPerRow"] as Int
            val uvRowStride = planes[1]["bytesPerRow"] as Int
            val uvPixelStride = planes[1]["bytesPerPixel"] as Int
            
            val rgbBytes = IntArray(width * height)
            
            yuv420ToRgb(yBuffer, uBuffer, vBuffer, width, height, yRowStride, uvRowStride, uvPixelStride, rgbBytes)
            
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            bitmap.setPixels(rgbBytes, 0, width, 0, 0, width, height)
            return bitmap
        } catch (e: Exception) {
            Log.e(TAG, "Error converting YUV to bitmap: ${e.message}")
            return null
        }
    }
    
    private fun yuv420ToRgb(yData: ByteArray, uData: ByteArray, vData: ByteArray,
                          width: Int, height: Int, yRowStride: Int, uvRowStride: Int,
                          uvPixelStride: Int, output: IntArray) {
        var yp = 0
        for (j in 0 until height) {
            val pY = yRowStride * j
            val pUV = uvRowStride * (j shr 1)
            
            for (i in 0 until width) {
                val uvOffset = pUV + (i shr 1) * uvPixelStride
                
                output[yp++] = yuv2Rgb(
                    yData[pY + i].toInt() and 0xff, 
                    uData[uvOffset].toInt() and 0xff - 128,
                    vData[uvOffset].toInt() and 0xff - 128
                )
            }
        }
    }
    
    private fun yuv2Rgb(y: Int, u: Int, v: Int): Int {
        // YUV to RGB conversion formula
        var r = (y + (1.370705 * v)).toInt()
        var g = (y - (0.698001 * v) - (0.337633 * u)).toInt()
        var b = (y + (1.732446 * u)).toInt()
        
        r = if (r < 0) 0 else if (r > 255) 255 else r
        g = if (g < 0) 0 else if (g > 255) 255 else g
        b = if (b < 0) 0 else if (b > 255) 255 else b
        
        return 0xff000000.toInt() or (r shl 16) or (g shl 8) or b
    }
    
    private fun handlePoseLandmarkerResult(resultBundle: PoseLandmarkerHelper.ResultBundle, result: MethodChannel.Result) {
        val landmarksList = mutableListOf<Map<String, Any>>()
        
        try {
            // Process all detected poses
            for (poseLandmarkerResult in resultBundle.results) {
                if (poseLandmarkerResult.landmarks().isNotEmpty()) {
                    // Just process the first detected person for simplicity
                    val firstPersonLandmarks = poseLandmarkerResult.landmarks()[0]
                    
                    for (normalizedLandmark in firstPersonLandmarks) {
                        // Safely unwrap Optional values if needed
                        val x = normalizedLandmark.x()
                        val y = normalizedLandmark.y()
                        val z = normalizedLandmark.z()
                        // Visibility might be wrapped in Optional in some MediaPipe versions
                        val visibility = try {
                            val visibilityValue = normalizedLandmark.visibility()
                            // Check if the result is an Optional (this happens in some MediaPipe versions)
                            if (visibilityValue is Optional<*>) {
                                if (visibilityValue.isPresent) {
                                    visibilityValue.get() as Float
                                } else {
                                    0.0f
                                }
                            } else {
                                // It's already a float
                                visibilityValue as Float
                            }
                        } catch (e: Exception) {
                            Log.d(TAG, "Error extracting visibility: ${e.message}")
                            // Default visibility if there's an error
                            0.0f
                        }
                        
                        val landmarkMap = mapOf(
                            "x" to x,
                            "y" to y,
                            "z" to z,
                            "visibility" to visibility
                        )
                        landmarksList.add(landmarkMap)
                    }
                }
            }
            
            val resultMap = mapOf(
                "landmarks" to landmarksList,
                "inferenceTime" to resultBundle.inferenceTime
            )
            
            result.success(resultMap)
        } catch (e: Exception) {
            Log.e(TAG, "Error processing landmark results: ${e.message}")
            result.error("LANDMARK_PROCESSING_ERROR", "Error processing landmarks: ${e.message}", null)
        }
    }
    
    override fun onResults(resultBundle: PoseLandmarkerHelper.ResultBundle) {
        // This is called from the PoseLandmarkerHelper when using LIVE_STREAM mode
        cameraProcessingResult?.let { result ->
            handlePoseLandmarkerResult(resultBundle, result)
            // Reset result reference after use
            cameraProcessingResult = null
        }
    }
    
    override fun onError(error: String, errorCode: Int) {
        Log.e(TAG, "Pose detection error: $error")
        
        val errorResult = when {
            imageProcessingResult != null -> imageProcessingResult
            videoProcessingResult != null -> videoProcessingResult
            cameraProcessingResult != null -> cameraProcessingResult
            else -> null
        }
        
        errorResult?.error("LANDMARKER_ERROR_$errorCode", error, null)
        
        // Reset result references
        imageProcessingResult = null
        videoProcessingResult = null
        cameraProcessingResult = null
    }
    
    override fun onDestroy() {
        super.onDestroy()
        poseLandmarkerHelper?.clearPoseLandmarker()
    }
}
