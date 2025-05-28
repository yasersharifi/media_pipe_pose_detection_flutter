// Remove unused import
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';

class CameraPosePage extends StatefulWidget {
  final List<CameraDescription> cameras;
  
  const CameraPosePage({Key? key, required this.cameras}) : super(key: key);

  @override
  State<CameraPosePage> createState() => _CameraPosePageState();
}

class _CameraPosePageState extends State<CameraPosePage> {
  static const platform = MethodChannel('com.example.last_native_pose_detection/pose_detection');
  
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isDetecting = false;
  bool _isFrontCamera = true;
  
  List<Map<String, dynamic>>? _landmarks;
  int? _inferenceTime;
  
  @override
  void initState() {
    super.initState();
    _initCamera();
  }
  
  @override
  void dispose() {
    _stopCamera();
    super.dispose();
  }
  
  Future<void> _initCamera() async {
    if (widget.cameras.isEmpty) {
      print('No cameras available on this device.');
      return;
    }
    
    // Find front camera
    final frontCamera = widget.cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => widget.cameras.first,
    );
    
    _cameraController = CameraController(
      _isFrontCamera ? frontCamera : widget.cameras.first,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    
    try {
      await _cameraController!.initialize();
      
      // Start camera stream
      await _cameraController!.startImageStream(_processCameraImage);
      
      setState(() {
        _isCameraInitialized = true;
      });
      
      print('Camera initialized successfully');
    } catch (e) {
      print('Error initializing camera: $e');
    }
  }
  
  void _stopCamera() {
    if (_cameraController != null) {
      if (_cameraController!.value.isStreamingImages) {
        _cameraController!.stopImageStream();
      }
      _cameraController!.dispose();
      _cameraController = null;
      _isCameraInitialized = false;
    }
  }
  
  void _switchCamera() async {
    setState(() {
      _isFrontCamera = !_isFrontCamera;
    });
    
    // Stop current camera
    _stopCamera();
    
    // Reinitialize with new camera
    await _initCamera();
  }
  
  Future<void> _processCameraImage(CameraImage image) async {
    if (_isDetecting) return;
    
    setState(() {
      _isDetecting = true;
    });
    
    try {
      // Convert the camera image format for pose detection
      final planes = <Map<String, dynamic>>[];
      
      for (int i = 0; i < image.planes.length; i++) {
        planes.add({
          'bytes': image.planes[i].bytes,
          'bytesPerRow': image.planes[i].bytesPerRow,
          'bytesPerPixel': image.planes[i].bytesPerPixel,
        });
      }
      
      // Call native method to process frame
      final result = await platform.invokeMethod('processImageFromCamera', {
        'width': image.width,
        'height': image.height,
        'format': image.format.raw,
        'planes': planes,
      });
      
      // Update UI with results - handle type casting properly
      setState(() {
        // Safely convert the landmarks from platform channel
        if (result['landmarks'] != null) {
          final landmarksList = result['landmarks'] as List<dynamic>;
          _landmarks = landmarksList
              .map((item) => Map<String, dynamic>.from(item as Map<Object?, Object?>))
              .toList();
              
          // Extract inference time
          _inferenceTime = result['inferenceTime'] as int?;
          
          // Log landmarks instead of drawing them
          print('Live pose detection: ${_landmarks!.length} landmarks found');
          print('Inference time: ${_inferenceTime}ms');
          
          // Log detailed landmark information if needed
          if (_landmarks!.isNotEmpty) {
            print('Landmark details:');
            for (int i = 0; i < _landmarks!.length; i++) {
              print('Landmark $i: ${_landmarks![i]}');
            }
          }
        } else {
          _landmarks = [];
          _inferenceTime = 0;
          print('No landmarks detected from camera');
        }
      });
    } on PlatformException catch (e) {
      print('Platform error during camera stream processing: $e');
    } catch (e) {
      print('Error during camera stream processing: $e');
    } finally {
      setState(() {
        _isDetecting = false;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Camera Pose Detection'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: Icon(_isFrontCamera ? Icons.camera_rear : Icons.camera_front),
            onPressed: _switchCamera,
            tooltip: 'Switch camera',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _isCameraInitialized
                    ? CameraPreview(_cameraController!)
                    : const Center(child: CircularProgressIndicator()),
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Landmarks detected: ${_landmarks?.length ?? 0}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                if (_inferenceTime != null)
                  Text(
                    'Inference time: ${_inferenceTime}ms',
                    style: const TextStyle(fontSize: 16),
                  ),
                if (_landmarks != null && _landmarks!.isNotEmpty)
                  const Text(
                    'Landmark details printed to console',
                    style: TextStyle(fontSize: 16, fontStyle: FontStyle.italic),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
