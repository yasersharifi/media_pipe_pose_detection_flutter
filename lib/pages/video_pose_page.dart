import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

class VideoPosePage extends StatefulWidget {
  const VideoPosePage({Key? key}) : super(key: key);

  @override
  State<VideoPosePage> createState() => _VideoPosePageState();
}

class _VideoPosePageState extends State<VideoPosePage> {
  static const platform = MethodChannel('com.example.last_native_pose_detection/pose_detection');
  
  final ImagePicker _picker = ImagePicker();
  String? _videoPath;
  List<Map<String, dynamic>>? _landmarks;
  int? _inferenceTime;
  bool _isProcessing = false;
  
  // Video player controllers
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool _isVideoInitialized = false;
  
  @override
  void dispose() {
    _disposeVideoControllers();
    super.dispose();
  }
  
  void _disposeVideoControllers() {
    _chewieController?.dispose();
    _videoPlayerController?.dispose();
    _isVideoInitialized = false;
  }
  
  Future<void> _pickVideo() async {
    setState(() {
      _isProcessing = true;
      _landmarks = null;
      _inferenceTime = null;
    });
    
    // Dispose existing video controllers
    _disposeVideoControllers();
    
    try {
      final XFile? video = await _picker.pickVideo(source: ImageSource.gallery);
      
      if (video != null) {
        print('Video picked: ${video.path}');
        final videoFile = File(video.path);
        
        if (await videoFile.exists()) {
          print('Video file exists, size: ${await videoFile.length()} bytes');
          
          setState(() {
            _videoPath = video.path;
          });
          
          // Initialize video player
          await _initializeVideoPlayer(_videoPath!);
          
          // Show loading indicator
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Processing video...'))
          );
          
          await _processPoseFromVideo(_videoPath!);
        } else {
          print('Video file does not exist: ${video.path}');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Selected video file could not be accessed'))
          );
        }
      }
    } catch (e) {
      print('Error picking video: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking video: $e'))
      );
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }
  
  Future<void> _initializeVideoPlayer(String videoPath) async {
    try {
      // Create video player controller
      final videoPlayerController = VideoPlayerController.file(File(videoPath));
      await videoPlayerController.initialize();
      
      // Create chewie controller
      final chewieController = ChewieController(
        videoPlayerController: videoPlayerController,
        aspectRatio: videoPlayerController.value.aspectRatio,
        autoPlay: false,
        looping: false,
        showControls: true,
        placeholder: const Center(child: CircularProgressIndicator()),
        autoInitialize: true,
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Text(
              'Error loading video: $errorMessage',
              style: const TextStyle(color: Colors.white),
            ),
          );
        },
      );
      
      setState(() {
        _videoPlayerController = videoPlayerController;
        _chewieController = chewieController;
        _isVideoInitialized = true;
      });
      
      print('Video player initialized successfully');
    } catch (e) {
      print('Error initializing video player: $e');
      setState(() {
        _isVideoInitialized = false;
      });
    }
  }
  
  Future<void> _processPoseFromVideo(String videoPath) async {
    try {
      final result = await platform.invokeMethod('processVideo', {
        'videoPath': videoPath,
      });
      
      // Handle the result properly with type casting
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
          print('Video pose detection: ${_landmarks!.length} landmarks found');
          print('Inference time: ${_inferenceTime}ms');
          
          // Log detailed landmark information
          if (_landmarks!.isNotEmpty) {
            print('Landmark details:');
            for (int i = 0; i < _landmarks!.length; i++) {
              print('Landmark $i: ${_landmarks![i]}');
            }
          }
        } else {
          _landmarks = [];
          _inferenceTime = 0;
          print('No landmarks detected in video');
        }
      });
    } on PlatformException catch (e) {
      print('Error processing video: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error processing video: ${e.message}'))
      );
    } catch (e) {
      print('Unexpected error processing video: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unexpected error processing video: $e'))
      );
    }
  }
  
  Widget _buildVideoPreview() {
    if (_videoPath != null && _isVideoInitialized && _chewieController != null) {
      return Chewie(controller: _chewieController!);
    } else if (_videoPath != null) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text('Loading video...', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
    } else {
      return Container(
        color: Colors.grey[300],
        child: const Center(
          child: Text('No video selected'),
        ),
      );
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Video Pose Detection'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
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
                child: _buildVideoPreview(),
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
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton(
              onPressed: _isProcessing ? null : _pickVideo,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                minimumSize: const Size.fromHeight(50),
              ),
              child: _isProcessing
                ? const CircularProgressIndicator()
                : const Text('Pick Video', style: TextStyle(fontSize: 18)),
            ),
          ),
        ],
      ),
    );
  }
}
