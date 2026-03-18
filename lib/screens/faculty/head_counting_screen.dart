import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// AR Head Counting Screen
/// Uses Google ML Kit Face Detection with world-space AR tracking
/// to count heads progressively without duplicate counting,
/// even during 180-degree camera sweeps.
class HeadCountingScreen extends StatefulWidget {
  const HeadCountingScreen({super.key});

  @override
  State<HeadCountingScreen> createState() => _HeadCountingScreenState();
}

class _HeadCountingScreenState extends State<HeadCountingScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isProcessing = false;
  bool _isCounting = false;

  // Face Detection - with landmarks for better tracking
  late FaceDetector _faceDetector;
  List<Face> _faces = [];

  // AR World-Space Tracking System
  final _ARWorldTracker _worldTracker = _ARWorldTracker();
  int _totalHeadCount = 0;

  // Accumulated rotation from device sensors
  double _accumulatedYaw = 0.0; // Horizontal rotation (left-right sweep)
  double _lastYaw = 0.0;
  static const EventChannel _rotationChannel = EventChannel('rotation_vector');
  StreamSubscription? _rotationSubscription;

  // Fallback: Track frame-to-frame face movement
  List<_FrameFace> _lastFrameFaces = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeFaceDetector();
    _initializeCamera();
    _initializeRotationSensor();
  }

  void _initializeFaceDetector() {
    final options = FaceDetectorOptions(
      enableTracking: true,
      enableLandmarks: true, // Enable landmarks for face signature
      enableContours: false,
      enableClassification: false,
      performanceMode: FaceDetectorMode.fast,
      minFaceSize: 0.15,
    );
    _faceDetector = FaceDetector(options: options);
  }

  void _initializeRotationSensor() {
    // Try to use platform rotation sensor for world-space tracking
    // This is a best-effort approach - if not available, we fall back to frame tracking
    try {
      _rotationSubscription = _rotationChannel.receiveBroadcastStream().listen(
        (data) {
          if (data is List && data.length >= 3) {
            final yaw = (data[0] as num).toDouble();
            if (_isCounting) {
              // Track rotation delta
              final delta = yaw - _lastYaw;
              if (delta.abs() < math.pi) {
                // Avoid wrap-around jumps
                _accumulatedYaw += delta;
              }
              _lastYaw = yaw;
            }
          }
        },
        onError: (e) {
          // Sensor not available, will use fallback tracking
        },
      );
    } catch (e) {
      // Platform channel not available
    }
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        _showError('No cameras available');
        return;
      }

      final backCamera = _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );

      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );

      await _cameraController!.initialize();

      if (mounted) {
        setState(() => _isInitialized = true);
      }
    } catch (e) {
      _showError('Failed to initialize camera: $e');
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _startCounting() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    setState(() {
      _isCounting = true;
      _totalHeadCount = 0;
      _accumulatedYaw = 0.0;
      _lastYaw = 0.0;
      _lastFrameFaces = [];
      _faces = [];
    });

    _worldTracker.reset();

    await _cameraController!.startImageStream(_processImage);
  }

  Future<void> _stopCounting() async {
    if (_cameraController != null &&
        _cameraController!.value.isStreamingImages) {
      await _cameraController!.stopImageStream();
    }

    setState(() {
      _isCounting = false;
      _faces = [];
    });
  }

  Future<void> _processImage(CameraImage image) async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final inputImage = _convertCameraImage(image);
      if (inputImage == null) {
        _isProcessing = false;
        return;
      }

      final faces = await _faceDetector.processImage(inputImage);

      if (mounted) {
        _processDetectedFaces(faces, image.width.toDouble(), image.height.toDouble());
        setState(() {
          _faces = faces;
        });
      }
    } catch (e) {
      // Handle processing error silently
    }

    _isProcessing = false;
  }

  void _processDetectedFaces(List<Face> faces, double imageWidth, double imageHeight) {
    final currentFrameFaces = <_FrameFace>[];

    for (final face in faces) {
      // Create face signature using multiple features
      final signature = _FaceSignature.fromFace(face, imageWidth, imageHeight);

      // Calculate world-space position based on camera yaw
      final worldX = _calculateWorldX(face.boundingBox, imageWidth);

      // Check if this face was already counted
      final isNew = _worldTracker.tryAddFace(
        signature: signature,
        worldX: worldX,
        screenX: face.boundingBox.center.dx / imageWidth,
        screenY: face.boundingBox.center.dy / imageHeight,
        trackingId: face.trackingId,
        lastFrameFaces: _lastFrameFaces,
      );

      if (isNew) {
        _totalHeadCount++;
      }

      currentFrameFaces.add(_FrameFace(
        signature: signature,
        screenX: face.boundingBox.center.dx / imageWidth,
        screenY: face.boundingBox.center.dy / imageHeight,
        trackingId: face.trackingId,
        worldX: worldX,
      ));
    }

    _lastFrameFaces = currentFrameFaces;
  }

  double _calculateWorldX(Rect boundingBox, double imageWidth) {
    // Convert screen position to world-space using accumulated yaw
    // Screen center = 0, left edge = -0.5, right edge = 0.5
    final screenX = (boundingBox.center.dx / imageWidth) - 0.5;

    // Assume ~60 degree horizontal field of view
    const hFovRadians = 60 * math.pi / 180;
    final angleInFrame = screenX * hFovRadians;

    // World X = accumulated yaw + angle within frame
    return _accumulatedYaw + angleInFrame;
  }

  InputImage? _convertCameraImage(CameraImage image) {
    if (_cameraController == null) return null;

    final camera = _cameraController!.description;
    final sensorOrientation = camera.sensorOrientation;

    InputImageRotation? rotation;
    rotation = InputImageRotation.values.firstWhere(
      (r) => r.rawValue == sensorOrientation,
      orElse: () => InputImageRotation.rotation0deg,
    );

    final format = InputImageFormat.nv21;
    final plane = image.planes.first;

    final imageMetadata = InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: format,
      bytesPerRow: plane.bytesPerRow,
    );

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: imageMetadata,
    );
  }

  void _resetCount() {
    setState(() {
      _totalHeadCount = 0;
      _accumulatedYaw = 0.0;
      _lastYaw = 0.0;
      _lastFrameFaces = [];
    });
    _worldTracker.reset();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      _stopCounting();
      _cameraController?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _rotationSubscription?.cancel();
    _stopCounting();
    _cameraController?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('AR Head Counter'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_isCounting)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _resetCount,
              tooltip: 'Reset Count',
            ),
        ],
      ),
      body: Column(
        children: [
          // Camera Preview with AR overlay
          Expanded(
            child: _isInitialized && _cameraController != null
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        child: CameraPreview(_cameraController!),
                      ),
                      if (_isCounting)
                        CustomPaint(
                          painter: _FaceMarkerPainter(
                            faces: _faces,
                            imageSize: Size(
                              _cameraController!.value.previewSize?.height ?? 1.0,
                              _cameraController!.value.previewSize?.width ?? 1.0,
                            ),
                            screenSize: MediaQuery.of(context).size,
                            isFrontCamera: _cameraController!.description.lensDirection ==
                                CameraLensDirection.front,
                            worldTracker: _worldTracker,
                          ),
                        ),
                      if (_isCounting)
                        Positioned(
                          top: 16,
                          left: 16,
                          right: 16,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color.fromRGBO(0, 0, 0, 0.7),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.pan_tool, color: Colors.blue.shade300, size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Slowly sweep camera across the room. Each person is only counted once.',
                                        style: TextStyle(
                                          color: Colors.white.withAlpha(230),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                // World tracking indicator
                                Row(
                                  children: [
                                    Icon(Icons.explore, color: Colors.green.shade300, size: 16),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Tracked: ${_worldTracker.trackedFaceCount} unique faces',
                                      style: TextStyle(
                                        color: Colors.green.shade300,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (!_isCounting)
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: const Color.fromRGBO(0, 0, 0, 0.6),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.face, size: 64, color: Colors.blue.shade300),
                                const SizedBox(height: 16),
                                const Text(
                                  'Ready to Count Heads',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Tap Start to begin counting',
                                  style: TextStyle(
                                    color: Colors.white.withAlpha(179),
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  )
                : const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Colors.white),
                        SizedBox(height: 16),
                        Text('Initializing Camera...', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
          ),

          // Bottom Controls
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey.shade900,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  // Head Count Display
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.blue.shade700, Colors.blue.shade500],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.withAlpha(77),
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.people, color: Colors.white, size: 32),
                        const SizedBox(width: 16),
                        Column(
                          children: [
                            Text(
                              '$_totalHeadCount',
                              style: const TextStyle(
                                fontSize: 48,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              'Heads Counted',
                              style: TextStyle(
                                color: Colors.white.withAlpha(204),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  if (_isCounting)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade800,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _StatusChip(
                            icon: Icons.visibility,
                            label: '${_faces.length} in view',
                            color: _faces.isNotEmpty ? Colors.green : Colors.grey,
                          ),
                          _StatusChip(
                            icon: Icons.memory,
                            label: '${_worldTracker.trackedFaceCount} tracked',
                            color: Colors.blue,
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isInitialized
                          ? (_isCounting ? _stopCounting : _startCounting)
                          : null,
                      icon: Icon(_isCounting ? Icons.stop : Icons.play_arrow, size: 28),
                      label: Text(
                        _isCounting ? 'Stop Counting' : 'Start Counting',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isCounting ? Colors.red.shade600 : Colors.green.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Status chip widget for displaying tracking info
class _StatusChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatusChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Icon(icon, color: Colors.white.withAlpha(179), size: 16),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: Colors.white.withAlpha(204))),
      ],
    );
  }
}

/// AR World Tracker - Maintains a world-space memory of counted faces
class _ARWorldTracker {
  final List<_WorldFace> _worldFaces = [];

  // Thresholds for duplicate detection
  static const double _worldXThreshold = 0.3; // ~18 degrees
  static const double _screenPositionThreshold = 0.15; // 15% of screen
  static const double _signatureSimilarityThreshold = 0.6; // 60% similarity

  int get trackedFaceCount => _worldFaces.length;

  void reset() {
    _worldFaces.clear();
  }

  /// Try to add a face. Returns true if it's a new face, false if duplicate.
  bool tryAddFace({
    required _FaceSignature signature,
    required double worldX,
    required double screenX,
    required double screenY,
    required int? trackingId,
    required List<_FrameFace> lastFrameFaces,
  }) {
    // Strategy 1: Check if we have an active tracking ID match
    if (trackingId != null) {
      final existingByTrackId = _worldFaces.where((wf) => wf.trackingId == trackingId);
      if (existingByTrackId.isNotEmpty) {
        // Update position for this tracked face
        existingByTrackId.first.updatePosition(worldX, screenX, screenY);
        return false; // Already counted
      }
    }

    // Strategy 2: Check if this face existed in the last frame (continuity tracking)
    for (final lastFace in lastFrameFaces) {
      final screenDist = _screenDistance(screenX, screenY, lastFace.screenX, lastFace.screenY);
      if (screenDist < _screenPositionThreshold) {
        // This face was in the last frame, check if it was already counted
        final matchingWorld = _findMatchingWorldFace(lastFace.worldX, signature);
        if (matchingWorld != null) {
          matchingWorld.updatePosition(worldX, screenX, screenY);
          if (trackingId != null) matchingWorld.trackingId = trackingId;
          return false; // Already counted
        }
      }
    }

    // Strategy 3: Check world-space + signature similarity
    final matchingWorld = _findMatchingWorldFace(worldX, signature);
    if (matchingWorld != null) {
      matchingWorld.updatePosition(worldX, screenX, screenY);
      if (trackingId != null) matchingWorld.trackingId = trackingId;
      return false; // Already counted
    }

    // Strategy 4: Check if any world face has very similar signature (regardless of position)
    // This catches cases where the same person appears but world tracking drifted
    for (final wf in _worldFaces) {
      if (signature.similarityTo(wf.signature) > 0.8) {
        // Very high similarity = same person
        wf.updatePosition(worldX, screenX, screenY);
        if (trackingId != null) wf.trackingId = trackingId;
        return false;
      }
    }

    // This is a new face - add to world tracking
    _worldFaces.add(_WorldFace(
      worldX: worldX,
      screenX: screenX,
      screenY: screenY,
      signature: signature,
      trackingId: trackingId,
    ));

    return true; // New face counted!
  }

  _WorldFace? _findMatchingWorldFace(double worldX, _FaceSignature signature) {
    for (final wf in _worldFaces) {
      final worldDist = (wf.worldX - worldX).abs();
      final similarity = signature.similarityTo(wf.signature);

      // Match if world position is close AND signature is similar
      if (worldDist < _worldXThreshold && similarity > _signatureSimilarityThreshold) {
        return wf;
      }
    }
    return null;
  }

  double _screenDistance(double x1, double y1, double x2, double y2) {
    return math.sqrt(math.pow(x1 - x2, 2) + math.pow(y1 - y2, 2));
  }

  /// Get tracking status for a face at the given screen position
  bool isTrackedAt(double screenX, double screenY) {
    for (final wf in _worldFaces) {
      final dist = _screenDistance(screenX, screenY, wf.lastScreenX, wf.lastScreenY);
      if (dist < _screenPositionThreshold) {
        return true;
      }
    }
    return false;
  }
}

/// Represents a face stored in world space
class _WorldFace {
  double worldX;
  double lastScreenX;
  double lastScreenY;
  _FaceSignature signature;
  int? trackingId;
  DateTime lastSeen;

  _WorldFace({
    required this.worldX,
    required double screenX,
    required double screenY,
    required this.signature,
    this.trackingId,
  })  : lastScreenX = screenX,
        lastScreenY = screenY,
        lastSeen = DateTime.now();

  void updatePosition(double newWorldX, double screenX, double screenY) {
    // Smooth world position update
    worldX = worldX * 0.7 + newWorldX * 0.3;
    lastScreenX = screenX;
    lastScreenY = screenY;
    lastSeen = DateTime.now();
  }
}

/// Face from the previous frame for continuity tracking
class _FrameFace {
  final _FaceSignature signature;
  final double screenX;
  final double screenY;
  final int? trackingId;
  final double worldX;

  _FrameFace({
    required this.signature,
    required this.screenX,
    required this.screenY,
    required this.trackingId,
    required this.worldX,
  });
}

/// Face signature using geometric features for identity matching
class _FaceSignature {
  final double aspectRatio; // width / height
  final double relativeSize; // size relative to frame
  final double? leftEyeRelX;
  final double? leftEyeRelY;
  final double? rightEyeRelX;
  final double? rightEyeRelY;
  final double? noseRelX;
  final double? noseRelY;
  final double? mouthRelX;
  final double? mouthRelY;

  _FaceSignature({
    required this.aspectRatio,
    required this.relativeSize,
    this.leftEyeRelX,
    this.leftEyeRelY,
    this.rightEyeRelX,
    this.rightEyeRelY,
    this.noseRelX,
    this.noseRelY,
    this.mouthRelX,
    this.mouthRelY,
  });

  factory _FaceSignature.fromFace(Face face, double imageWidth, double imageHeight) {
    final bbox = face.boundingBox;
    final aspectRatio = bbox.width / bbox.height;
    final relativeSize = (bbox.width * bbox.height) / (imageWidth * imageHeight);

    // Extract landmark positions relative to bounding box
    double? leftEyeX, leftEyeY, rightEyeX, rightEyeY;
    double? noseX, noseY, mouthX, mouthY;

    final leftEye = face.landmarks[FaceLandmarkType.leftEye];
    if (leftEye != null) {
      leftEyeX = (leftEye.position.x - bbox.left) / bbox.width;
      leftEyeY = (leftEye.position.y - bbox.top) / bbox.height;
    }

    final rightEye = face.landmarks[FaceLandmarkType.rightEye];
    if (rightEye != null) {
      rightEyeX = (rightEye.position.x - bbox.left) / bbox.width;
      rightEyeY = (rightEye.position.y - bbox.top) / bbox.height;
    }

    final nose = face.landmarks[FaceLandmarkType.noseBase];
    if (nose != null) {
      noseX = (nose.position.x - bbox.left) / bbox.width;
      noseY = (nose.position.y - bbox.top) / bbox.height;
    }

    final mouth = face.landmarks[FaceLandmarkType.bottomMouth];
    if (mouth != null) {
      mouthX = (mouth.position.x - bbox.left) / bbox.width;
      mouthY = (mouth.position.y - bbox.top) / bbox.height;
    }

    return _FaceSignature(
      aspectRatio: aspectRatio,
      relativeSize: relativeSize,
      leftEyeRelX: leftEyeX,
      leftEyeRelY: leftEyeY,
      rightEyeRelX: rightEyeX,
      rightEyeRelY: rightEyeY,
      noseRelX: noseX,
      noseRelY: noseY,
      mouthRelX: mouthX,
      mouthRelY: mouthY,
    );
  }

  /// Calculate similarity score between two face signatures (0 to 1)
  double similarityTo(_FaceSignature other) {
    double score = 0;
    int features = 0;

    // Aspect ratio similarity (faces have consistent proportions)
    final aspectDiff = (aspectRatio - other.aspectRatio).abs();
    score += 1 - (aspectDiff / 0.5).clamp(0, 1);
    features++;

    // Relative size similarity (not too strict due to distance changes)
    final sizeDiff = (relativeSize - other.relativeSize).abs();
    final maxSize = math.max(relativeSize, other.relativeSize);
    if (maxSize > 0) {
      score += 1 - (sizeDiff / maxSize).clamp(0, 1) * 0.5;
      features++;
    }

    // Landmark positions (if available)
    if (leftEyeRelX != null && other.leftEyeRelX != null) {
      final dist = _dist(leftEyeRelX!, leftEyeRelY!, other.leftEyeRelX!, other.leftEyeRelY!);
      score += 1 - (dist / 0.3).clamp(0, 1);
      features++;
    }

    if (rightEyeRelX != null && other.rightEyeRelX != null) {
      final dist = _dist(rightEyeRelX!, rightEyeRelY!, other.rightEyeRelX!, other.rightEyeRelY!);
      score += 1 - (dist / 0.3).clamp(0, 1);
      features++;
    }

    if (noseRelX != null && other.noseRelX != null) {
      final dist = _dist(noseRelX!, noseRelY!, other.noseRelX!, other.noseRelY!);
      score += 1 - (dist / 0.3).clamp(0, 1);
      features++;
    }

    if (mouthRelX != null && other.mouthRelX != null) {
      final dist = _dist(mouthRelX!, mouthRelY!, other.mouthRelX!, other.mouthRelY!);
      score += 1 - (dist / 0.3).clamp(0, 1);
      features++;
    }

    return features > 0 ? score / features : 0;
  }

  double _dist(double x1, double y1, double x2, double y2) {
    return math.sqrt(math.pow(x1 - x2, 2) + math.pow(y1 - y2, 2));
  }
}

/// Custom painter for face markers with tracking status
class _FaceMarkerPainter extends CustomPainter {
  final List<Face> faces;
  final Size imageSize;
  final Size screenSize;
  final bool isFrontCamera;
  final _ARWorldTracker worldTracker;

  _FaceMarkerPainter({
    required this.faces,
    required this.imageSize,
    required this.screenSize,
    required this.isFrontCamera,
    required this.worldTracker,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (final face in faces) {
      final rect = face.boundingBox;
      final scaleX = size.width / imageSize.width;
      final scaleY = size.height / imageSize.height;

      double left = rect.left * scaleX;
      double top = rect.top * scaleY;
      double right = rect.right * scaleX;
      double bottom = rect.bottom * scaleY;

      if (isFrontCamera) {
        final temp = left;
        left = size.width - right;
        right = size.width - temp;
      }

      final markerX = (left + right) / 2;
      final markerY = top - 10;

      // Draw the 🔻 emoji marker
      textPainter.text = const TextSpan(text: '🔻', style: TextStyle(fontSize: 28));
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(markerX - textPainter.width / 2, markerY - textPainter.height),
      );

      // Draw bounding box (green for new detection, blue for tracked)
      final isTracked = worldTracker.isTrackedAt(
        (left + right) / 2 / size.width,
        (top + bottom) / 2 / size.height,
      );

      final boxPaint = Paint()
        ..color = isTracked ? Colors.green.withAlpha(150) : Colors.blue.withAlpha(100)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(left, top, right, bottom),
          const Radius.circular(8),
        ),
        boxPaint,
      );

      // Draw a small "COUNTED" label for tracked faces
      if (isTracked) {
        textPainter.text = TextSpan(
          text: ' ✓ ',
          style: TextStyle(
            fontSize: 10,
            color: Colors.white,
            backgroundColor: Colors.green.withAlpha(200),
          ),
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(left, bottom + 2));
      }
    }
  }

  @override
  bool shouldRepaint(_FaceMarkerPainter oldDelegate) => true;
}
