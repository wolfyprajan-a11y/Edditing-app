import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const CapCutAIApp());
}

class CapCutAIApp extends StatelessWidget {
  const CapCutAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Video Editor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0F12),
        primaryColor: const Color(0xFF00E5FF),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFF6C5CE7),
        ),
      ),
      home: const VideoEditorScreen(),
    );
  }
}

class VideoEditorScreen extends StatefulWidget {
  const VideoEditorScreen({super.key});

  @override
  State<VideoEditorScreen> createState() => _VideoEditorScreenState();
}

class _VideoEditorScreenState extends State<VideoEditorScreen> {
  final ImagePicker _picker = ImagePicker();
  VideoPlayerController? _controller;
  File? _videoFile;

  // Trim controls
  double _trimStart = 0.0;
  double _trimEnd = 1.0;

  // AI & Subtitle data
  String _apiKey = "";
  String _activeCaption = "";
  List<Map<String, dynamic>> _captionsList = [];
  bool _isProcessingAI = false;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    final XFile? selected = await _picker.pickVideo(source: ImageSource.gallery);
    if (selected == null) return;

    _controller?.dispose();
    final file = File(selected.path);
    final controller = VideoPlayerController.file(file);

    await controller.initialize();
    controller.addListener(_videoListener);

    setState(() {
      _videoFile = file;
      _controller = controller;
      _trimStart = 0.0;
      _trimEnd = 1.0;
      _captionsList.clear();
      _activeCaption = "";
    });
    controller.play();
  }

  void _videoListener() {
    if (_controller == null || !_controller!.value.isInitialized) return;

    final currentSeconds = _controller!.value.position.inMilliseconds / 1000.0;

    // Check for matching captions
    String matched = "";
    for (var item in _captionsList) {
      final start = item['start'] as double;
      final end = item['end'] as double;
      if (currentSeconds >= start && currentSeconds <= end) {
        matched = item['text'] as String;
        break;
      }
    }

    if (matched != _activeCaption) {
      setState(() {
        _activeCaption = matched;
      });
    }

    // Auto-loop within trim limits
    final totalDuration = _controller!.value.duration.inMilliseconds / 1000.0;
    final limitEnd = totalDuration * _trimEnd;
    final limitStart = totalDuration * _trimStart;

    if (currentSeconds >= limitEnd) {
      _controller!.seekTo(Duration(milliseconds: (limitStart * 1000).toInt()));
    }
  }

  Future<void> _askGeminiAI(String promptType) async {
    if (_apiKey.trim().isEmpty) {
      _showApiKeyDialog();
      return;
    }

    setState(() => _isProcessingAI = true);

    final durationSec = _controller?.value.duration.inSeconds ?? 30;
    String promptText = "";

    if (promptType == "captions") {
      promptText =
          "Generate timestamped auto-captions for a $durationSec-second viral short video. "
          "Return ONLY a valid JSON array of objects with keys 'start' (float seconds), "
          "'end' (float seconds), and 'text' (short subtitle phrase). No markdown formatting.";
    } else {
      promptText =
          "Suggest 3 viral video hooks and highlight moments for a $durationSec-second reel. "
          "Provide punchy cut timestamps and recommendations.";
    }

    try {
      final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$_apiKey');

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [
            {
              "parts": [
                {"text": promptText}
              ]
            }
          ]
        }),
      );

      final data = jsonDecode(response.body);
      final rawText = data['candidates'][0]['content']['parts'][0]['text'] as String;

      if (promptType == "captions") {
        final cleanJson = rawText.replaceAll('```json', '').replaceAll('```', '').trim();
        final List parsed = jsonDecode(cleanJson);
        setState(() {
          _captionsList = parsed.map((e) => {
            'start': (e['start'] as num).toDouble(),
            'end': (e['end'] as num).toDouble(),
            'text': e['text'].toString(),
          }).toList();
        });
        _showSnackbar("Auto-captions generated and synced to timeline!");
      } else {
        _showResultDialog("AI Highlights & Suggestions", rawText);
      }
    } catch (e) {
      _showSnackbar("AI Request Error: $e");
    } finally {
      setState(() => _isProcessingAI = false);
    }
  }

  void _showApiKeyDialog() {
    final textController = TextEditingController(text: _apiKey);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E24),
        title: const Text("Google AI Studio API Key"),
        content: TextField(
          controller: textController,
          decoration: const InputDecoration(
            hintText: "Paste AI Studio API key here",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _apiKey = textController.text.trim());
              Navigator.pop(ctx);
              _showSnackbar("API Key saved!");
            },
            child: const Text("Save"),
          )
        ],
      ),
    );
  }

  void _showResultDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E24),
        title: Text(title),
        content: SingleChildScrollView(child: Text(content)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Done")),
        ],
      ),
    );
  }

  void _showSnackbar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF16161B),
        title: const Text("CapCut AI Studio", style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.key, color: Color(0xFF00E5FF)),
            onPressed: _showApiKeyDialog,
            tooltip: "Set Gemini API Key",
          ),
          IconButton(
            icon: const Icon(Icons.add_photo_alternate, color: Colors.white),
            onPressed: _pickVideo,
            tooltip: "Pick Video",
          ),
        ],
      ),
      body: _videoFile == null
          ? Center(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E5FF),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                ),
                onPressed: _pickVideo,
                icon: const Icon(Icons.file_upload),
                label: const Text("Select Video from Storage", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            )
          : Column(
              children: [
                // Video Preview Area
                Expanded(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AspectRatio(
                        aspectRatio: _controller!.value.aspectRatio,
                        child: VideoPlayer(_controller!),
                      ),
                      // Subtitle Overlay
                      if (_activeCaption.isNotEmpty)
                        Positioned(
                          bottom: 24,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.75),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF00E5FF), width: 1),
                            ),
                            child: Text(
                              _activeCaption,
                              style: const TextStyle(color: Colors.yellowAccent, fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      // Play/Pause Overlay Button
                      IconButton(
                        iconSize: 56,
                        color: Colors.white.withOpacity(0.8),
                        icon: Icon(_controller!.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
                        onPressed: () {
                          setState(() {
                            _controller!.value.isPlaying ? _controller!.pause() : _controller!.play();
                          });
                        },
                      ),
                    ],
                  ),
                ),

                // Trim & Timeline Scrubber
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: const Color(0xFF16161B),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("Trim In: ${(_trimStart * 100).toInt()}%", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          const Text("Drag handles to cut clip", style: TextStyle(fontSize: 12, color: Color(0xFF00E5FF))),
                          Text("Trim Out: ${(_trimEnd * 100).toInt()}%", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                      RangeSlider(
                        values: RangeValues(_trimStart, _trimEnd),
                        activeColor: const Color(0xFF00E5FF),
                        inactiveColor: Colors.white24,
                        onChanged: (RangeValues vals) {
                          setState(() {
                            _trimStart = vals.start;
                            _trimEnd = vals.end;
                          });
                        },
                      ),
                    ],
                  ),
                ),

                // AI Tools Bottom Dock
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E1E24),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  child: _isProcessingAI
                      ? const Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator()))
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildActionButton(Icons.subtitles, "AI Captions", () => _askGeminiAI("captions")),
                            _buildActionButton(Icons.auto_awesome, "AI Highlights", () => _askGeminiAI("highlights")),
                            _buildActionButton(Icons.content_cut, "Apply Trim", () {
                              final total = _controller!.value.duration.inMilliseconds;
                              _controller!.seekTo(Duration(milliseconds: (total * _trimStart).toInt()));
                              _showSnackbar("Video trimmed to selection!");
                            }),
                          ],
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFF2A2A35),
            child: Icon(icon, color: const Color(0xFF00E5FF), size: 20),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.white)),
        ],
      ),
    );
  }
}
