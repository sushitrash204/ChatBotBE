import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../models/message.dart';
import '../services/chat_service.dart';
import '../services/auth_service.dart';
import '../providers/auth_provider.dart';
import 'login_screen.dart';

class VoiceChatScreen extends StatefulWidget {
  final Function(VoidCallback)? onNewChatRequested;

  const VoiceChatScreen({super.key, this.onNewChatRequested});

  @override
  State<VoiceChatScreen> createState() => _VoiceChatScreenState();
}

class _VoiceChatScreenState extends State<VoiceChatScreen> with TickerProviderStateMixin {
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  final ChatService _chatService = ChatService();
  final AuthService _authService = AuthService();
  final List<Message> _messages = [];

  bool _isRecorderInitialized = false;
  bool _isPlayerInitialized = false;
  bool _isRecording = false;
  bool _isPlaying = false;
  bool _isLoading = false;
  bool _isLoggedIn = false;
  String? _recordingPath;
  String _userText = '';
  String _aiText = '';

  // --- Animation Controllers ---
  late AnimationController _bgController;
  late AnimationController _pulseController;
  late AnimationController _waveController;
  late AnimationController _shimmerController;
  late AnimationController _rippleController; // Dedicated controller for ripple

  Offset _touchPosition = Offset.zero;
  Color _touchColor = Colors.blue; // Random color for each touch

  void _newChat() {
    setState(() {
      _messages.clear();
      _userText = '';
      _aiText = '';
    });
  }

  @override
  void initState() {
    super.initState();
    _initRecorder();
    _initPlayer();
    _checkLogin();
    widget.onNewChatRequested?.call(_newChat);

    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat(reverse: true);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 40),
    )..repeat();

    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat();

    // Ripple controller - does NOT repeat, triggered manually
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500), // Slower fade-out
    );
  }

  void _triggerRipple(Offset position) {
    final random = math.Random();
    setState(() {
      _touchPosition = position;
      // Randomly pick between blue or red
      _touchColor = random.nextBool() 
          ? const Color(0xFF448AFF) // Blue
          : const Color(0xFFFF1744); // Red
    });
    // Restart animation from 0
    _rippleController.forward(from: 0.0);
  }

  Future<void> _checkLogin() async {
    final loggedIn = await _authService.isLoggedIn();
    setState(() => _isLoggedIn = loggedIn);
  }

  Future<void> _initRecorder() async {
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission denied')),
      );
      return;
    }
    await _recorder.openRecorder();
    setState(() => _isRecorderInitialized = true);
  }

  Future<void> _initPlayer() async {
    await _player.openPlayer();
    setState(() => _isPlayerInitialized = true);
  }

  Future<void> _startRecording() async {
    if (!_isRecorderInitialized) return;
    final dir = await getTemporaryDirectory();
    _recordingPath = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.wav';
    await _recorder.startRecorder(toFile: _recordingPath, codec: Codec.pcm16WAV);
    setState(() {
      _isRecording = true;
      _userText = 'Recording...';
    });
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    await _recorder.stopRecorder();
    setState(() {
      _isRecording = false;
      _isLoading = true;
      _userText = 'Processing...';
    });
    await _sendVoiceMessage('Hello from voice chat');
  }

  Future<void> _sendVoiceMessage(String text) async {
    try {
      final response = await _chatService.sendVoiceMessage(
        text,
        _messages,
        voice: 'Charon',
        language: 'vi',
      );
      setState(() {
        _userText = text;
        _aiText = response['text'];
        _messages.add(Message(role: 'user', text: text));
        _messages.add(Message(role: 'model', text: response['text']));
        _isLoading = false;
      });
      if (response['audio'] != null) {
        await _playAudioResponse(response['audio']);
      }
    } catch (e) {
      setState(() {
        _aiText = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _playAudioResponse(String base64Audio) async {
    if (!_isPlayerInitialized) return;
    try {
      final bytes = base64Decode(base64Audio);
      final dir = await getTemporaryDirectory();
      final audioPath = '${dir.path}/response_${DateTime.now().millisecondsSinceEpoch}.wav';
      final file = File(audioPath);
      await file.writeAsBytes(bytes);

      setState(() => _isPlaying = true);
      await _player.startPlayer(
        fromURI: audioPath,
        whenFinished: () {
          setState(() => _isPlaying = false);
          file.delete();
        },
      );
    } catch (e) {
      setState(() => _isPlaying = false);
      print('Error playing audio: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final isLoggedIn = authProvider.isLoggedIn;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('🎙️ Voice Chat', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: isLoggedIn
                ? IconButton(
                    icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                    onPressed: () async {
                      await authProvider.logout();
                    },
                  )
                : _buildGradientLoginButton(),
          ),
        ],
      ),
      body: Stack(
        children: [
          Container(color: const Color(0xFF0A0B11)),

          AnimatedBuilder(
            animation: _waveController,
            builder: (context, _) {
              return CustomPaint(
                painter: MinimalWavesPainter(_waveController.value),
                size: Size.infinite,
              );
            },
          ),

          GestureDetector(
            onTapDown: (details) => _triggerRipple(details.localPosition),
            onPanDown: (details) => _triggerRipple(details.localPosition),
            child: Stack(
              children: [
                AnimatedBuilder(
                  animation: _bgController,
                  builder: (context, child) {
                    return Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          stops: [0.0, 0.5, 1.0],
                          colors: [
                            const Color(0xFF0F1014).withOpacity(0.3),
                            Color.lerp(const Color(0xFF1A1C23), const Color(0xFF252936), _bgController.value)!.withOpacity(0.2),
                            const Color(0xFF0F1014).withOpacity(0.3),
                          ],
                        ),
                      ),
                    );
                  },
                ),

                AnimatedBuilder(
                  animation: _rippleController,
                  builder: (context, _) {
                    return CustomPaint(
                      painter: TouchRipplePainter(
                        _touchPosition,
                        _rippleController.value,
                        _touchColor,
                      ),
                      child: Container(),
                    );
                  },
                ),

                SafeArea(
                  child: Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              AnimatedBuilder(
                                animation: _pulseController,
                                builder: (context, child) {
                                  double pulse = (_isRecording || _isPlaying) ? _pulseController.value * 20 : 0;
                                  return Container(
                                    width: 200 + pulse,
                                    height: 200 + pulse,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: LinearGradient(
                                        colors: _isRecording || _isPlaying
                                            ? [const Color(0xFF667EEA), const Color(0xFF764BA2)]
                                            : [Colors.grey.shade800, Colors.grey.shade700],
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: (_isRecording || _isPlaying ? const Color(0xFF667EEA) : Colors.black)
                                              .withOpacity(0.5),
                                          blurRadius: 30 + pulse,
                                          spreadRadius: 5 + (pulse / 2),
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      _isRecording ? Icons.mic : _isPlaying ? Icons.volume_up : Icons.mic_none,
                                      size: 80,
                                      color: Colors.white,
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 50),
                              if (_userText.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 32),
                                  child: Text(_userText,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(color: Colors.white70, fontSize: 16)),
                                ),
                              const SizedBox(height: 20),
                              if (_aiText.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 32),
                                  child: Text(_aiText,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500)),
                                ),
                              if (_isLoading)
                                const Padding(
                                  padding: EdgeInsets.only(top: 20),
                                  child: CircularProgressIndicator(color: Color(0xFF667EEA)),
                                ),
                            ],
                          ),
                        ),
                      ),

                      Container(
                        padding: const EdgeInsets.all(32),
                        child: GestureDetector(
                          onLongPressStart: (_) => _startRecording(),
                          onLongPressEnd: (_) => _stopRecording(),
                          child: AnimatedScale(
                            duration: const Duration(milliseconds: 200),
                            scale: _isRecording ? 1.2 : 1.0,
                            child: Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: _isRecording
                                      ? [Colors.red.shade400, Colors.red.shade600]
                                      : [const Color(0xFF667EEA), const Color(0xFF764BA2)],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: (_isRecording ? Colors.red : const Color(0xFF667EEA)).withOpacity(0.4),
                                    blurRadius: 20,
                                    spreadRadius: 5,
                                  ),
                                ],
                              ),
                              child: Icon(_isRecording ? Icons.stop : Icons.mic, size: 40, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: Text(_isRecording ? 'Release to send' : 'Hold to speak',
                            style: const TextStyle(color: Colors.grey, fontSize: 14)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Nút Login với Premium Shimmer Effect
  Widget _buildGradientLoginButton() {
    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, _) {
        final shimmerValue = _shimmerController.value;
        final curvedValue = Curves.easeInOutCubic.transform(shimmerValue);
        
        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => LoginScreen()),
          ),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            height: 44,
            width: 110,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              gradient: const LinearGradient(
                colors: [Color(0xFF448AFF), Color(0xFFFF1744)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: Color.lerp(
                    const Color(0xFF448AFF),
                    const Color(0xFFFF1744),
                    shimmerValue,
                  )!.withOpacity(0.5),
                  blurRadius: 16,
                  spreadRadius: 2,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Shimmer Layer 1 (Primary wave)
                ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: Transform.translate(
                    offset: Offset((curvedValue * 3.5 - 1.2) * 110, 0),
                    child: Container(
                      width: 70,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withOpacity(0.0),
                            Colors.white.withOpacity(0.6),
                            Colors.white.withOpacity(0.0),
                          ],
                          stops: const [0.0, 0.5, 1.0],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                      ),
                    ),
                  ),
                ),
                
                // Shimmer Layer 2 (Secondary trailing wave)
                ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: Transform.translate(
                    offset: Offset((curvedValue * 3.5 - 1.5) * 110, 0),
                    child: Container(
                      width: 40,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withOpacity(0.0),
                            Colors.white.withOpacity(0.3),
                            Colors.white.withOpacity(0.0),
                          ],
                          stops: const [0.0, 0.5, 1.0],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                      ),
                    ),
                  ),
                ),

                // Text with shadow for better contrast
                Text(
                  'Login',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    letterSpacing: 1.0,
                    shadows: [
                      Shadow(
                        color: Colors.black.withOpacity(0.3),
                        offset: const Offset(0, 1),
                        blurRadius: 2,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _bgController.dispose();
    _pulseController.dispose();
    _waveController.dispose();
    _shimmerController.dispose();
    _rippleController.dispose();
    _recorder.closeRecorder();
    _player.closePlayer();
    super.dispose();
  }
}

class TouchRipplePainter extends CustomPainter {
  final Offset position;
  final double opacity;
  final Color baseColor;

  TouchRipplePainter(this.position, this.opacity, this.baseColor);

  @override
  void paint(Canvas canvas, Size size) {
    // Early return if animation is complete or just starting
    if (opacity <= 0 || opacity >= 0.95) return;
    
    final random = math.Random(baseColor.hashCode);
    
    // Create multiple expanding ripple rings (water droplet effect)
    for (int i = 0; i < 8; i++) {
      final delay = i * 0.12;
      final progress = math.max(0.0, math.min(1.0, opacity - delay));
      
      // Skip if this ring hasn't started or is complete
      if (progress <= 0 || progress >= 0.95) continue;

      // Slower, linear expansion for realistic water ripple
      final maxRadius = math.min(size.width, size.height) * 0.8;
      final radius = 30 + (progress * maxRadius);
      
      // Exponential fade-out for smooth disappearance
      final fadeOut = math.pow(1 - progress, 2).toDouble(); // Squared for smoother fade
      final ringOpacity = fadeOut * 0.35;
      
      // Use the base color (blue or red) for all rings
      final ringColor = baseColor;

      // Gradient fill for water effect (center brighter, edge fades)
      final gradient = RadialGradient(
        colors: [
          ringColor.withOpacity(ringOpacity * 0.25), // Reduced from 0.5
          ringColor.withOpacity(ringOpacity * 0.15), // Reduced from 0.3
          ringColor.withOpacity(0.0),
        ],
        stops: const [0.85, 0.95, 1.0],
      );

      final rect = Rect.fromCircle(center: position, radius: radius);
      final paint = Paint()..shader = gradient.createShader(rect);
      
      canvas.drawCircle(position, radius, paint);

      // Stroke outline for wave definition (thinner and more transparent)
      final strokePaint = Paint()
        ..color = ringColor.withOpacity(ringOpacity * 0.5) // Reduced from 0.9
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 + fadeOut * 1.5; // Thinner stroke

      canvas.drawCircle(position, radius, strokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant TouchRipplePainter oldDelegate) =>
      oldDelegate.position != position || 
      oldDelegate.opacity != opacity ||
      oldDelegate.baseColor != baseColor;
}

class MinimalWavesPainter extends CustomPainter {
  final double animationValue;

  MinimalWavesPainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final paintBlue1 = Paint()
      ..color = const Color(0xFF448AFF).withOpacity(0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final paintBlue2 = Paint()
      ..color = const Color(0xFF448AFF).withOpacity(0.20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final paintBlue3 = Paint()
      ..color = const Color(0xFF667EEA).withOpacity(0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    final paintRed1 = Paint()
      ..color = const Color(0xFFFF1744).withOpacity(0.30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final paintRed2 = Paint()
      ..color = const Color(0xFFFF1744).withOpacity(0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    final pathBlue1 = Path();
    final pathBlue2 = Path();
    final pathBlue3 = Path();
    final pathRed1 = Path();
    final pathRed2 = Path();

    final width = size.width;
    final height = size.height;

    // Diagonal wave 1 (Blue) - Top-left to bottom-right
    pathBlue1.moveTo(0, height * 0.15);
    for (double x = 0; x <= width; x += 5) {
      final progress = x / width;
      final yBase = height * 0.15 + progress * height * 0.5; // Diagonal baseline
      final yWave = yBase + math.sin((progress * 2.0 * math.pi) + animationValue * 2 * math.pi) * 30;
      pathBlue1.lineTo(x, yWave);
    }

    // Diagonal wave 2 (Blue) - Top to bottom
    pathBlue2.moveTo(0, height * 0.25);
    for (double x = 0; x <= width; x += 5) {
      final progress = x / width;
      final yBase = height * 0.25 + progress * height * 0.4;
      final yWave = yBase + math.cos((progress * 2.5 * math.pi) - animationValue * 1.7 * math.pi) * 25;
      pathBlue2.lineTo(x, yWave);
    }

    // Diagonal wave 3 (Blue) - Middle diagonal
    pathBlue3.moveTo(0, height * 0.40);
    for (double x = 0; x <= width; x += 5) {
      final progress = x / width;
      final yBase = height * 0.40 + progress * height * 0.3;
      final yWave = yBase + math.sin((progress * 1.8 * math.pi) + animationValue * 2.3 * math.pi) * 22;
      pathBlue3.lineTo(x, yWave);
    }

    // Diagonal wave 4 (Red) - Lower diagonal
    pathRed1.moveTo(0, height * 0.60);
    for (double x = 0; x <= width; x += 5) {
      final progress = x / width;
      final yBase = height * 0.60 + progress * height * 0.25;
      final yWave = yBase + math.sin((progress * 1.5 * math.pi) + animationValue * 2.2 * math.pi) * 28;
      pathRed1.lineTo(x, yWave);
    }

    // Diagonal wave 5 (Red) - Bottom diagonal
    pathRed2.moveTo(0, height * 0.75);
    for (double x = 0; x <= width; x += 5) {
      final progress = x / width;
      final yBase = height * 0.75 + progress * height * 0.15;
      final yWave = yBase + math.cos((progress * 1.3 * math.pi) - animationValue * 1.9 * math.pi) * 24;
      pathRed2.lineTo(x, yWave);
    }

    canvas.drawPath(pathBlue1, paintBlue1);
    canvas.drawPath(pathBlue2, paintBlue2);
    canvas.drawPath(pathBlue3, paintBlue3);
    canvas.drawPath(pathRed1, paintRed1);
    canvas.drawPath(pathRed2, paintRed2);
  }

  @override
  bool shouldRepaint(covariant MinimalWavesPainter oldDelegate) =>
      oldDelegate.animationValue != animationValue;
}