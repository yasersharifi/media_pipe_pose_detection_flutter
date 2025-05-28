package com.example.last_native_pose_detection

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Matrix
import android.media.MediaMetadataRetriever
import android.os.SystemClock
import android.util.Log
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.framework.image.MPImage
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarkerResult

class PoseLandmarkerHelper(
    var minPoseDetectionConfidence: Float = DEFAULT_POSE_DETECTION_CONFIDENCE,
    var minPoseTrackingConfidence: Float = DEFAULT_POSE_TRACKING_CONFIDENCE,
    var minPosePresenceConfidence: Float = DEFAULT_POSE_PRESENCE_CONFIDENCE,
    // Use lite model by default for better performance on mobile devices
    var currentModel: Int = MODEL_POSE_LANDMARKER_LITE,
    var currentDelegate: Int = DELEGATE_CPU,
    var runningMode: RunningMode = RunningMode.IMAGE,
    val context: Context,
    // this listener is only used when running in RunningMode.LIVE_STREAM
    val poseLandmarkerHelperListener: LandmarkerListener? = null
) {

    // For this example this needs to be a var so it can be reset on changes.
    // If the Pose Landmarker will not change, a lazy val would be preferable.
    private var poseLandmarker: PoseLandmarker? = null

    init {
        setupPoseLandmarker()
    }

    fun clearPoseLandmarker() {
        poseLandmarker?.close()
        poseLandmarker = null
    }

    // Return running status of PoseLandmarkerHelper
    fun isClose(): Boolean {
        return poseLandmarker == null
    }

    // Initialize the Pose landmarker using current settings on the
    // thread that is using it. CPU can be used with Landmarker
    // that are created on the main thread and used on a background thread, but
    // the GPU delegate needs to be used on the thread that initialized the
    // Landmarker
    fun setupPoseLandmarker() {
        Log.d(TAG, "Setting up PoseLandmarker with mode: $runningMode, model: $currentModel")
        // Set general pose landmarker options
        val baseOptionBuilder = BaseOptions.builder()

        // Use the specified hardware for running the model. Default to CPU
        when (currentDelegate) {
            DELEGATE_CPU -> {
                baseOptionBuilder.setDelegate(Delegate.CPU)
                Log.d(TAG, "Using CPU delegate")
            }
            DELEGATE_GPU -> {
                baseOptionBuilder.setDelegate(Delegate.GPU)
                Log.d(TAG, "Using GPU delegate")
            }
        }

        val modelName =
            when (currentModel) {
                MODEL_POSE_LANDMARKER_FULL -> "pose_landmarker_full.task"
                MODEL_POSE_LANDMARKER_LITE -> "pose_landmarker_lite.task"
                MODEL_POSE_LANDMARKER_HEAVY -> "pose_landmarker_heavy.task"
                else -> "pose_landmarker_lite.task" // Default to lite for better performance
            }
        
        Log.d(TAG, "Using model: $modelName")
        baseOptionBuilder.setModelAssetPath(modelName)

        // Check if runningMode is consistent with poseLandmarkerHelperListener
        when (runningMode) {
            RunningMode.LIVE_STREAM -> {
                if (poseLandmarkerHelperListener == null) {
                    throw IllegalStateException(
                        "poseLandmarkerHelperListener must be set when runningMode is LIVE_STREAM."
                    )
                }
            }
            else -> {
                // no-op
            }
        }

        try {
            val baseOptions = baseOptionBuilder.build()
            // Create an option builder with base options and specific
            // options only use for Pose Landmarker.
            val optionsBuilder =
                PoseLandmarker.PoseLandmarkerOptions.builder()
                    .setBaseOptions(baseOptions)
                    .setMinPoseDetectionConfidence(minPoseDetectionConfidence)
                    .setMinTrackingConfidence(minPoseTrackingConfidence)
                    .setMinPosePresenceConfidence(minPosePresenceConfidence)
                    .setRunningMode(runningMode)

            // The ResultListener and ErrorListener only use for LIVE_STREAM mode.
            if (runningMode == RunningMode.LIVE_STREAM) {
                optionsBuilder
                    .setResultListener(this::returnLivestreamResult)
                    .setErrorListener(this::returnLivestreamError)
            }

            val options = optionsBuilder.build()
            Log.d(TAG, "Creating PoseLandmarker with detection confidence: $minPoseDetectionConfidence, tracking: $minPoseTrackingConfidence, presence: $minPosePresenceConfidence")
            poseLandmarker =
                PoseLandmarker.createFromOptions(context, options)
            Log.d(TAG, "PoseLandmarker successfully created")
        } catch (e: IllegalStateException) {
            poseLandmarkerHelperListener?.onError(
                "Pose Landmarker failed to initialize. See error logs for " +
                        "details"
            )
            Log.e(
                TAG, "MediaPipe failed to load the task with error: " + e
                    .message
            )
        } catch (e: RuntimeException) {
            // This occurs if the model being used does not support GPU
            poseLandmarkerHelperListener?.onError(
                "Pose Landmarker failed to initialize. See error logs for " +
                        "details", GPU_ERROR
            )
            Log.e(
                TAG,
                "Image classifier failed to load model with error: " + e.message
            )
        }
    }

    // Process the camera frame for live stream
    fun detectLiveStream(
        bitmap: Bitmap,
        isFrontCamera: Boolean
    ) {
        if (runningMode != RunningMode.LIVE_STREAM) {
            throw IllegalArgumentException(
                "Attempting to call detectLiveStream" +
                        " while not using RunningMode.LIVE_STREAM"
            )
        }
        
        val frameTime = SystemClock.uptimeMillis()
        
        try {
            Log.d(TAG, "Processing live camera frame: ${bitmap.width}x${bitmap.height}")
            
            // During testing, sometimes recreating the poseLandmarker with even lower thresholds
            // can help detection when no poses are being found
            if (frameTime % 50 == 0L && poseLandmarker != null) {
                Log.d(TAG, "Trying to reinitialize pose detector with lower thresholds")
                minPoseDetectionConfidence = 0.01f
                minPoseTrackingConfidence = 0.01f
                minPosePresenceConfidence = 0.01f
                clearPoseLandmarker()
                setupPoseLandmarker()
            }
            
            val matrix = Matrix().apply {
                // Flip image if using front camera
                if (isFrontCamera) {
                    postScale(-1f, 1f, bitmap.width.toFloat(), bitmap.height.toFloat())
                }
                
                // Try a slightly different rotation each frame to catch poses at different angles
                // This can help with detection in challenging conditions
                val angle = ((frameTime % 20) - 10).toFloat() // Range from -10 to 9 degrees as float
                if (angle != 0f) {
                    postRotate(angle, bitmap.width / 2f, bitmap.height / 2f)
                }
            }
            
            val processedBitmap = Bitmap.createBitmap(
                bitmap, 0, 0, bitmap.width, bitmap.height,
                matrix, true
            )
            
            // Convert the input Bitmap object to an MPImage object to run inference
            val mpImage = BitmapImageBuilder(processedBitmap).build()
            
            // Process the frame
            detectAsync(mpImage, frameTime)
            
            if (processedBitmap != bitmap) {
                processedBitmap.recycle()
            }
            
            // Log that we've processed the frame
            Log.d(TAG, "Successfully processed live camera frame at time $frameTime")
            
        } catch (e: Exception) {
            Log.e(TAG, "Error processing live camera frame: ${e.message}")
            e.printStackTrace()
            poseLandmarkerHelperListener?.onError("Error processing live camera frame: ${e.message}")
        }
    }

    // Run pose landmark using MediaPipe Pose Landmarker API
    private fun detectAsync(mpImage: MPImage, frameTime: Long) {
        poseLandmarker?.detectAsync(mpImage, frameTime)
        // As we're using running mode LIVE_STREAM, the landmark result will
        // be returned in returnLivestreamResult function
    }

    // Process the frames from a video file
    fun detectVideoFile(videoPath: String): ResultBundle? {
        if (runningMode != RunningMode.VIDEO) {
            throw IllegalArgumentException(
                "Attempting to call detectVideoFile" +
                        " while not using RunningMode.VIDEO"
            )
        }

        // Inference time is the difference between the system time at the start and finish of the
        // process
        val startTime = SystemClock.uptimeMillis()
        
        // Temporarily clear and recreate PoseLandmarker in IMAGE mode
        // This is a workaround since MediaPipe's VIDEO mode doesn't support single frame detection
        // We'll process the video frame as an image instead
        val originalRunningMode = runningMode
        clearPoseLandmarker()
        
        // Store current settings
        val savedMinPoseDetectionConfidence = minPoseDetectionConfidence
        val savedMinPoseTrackingConfidence = minPoseTrackingConfidence
        val savedMinPosePresenceConfidence = minPosePresenceConfidence
        val savedCurrentModel = currentModel
        val savedCurrentDelegate = currentDelegate
        
        // Set up for image processing
        runningMode = RunningMode.IMAGE
        setupPoseLandmarker()

        try {
            // Load frames from the video and run the pose landmarker.
            val retriever = MediaMetadataRetriever()
            retriever.setDataSource(videoPath)
            val videoLengthMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLong() ?: 0
            
            Log.d(TAG, "Video length: ${videoLengthMs}ms")
            
            // Get middle frame of the video
            val centerTimeUs = videoLengthMs * 1000 / 2
            val originalBitmap = retriever.getFrameAtTime(centerTimeUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                ?: return null
                
            Log.d(TAG, "Retrieved video frame: ${originalBitmap.width}x${originalBitmap.height}, config: ${originalBitmap.config}")
            
            // Ensure the bitmap is in ARGB_8888 format which is required by MediaPipe
            val bitmap = if (originalBitmap.config != Bitmap.Config.ARGB_8888) {
                Log.d(TAG, "Converting bitmap to ARGB_8888 format")
                val convertedBitmap = originalBitmap.copy(Bitmap.Config.ARGB_8888, false)
                originalBitmap.recycle() // Free up the original bitmap
                convertedBitmap
            } else {
                originalBitmap
            }
            
            // Convert the input Bitmap object to an MPImage object to run inference
            val mpImage = BitmapImageBuilder(bitmap).build()
            
            // Now use the correct method for image processing
            Log.d(TAG, "Processing video frame in IMAGE mode")
            val poseLandmarkerResult = poseLandmarker?.detect(mpImage)
            
            retriever.release()
            
            val inferenceTimeMs = SystemClock.uptimeMillis() - startTime
            
            // Free up resources for Bitmap if we're done with it
            if (bitmap != originalBitmap) {
                bitmap.recycle()
            }
            
            // Store the result before restoring original configuration
            val resultBundle = if (poseLandmarkerResult != null) {
                Log.d(TAG, "Video pose detection successful")
                ResultBundle(
                    listOf(poseLandmarkerResult),
                    inferenceTimeMs,
                    bitmap.height,
                    bitmap.width
                )
            } else {
                Log.e(TAG, "Pose Landmarker failed to detect on video frame")
                poseLandmarkerHelperListener?.onError("Pose Landmarker failed to detect on video frame.")
                null
            }
            
            // Restore original settings
            clearPoseLandmarker()
            runningMode = originalRunningMode
            minPoseDetectionConfidence = savedMinPoseDetectionConfidence
            minPoseTrackingConfidence = savedMinPoseTrackingConfidence
            minPosePresenceConfidence = savedMinPosePresenceConfidence
            currentModel = savedCurrentModel
            currentDelegate = savedCurrentDelegate
            setupPoseLandmarker()
            
            return resultBundle
            
        } catch (e: Exception) {
            Log.e(TAG, "Error in video processing: ${e.message}")
            poseLandmarkerHelperListener?.onError("Error in video processing: ${e.message}")
            
            // Restore original settings even on error
            try {
                clearPoseLandmarker()
                runningMode = originalRunningMode
                minPoseDetectionConfidence = savedMinPoseDetectionConfidence
                minPoseTrackingConfidence = savedMinPoseTrackingConfidence
                minPosePresenceConfidence = savedMinPosePresenceConfidence
                currentModel = savedCurrentModel
                currentDelegate = savedCurrentDelegate
                setupPoseLandmarker()
            } catch (e2: Exception) {
                Log.e(TAG, "Error restoring original settings: ${e2.message}")
            }
            
            return null
        }
    }

    // Detect pose landmarks from a bitmap image
    fun detectImage(bitmap: Bitmap): ResultBundle? {
        if (runningMode != RunningMode.IMAGE) {
            throw IllegalArgumentException(
                "Attempting to call detectImage" +
                        " while not using RunningMode.IMAGE"
            )
        }

        // Inference time is the difference between the system time at the
        // start and finish of the process
        val startTime = SystemClock.uptimeMillis()

        // Convert the input Bitmap object to an MPImage object to run inference
        val mpImage = BitmapImageBuilder(bitmap).build()

        // Run pose landmarker using MediaPipe Pose Landmarker API
        poseLandmarker?.detect(mpImage)?.also { landmarkResult ->
            val inferenceTimeMs = SystemClock.uptimeMillis() - startTime
            return ResultBundle(
                listOf(landmarkResult),
                inferenceTimeMs,
                bitmap.height,
                bitmap.width
            )
        }

        // If poseLandmarker?.detect() returns null, this is likely an error
        poseLandmarkerHelperListener?.onError(
            "Pose Landmarker failed to detect."
        )
        return null
    }

    // Return the landmark result to this PoseLandmarkerHelper's caller
    private fun returnLivestreamResult(
        result: PoseLandmarkerResult,
        input: MPImage
    ) {
        val finishTimeMs = SystemClock.uptimeMillis()
        val inferenceTime = finishTimeMs - result.timestampMs()

        // Log the detection results for debugging
        val poseCount = result.landmarks().size
        Log.d(TAG, "LiveStream result: detected $poseCount poses")
        
        if (poseCount > 0) {
            // If poses were detected, log more details
            val firstPose = result.landmarks()[0]
            Log.d(TAG, "First pose has ${firstPose.size} landmarks")
        }

        poseLandmarkerHelperListener?.onResults(
            ResultBundle(
                listOf(result),
                inferenceTime,
                input.height,
                input.width
            )
        )
    }

    // Return errors thrown during detection to this PoseLandmarkerHelper's
    // caller
    private fun returnLivestreamError(error: RuntimeException) {
        poseLandmarkerHelperListener?.onError(
            error.message ?: "An unknown error has occurred"
        )
    }

    companion object {
        const val TAG = "PoseLandmarkerHelper"

        const val DELEGATE_CPU = 0
        const val DELEGATE_GPU = 1
        const val MODEL_POSE_LANDMARKER_FULL = 0
        const val MODEL_POSE_LANDMARKER_LITE = 1
        const val MODEL_POSE_LANDMARKER_HEAVY = 2
        // Lowered confidence thresholds to make detection more sensitive
        const val DEFAULT_POSE_DETECTION_CONFIDENCE = 0.2f
        const val DEFAULT_POSE_TRACKING_CONFIDENCE = 0.2f
        const val DEFAULT_POSE_PRESENCE_CONFIDENCE = 0.2f
        const val OTHER_ERROR = 0
        const val GPU_ERROR = 1
    }

    data class ResultBundle(
        val results: List<PoseLandmarkerResult>,
        val inferenceTime: Long,
        val inputImageHeight: Int,
        val inputImageWidth: Int,
    )

    interface LandmarkerListener {
        fun onError(error: String, errorCode: Int = OTHER_ERROR)
        fun onResults(resultBundle: ResultBundle)
    }
}
