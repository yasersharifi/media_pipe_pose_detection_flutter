import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

class ImagePosePage extends StatefulWidget {
  const ImagePosePage({Key? key}) : super(key: key);

  @override
  State<ImagePosePage> createState() => _ImagePosePageState();
}

class _ImagePosePageState extends State<ImagePosePage> {
  static const platform = MethodChannel('com.example.last_native_pose_detection/pose_detection');
  
  final ImagePicker _picker = ImagePicker();
  File? _imageFile;
  List<Map<String, dynamic>>? _landmarks;
  int? _inferenceTime;
  bool _isProcessing = false;
  
  Future<void> _pickImage() async {
    setState(() {
      _isProcessing = true;
      _landmarks = null;
      _inferenceTime = null;
    });
    
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      
      if (image != null) {
        final imageFile = File(image.path);
        
        setState(() {
          _imageFile = imageFile;
        });
        
        await _processPoseFromImage(imageFile.path);
      }
    } catch (e) {
      print('Error picking image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking image: $e'))
      );
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }
  
  Future<void> _processPoseFromImage(String imagePath) async {
    try {
      final result = await platform.invokeMethod('processImage', {
        'imagePath': imagePath,
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
          print('Image pose detection: ${_landmarks!.length} landmarks found');
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
          print('No landmarks detected');
        }
      });
    } on PlatformException catch (e) {
      print('Error processing image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error processing image: ${e.message}'))
      );
    } catch (e) {
      print('Unexpected error processing image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unexpected error processing image: $e'))
      );
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Image Pose Detection'),
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
              child: _imageFile == null
                ? const Center(child: Text('No image selected'))
                : ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      _imageFile!,
                      fit: BoxFit.contain,
                    ),
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
              onPressed: _isProcessing ? null : _pickImage,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                minimumSize: const Size.fromHeight(50),
              ),
              child: _isProcessing
                ? const CircularProgressIndicator()
                : const Text('Pick Image', style: TextStyle(fontSize: 18)),
            ),
          ),
        ],
      ),
    );
  }
}
