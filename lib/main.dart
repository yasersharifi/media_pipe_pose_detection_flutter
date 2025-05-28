import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:camera/camera.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  
  const MyApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pose Detection',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: PoseDetectionHome(cameras: cameras),
    );
  }
}

// CustomPainter to draw pose landmarks and connections
class PosePainter extends CustomPainter {
  final List<Map<String, dynamic>> landmarks;
  
  PosePainter({required this.landmarks});
  
  @override
  void paint(Canvas canvas, Size size) {
    // Define connections between landmarks (simplified version)
    final connections = [
      [11, 12], // shoulders
      [11, 13], [13, 15], // left arm
      [12, 14], [14, 16], // right arm
      [11, 23], [12, 24], // hip connections
      [23, 24], // hips
      [23, 25], [25, 27], // left leg
      [24, 26], [26, 28], // right leg
      [27, 29], [28, 30], // foot connections
    ];
    
    // Paint for lines
    final linePaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
      
    // Paint for points
    final pointPaint = Paint()
      ..color = Colors.yellow
      ..style = PaintingStyle.fill;
      
    if (landmarks.isEmpty) return;
    
    // Draw connections
    for (final connection in connections) {
      if (connection[0] < landmarks.length && connection[1] < landmarks.length) {
        final start = landmarks[connection[0]];
        final end = landmarks[connection[1]];
        
        // Only draw if points have reasonable visibility
        if ((start['visibility'] as double?) != null && 
            (end['visibility'] as double?) != null && 
            start['visibility'] > 0.5 && 
            end['visibility'] > 0.5) {
            
          canvas.drawLine(
            Offset(
              (start['x'] as double) * size.width,
              (start['y'] as double) * size.height
            ),
            Offset(
              (end['x'] as double) * size.width,
              (end['y'] as double) * size.height
            ),
            linePaint
          );
        }
      }
    }
    
    // Draw landmark points
    for (int i = 0; i < landmarks.length; i++) {
      final landmark = landmarks[i];
      
      // Only draw if point has reasonable visibility
      if ((landmark['visibility'] as double?) != null && landmark['visibility'] > 0.5) {
        // Color based on landmark index
        pointPaint.color = i == 0 ? Colors.red : 
                          (i < 11 ? Colors.orange : 
                          (i < 23 ? Colors.green : Colors.blue));
                          
        canvas.drawCircle(
          Offset(
            (landmark['x'] as double) * size.width,
            (landmark['y'] as double) * size.height
          ),
          4,
          pointPaint
        );
      }
    }
  }
  
  @override
  bool shouldRepaint(PosePainter oldDelegate) {
    return oldDelegate.landmarks != landmarks;
  }
}

class PoseDetectionHome extends StatefulWidget {
  final List<CameraDescription> cameras;
  
  const PoseDetectionHome({super.key, required this.cameras});

  @override
  State<PoseDetectionHome> createState() => _PoseDetectionHomeState();
}

class _PoseDetectionHomeState extends State<PoseDetectionHome> with WidgetsBindingObserver {
  static const platform = MethodChannel('com.example.last_native_pose_detection/pose_detection');
  
  final ImagePicker _picker = ImagePicker();
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isDetecting = false;
  
  // For display results
  File? _imageFile;
  String? _videoPath;
  bool _isLiveDetection = false;
  
  // Store pose landmarks and inference time
  List<Map<String, dynamic>>? _landmarks;
  int? _inferenceTime;
  
  // Canvas for drawing pose skeleton
  final GlobalKey _canvasKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopCamera();
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _cameraController;
    
    // App state changed before we got the chance to initialize.
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera(cameraController.description);
    }
  }

  Future<void> _initializeCamera(CameraDescription cameraDescription) async {
    final CameraController cameraController = CameraController(
      cameraDescription,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    _cameraController = cameraController;

    try {
      await cameraController.initialize();
      if (!mounted) return;
      
      setState(() {
        _isCameraInitialized = true;
      });
      
      if (_isLiveDetection) {
        _startCameraStream();
      }
    } catch (e) {
      print('Error initializing camera: $e');
    }
  }
  
  void _stopCamera() {
    if (_cameraController != null) {
      _cameraController!.stopImageStream();
      _cameraController!.dispose();
      _cameraController = null;
      _isCameraInitialized = false;
    }
  }

  Future<void> _startCameraStream() async {
    if (_cameraController == null || !_isCameraInitialized) return;
    
    _isLiveDetection = true;
    _landmarks = [];
    
    await _cameraController!.startImageStream((CameraImage image) async {
      if (!_isDetecting) {
        _isDetecting = true;
        try {
          // Pass camera image to native code
          final result = await platform.invokeMethod('processImageFromCamera', {
            'width': image.width,
            'height': image.height,
            'format': image.format.raw,
            'planes': image.planes.map((plane) => {
              'bytes': plane.bytes,
              'bytesPerRow': plane.bytesPerRow,
              'bytesPerPixel': plane.bytesPerPixel,
            }).toList(),
          });
          
          if (result != null) {
            // Properly convert the landmarks data with explicit casting
            final landmarks = _convertLandmarksData(result['landmarks']);
            final inferenceTime = result['inferenceTime'] as int?;
            
            setState(() {
              _landmarks = landmarks;
              _inferenceTime = inferenceTime;
              print('Live pose detection: ${_landmarks?.length} landmarks found');
              print('Inference time: ${_inferenceTime ?? 'unknown'}ms');
            });
          }
        } catch (e) {
          print('Error during camera stream processing: $e');
        }
        _isDetecting = false;
      }
    });
  }
  
  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    
    if (image != null) {
      setState(() {
        _imageFile = File(image.path);
        _videoPath = null;
        _isLiveDetection = false;
      });
      
      await _processPoseFromImage(_imageFile!.path);
    }
  }
  
  Future<void> _pickVideo() async {
    final XFile? video = await _picker.pickVideo(source: ImageSource.gallery);
    
    if (video != null) {
      setState(() {
        _videoPath = video.path;
        _imageFile = null;
        _isLiveDetection = false;
      });
      
      await _processPoseFromVideo(_videoPath!);
    }
  }
  
  Future<void> _startLiveDetection() async {
    // Stop any previous camera
    _stopCamera();
    
    setState(() {
      _imageFile = null;
      _videoPath = null;
      _isLiveDetection = true;
    });
    
    // Initialize the camera with front camera if available
    final frontCamera = widget.cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => widget.cameras.first,
    );
    
    await _initializeCamera(frontCamera);
  }
  
  Future<void> _processPoseFromImage(String imagePath) async {
    try {
      final result = await platform.invokeMethod('processImage', {
        'imagePath': imagePath,
      });
      
      if (result != null) {
        // Properly convert the landmarks data with explicit casting
        final landmarks = _convertLandmarksData(result['landmarks']);
        final inferenceTime = result['inferenceTime'] as int?;
        
        setState(() {
          _landmarks = landmarks;
          _inferenceTime = inferenceTime;
          print('Pose detection complete: ${_landmarks?.length} landmarks found');
          print('Inference time: ${_inferenceTime ?? 'unknown'}ms');
        });
      }
    } catch (e) {
      print('Error during image processing: $e');
    }
  }
  
  Future<void> _processPoseFromVideo(String videoPath) async {
    try {
      final result = await platform.invokeMethod('processVideo', {
        'videoPath': videoPath,
      });
      
      if (result != null) {
        // Properly convert the landmarks data with explicit casting
        final landmarks = _convertLandmarksData(result['landmarks']);
        final inferenceTime = result['inferenceTime'] as int?;
        
        setState(() {
          _landmarks = landmarks;
          _inferenceTime = inferenceTime;
          print('Pose detection complete: ${_landmarks?.length} landmarks found');
          print('Inference time: ${_inferenceTime ?? 'unknown'}ms');
        });
      }
    } catch (e) {
      print('Error during video processing: $e');
    }
  }

  // Build a custom visualization of the pose skeleton
  Widget _buildLandmarksVisualizer() {
    if (_landmarks == null || _landmarks!.isEmpty) {
      return const SizedBox(height: 100, child: Center(child: Text('No landmarks detected')));
    }
    
    return Container(
      height: 200,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(12),
      ),
      child: CustomPaint(
        key: _canvasKey,
        painter: PosePainter(landmarks: _landmarks!),
        child: Container(), // Empty container for the CustomPaint
      ),
    );
  }
  
  // Get human-readable names for pose landmarks
  String _getPoseLandmarkName(int index) {
    // MediaPipe pose landmarks mapping (33 points)
    final landmarkNames = [
      'Nose',
      'Left eye inner', 'Left eye', 'Left eye outer',
      'Right eye inner', 'Right eye', 'Right eye outer',
      'Left ear', 'Right ear',
      'Mouth left', 'Mouth right',
      'Left shoulder', 'Right shoulder',
      'Left elbow', 'Right elbow',
      'Left wrist', 'Right wrist',
      'Left pinky', 'Right pinky',
      'Left index', 'Right index',
      'Left thumb', 'Right thumb',
      'Left hip', 'Right hip',
      'Left knee', 'Right knee',
      'Left ankle', 'Right ankle',
      'Left heel', 'Right heel',
      'Left foot index', 'Right foot index',
    ];
    
    if (index < landmarkNames.length) {
      return landmarkNames[index];
    }
    return 'Landmark #$index';
  }
  
  // Get color for different landmark types
  Color _getLandmarkColor(int index) {
    // Group landmarks by body part for color coding
    if (index == 0) { // Nose
      return Colors.red;
    } else if (index >= 1 && index <= 10) { // Face
      return Colors.orange;
    } else if (index >= 11 && index <= 22) { // Upper body
      return Colors.green;
    } else { // Lower body
      return Colors.blue;
    }
  }
  
  // Helper method to safely convert the landmarks data from native to Flutter
  List<Map<String, dynamic>> _convertLandmarksData(dynamic rawLandmarks) {
    final List<Map<String, dynamic>> result = [];
    
    try {
      if (rawLandmarks is List) {
        for (final landmark in rawLandmarks) {
          if (landmark is Map) {
            // Create a clean Map<String, dynamic> with explicit type casting
            final Map<String, dynamic> landmarkMap = {
              'x': _toDouble(landmark['x']),
              'y': _toDouble(landmark['y']),
              'z': _toDouble(landmark['z']),
              'visibility': _toDouble(landmark['visibility']),
            };
            result.add(landmarkMap);
          }
        }
      }
    } catch (e) {
      print('Error converting landmark data: $e');
    }
    
    return result;
  }
  
  // Helper method to safely convert values to double
  double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Pose Detection'),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 400,
              padding: const EdgeInsets.all(16.0),
              child: _buildPreview(),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.image),
                    label: const Text('Image'),
                  ),
                  ElevatedButton.icon(
                    onPressed: _pickVideo,
                    icon: const Icon(Icons.video_library),
                    label: const Text('Video'),
                  ),
                  ElevatedButton.icon(
                    onPressed: _startLiveDetection,
                    icon: const Icon(Icons.camera),
                    label: const Text('Camera'),
                  ),
                ],
              ),
            ),
              if (_landmarks != null && _landmarks!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Pose Landmarks',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Detected ${_landmarks!.length} landmarks',
                              style: const TextStyle(fontSize: 14),
                            ),
                            if (_inferenceTime != null)
                              Text(
                                'Inference time: ${_inferenceTime!}ms',
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                          ],
                        ),
                        const Divider(),
                        _buildLandmarksVisualizer(),
                        const SizedBox(height: 12),
                        const Text(
                          'Landmarks Data:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        SizedBox(
                          height: 200,
                          child: ListView.builder(
                            itemCount: _landmarks!.length,
                            itemBuilder: (context, index) {
                              final landmark = _landmarks![index];
                              final landmarkName = _getPoseLandmarkName(index);
                              return ListTile(
                                dense: true,
                                title: Text(landmarkName),
                                subtitle: Text(
                                  'x: ${landmark['x']?.toStringAsFixed(2)}, '
                                  'y: ${landmark['y']?.toStringAsFixed(2)}, '
                                  'z: ${landmark['z']?.toStringAsFixed(2)}, '
                                  'visibility: ${landmark['visibility']?.toStringAsFixed(2)}'
                                ),
                                leading: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: _getLandmarkColor(index),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(child: Text('${index}', style: TextStyle(color: Colors.white, fontSize: 12))),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildPreview() {
    if (_isLiveDetection && _isCameraInitialized) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CameraPreview(_cameraController!),
      );
    } else if (_imageFile != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          _imageFile!,
          fit: BoxFit.cover,
        ),
      );
    } else if (_videoPath != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          color: Colors.black,
          child: const Center(
            child: Icon(Icons.video_file, size: 64, color: Colors.white),
          ),
        ),
      );
    } else {
      return Container(
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Text('Select an image, video, or use camera'),
        ),
      );
    }
  }
}
