import 'dart:io';
import 'package:audiate/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:async';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:quick_usb/quick_usb.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {

  WidgetsFlutterBinding.ensureInitialized();
  // Pre-load preferences
  await SharedPreferences.getInstance();
  _macOSPluginInitDelay().then((_) {
    runApp(const MyApp());
  });
}
Future<void> _macOSPluginInitDelay() async {
  if (Platform.isMacOS) {
    print("Adding delay for macOS plugin initialization");
    
    // Give the platform channels time to initialize before using them
    await Future.delayed(Duration(milliseconds: 2000));
    
    // Attempt to initialize QuickUsb very early, but ignore errors
    // This "primes" the platform channel
    try {
      print("Early plugin initialization attempt");
      await QuickUsb.init();
    } catch (e) {
      print("Expected early initialization error (this is normal): $e");
      // This error is expected - we're just forcing platform channel setup
    }
    
    // Additional delay to let Flutter settle after initialization attempt
    await Future.delayed(Duration(milliseconds: 1000));
  }
}
class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: const Color(0xFF1A1A1A),
      ),
    );
    
    return MaterialApp(
      title: 'AssistiveType Pro',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1A1A1A),
        fontFamily: 'SF Pro Display',
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF007AFF),
          secondary: Color(0xFF5AC8FA),
          surface: Color(0xFF2C2C2E),
          background: Color(0xFF1A1A1A),
          error: Color(0xFFFF3B30),
          tertiary: Color(0xFFAF52DE), // Purple for AI features
        ),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(fontWeight: FontWeight.w600),
          titleLarge: TextStyle(fontWeight: FontWeight.w600),
          titleMedium: TextStyle(letterSpacing: 0.15),
          bodyLarge: TextStyle(letterSpacing: 0.15),
          labelLarge: TextStyle(letterSpacing: 0.1, fontWeight: FontWeight.w500),
        ),
        useMaterial3: true,
      ),
      debugShowCheckedModeBanner: false,
      home:  AccessibilityKeyboardScreen(),
    );
  }
}

class AccessibilityKeyboardScreen extends StatefulWidget {
  const AccessibilityKeyboardScreen({Key? key}) : super(key: key);

  @override
  State<AccessibilityKeyboardScreen> createState() => _AccessibilityKeyboardScreenState();
}

class _AccessibilityKeyboardScreenState extends State<AccessibilityKeyboardScreen> with TickerProviderStateMixin {
  bool _isConnected = false;
  StreamSubscription<Uint8List>? _subscription;
  final TextEditingController _textController = TextEditingController();
  final FlutterTts _flutterTts = FlutterTts();
  final ScrollController _scrollController = ScrollController();
   var availablePorts = [];
    SerialPort? port;
  SerialPortReader? reader;
  String receivedData = '';
  String _flaskApiBaseUrl = 'http://10.40.9.218:8000/';
  String _flaskApiBaseUrl2 = 'http://10.40.9.218:8001/'; // Second API URL
  bool _useFirstApi = true;
  
  void connectToArduino() {
    final availablePorts = SerialPort.availablePorts;
    print(availablePorts.toString());
    for (final portName in availablePorts) {
      if (portName.contains("/dev/cu.usbserial-110")) {  // Typical Arduino port name
        port = SerialPort(portName);
        if (port!.openReadWrite()) {
          print("Connected to $portName");
          reader = SerialPortReader(port!);
          reader!.stream.listen((data) {
            print(String.fromCharCodes(data));
            if(int.parse(String.fromCharCodes(data))==0){
              _handleSelectButtonPress();
            }
            setState(() {
              receivedData += String.fromCharCodes(data);
            });
          });
          break;
        }
      }
    }
  }
  // For logging and analytics
  final List<String> _typingHistory = [];
  
  // User preferences
  late SharedPreferences _prefs;
  bool _darkTheme = true;
  double _scanSpeed = 1.0;
  bool _highContrastMode = false;
  String _activeLanguage = 'en-US';
  
  // Network connectivity

  // For Gemini AI
  late GenerativeModel _generativeModel;
  String _currentPrediction = "";
  List<String> _alternativePredictions = [];
  int _currentPredictionIndex = 0;
  bool _isLoading = false;
  String _geminiApiKey = "AIzaSyAEY0DdEKpeqHOz8XT4YFsZVbKDUyTtTcM"; // Replace in production
  int _predictionConfidence = 0;
  
  // Selection timers
  Timer? _selectionTimer;
  
  // Redesigned keyboard layout with at least 2 buttons per row
  final List<List<String>> _keyboard = [
    ['A', 'B', 'C', 'D', 'E'],
    ['F', 'G', 'H', 'I', 'J'],
    ['K', 'L', 'M', 'N', 'O'],
    ['P', 'Q', 'R', 'S', 'T'],
    ['U', 'V', 'W', 'X', 'Y'],
    ['Z', 'SPACE', 'DEL', 'SPEAK'],
    ['YES', 'NO', 'MAYBE'],
    ['START AGAIN', 'SWITCH MODE'],
    //['TEMPLATES', "THAT'S NOT RIGHT"],
  ];
  
  // Category-organized templates
  final Map<String, List<String>> _templates = {
    'Greetings': [
      'Hello, how are you?',
      'Good morning!',
      'Nice to meet you',
      'Hope you are doing well'
    ],
    'Requests': [
      'Could you help me please?',
      'I need assistance with this',
      'Can you pass me that?',
      'Would you mind if I ask a question?'
    ],
    'Needs': [
      'I need a break',
      'I am hungry',
      'I am thirsty',
      'I need to rest now'
    ],
    'Responses': [
      'Yes, that sounds good',
      'No, thank you',
      'I agree with you',
      'Let me think about it'
    ],
    'Feelings': [
      'I feel happy today',
      'I am not feeling well',
      'I am excited about this',
      'I would like some quiet time'
    ],
    'Medical': [
      'I need my medication',
      'I am in pain',
      'Please call the doctor',
      'I feel dizzy'
    ],
    'Emergency': [
      'I need help immediately',
      'Call emergency services',
      'Something is wrong',
      'I don\'t feel safe'
    ],
  };
  
  // Operating modes
  // 0: Row selection
  // 1: Character selection
  // 2: Template category selection
  // 3: Template selection
  // 4: Settings mode
  int _currentMode = 0;
  
  // Selection indices
  int _selectedRowIndex = 0;
  int _selectedCharIndex = 0;
  int _selectedCategoryIndex = 0;
  int _selectedTemplateIndex = 0;
  int _selectedSettingIndex = 0;
  
  // Time in milliseconds for selection cycling
  int _rowSelectionTime = 2000;
  int _charSelectionTime = 2000;
  int _categorySelectionTime = 1500;
  int _templateSelectionTime = 1500;
  int _settingSelectionTime = 1500;
  
  // Settings options
  final List<String> _settingsOptions = [
    'Scan Speed',
    'Theme',
    'Text Size',
    'Language',
    'Back to Keyboard'
  ];
  
  // Recent predictions for reuse
  final List<String> _recentPredictions = [];
  
  // Sentiment analysis of message (basic implementation)
  String _messageSentiment = 'neutral';
  
  // Animations
  late AnimationController _pulseAnimController;
  late Animation<double> _pulseAnimation;
  late AnimationController _scaleAnimController;
  late Animation<double> _scaleAnimation;
  late AnimationController _slideAnimController;
  late Animation<Offset> _slideAnimation;
  
  // Add new variables for word list
  List<String> _wordList = [];
  bool _isWordListLoaded = false;
  String _wordListUrl = "https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/en/en_50k.txt";
  
  @override
  void initState() {
    super.initState();
    // Initialize preferences
    _initPreferences();
    
    // Initialize TTS
    _initTts();
    
    // Initialize Gemini
    _initGemini();
    
    // Initialize connectivity monitoring
    _initConnectivity();
    
    // Initialize animations
    _initAnimations();
    
    // Load word list
    _loadWordList();
    
    // Start row selection by default
    _startRowSelection();
    connectToArduino();
  }

  // Add new method to load word list
  Future<void> _loadWordList() async {
    try {
      final response = await http.get(Uri.parse(_wordListUrl));
      if (response.statusCode == 200) {
        // Parse the response and extract words
        List<String> lines = response.body.split('\n');
        _wordList = lines.map((line) {
          // Split by space and take the first part (the word)
          List<String> parts = line.trim().split(' ');
          return parts.isNotEmpty ? parts[0].toLowerCase() : '';
        }).where((word) => word.isNotEmpty).toList();
        
        setState(() {
          _isWordListLoaded = true;
        });
      } else {
        print('Failed to load word list: ${response.statusCode}');
        _loadFallbackWordList();
      }
    } catch (e) {
      print('Error loading word list: $e');
      _loadFallbackWordList();
    }
  }

  // Add fallback word list method
  void _loadFallbackWordList() {
    // Use a basic set of common words as fallback
    _wordList = [
      'the', 'be', 'to', 'of', 'and', 'a', 'in', 'that', 'have', 'i',
      'it', 'for', 'not', 'on', 'with', 'he', 'as', 'you', 'do', 'at',
      'this', 'but', 'his', 'by', 'from', 'they', 'we', 'say', 'her', 'she',
      'or', 'an', 'will', 'my', 'one', 'all', 'would', 'there', 'their', 'what',
      'so', 'up', 'out', 'if', 'about', 'who', 'get', 'which', 'go', 'me',
      'when', 'make', 'can', 'like', 'time', 'no', 'just', 'him', 'know', 'take',
      'people', 'into', 'year', 'your', 'good', 'some', 'could', 'them', 'see', 'other',
      'than', 'then', 'now', 'look', 'only', 'come', 'its', 'over', 'think', 'also',
      'back', 'after', 'use', 'two', 'how', 'our', 'work', 'first', 'well', 'way',
      'even', 'new', 'want', 'because', 'any', 'these', 'give', 'day', 'most', 'us'
    ];
    setState(() {
      _isWordListLoaded = true;
    });
  }

  @override
  void dispose() {
    _selectionTimer?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    _pulseAnimController.dispose();
    _scaleAnimController.dispose();
    _slideAnimController.dispose();
    _flutterTts.stop();
    super.dispose();
  }
  
  // Initialize user preferences
  Future<void> _initPreferences() async {
    _prefs = await SharedPreferences.getInstance();
    setState(() {
      _darkTheme = _prefs.getBool('darkTheme') ?? true;
      _scanSpeed = _prefs.getDouble('scanSpeed') ?? 1.0;
      _highContrastMode = _prefs.getBool('highContrast') ?? false;
      _activeLanguage = _prefs.getString('language') ?? 'en-US';
      
      // Adjust timing based on scan speed preference
      _rowSelectionTime = (2000 / _scanSpeed).round();
      _charSelectionTime = (1000 / _scanSpeed).round();
      _categorySelectionTime = (1500 / _scanSpeed).round();
      _templateSelectionTime = (1500 / _scanSpeed).round();
    });
  }
  
  // Initialize connectivity monitoring
  void _initConnectivity() {
    // In a real app, you would use the connectivity_plus package
    // For now, we'll simulate always being connected
    setState(() {
      _isConnected = true;
    });
  }
  
  // Show snackbar message
  void _showSnackBar(String message) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
  
  // Initialize animations
  void _initAnimations() {
    _pulseAnimController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseAnimController, curve: Curves.easeInOut)
    );
    
    _scaleAnimController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _scaleAnimController, curve: Curves.easeInOut)
    );
    
    _slideAnimController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _slideAnimation = Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero).animate(
      CurvedAnimation(parent: _slideAnimController, curve: Curves.easeOut)
    );
  }

  // Initialize text-to-speech
  Future<void> _initTts() async {
    await _flutterTts.setLanguage(_activeLanguage);
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
    
    // Get available voices
    var voices = await _flutterTts.getVoices;
    if (voices != null && voices is List && voices.isNotEmpty) {
      // Try to find a high-quality voice
      for (var voice in voices) {
        if (voice is Map && voice.containsKey('name') && 
            voice['name'].toString().toLowerCase().contains('enhanced')) {
          //await _flutterTts.setVoice(voice['name'].toString());
          break;
        }
      }
    }
  }
  
  // Initialize Gemini AI
  void _initGemini() {
    _generativeModel = GenerativeModel(
      model: 'gemini-2.0-flash',
      apiKey: _geminiApiKey,
    );
    
    // Generate initial prediction
    _generatePredictions();
  }

  // Start row selection mode
  void _startRowSelection() {
    _selectionTimer?.cancel();
    
    setState(() {
      _currentMode = 0;
      _selectedRowIndex = 0;
    });
    
    _selectionTimer = Timer.periodic(Duration(milliseconds: _rowSelectionTime), (timer) {
      setState(() {
        _selectedRowIndex = (_selectedRowIndex + 1) % _keyboard.length;
      });
    });
  }
  
  // Start character selection mode for the selected row
  void _startCharSelection() {
    _selectionTimer?.cancel();
    
    setState(() {
      _currentMode = 1;
      _selectedCharIndex = 0;
    });
    
    _selectionTimer = Timer.periodic(Duration(milliseconds: _charSelectionTime), (timer) {
      setState(() {
        _selectedCharIndex = (_selectedCharIndex + 1) % _keyboard[_selectedRowIndex].length;
      });
    });
  }
  
  // Start template category selection
  void _startCategorySelection() {
    _selectionTimer?.cancel();
    
    setState(() {
      _currentMode = 2;
      _selectedCategoryIndex = 0;
    });
    
    _selectionTimer = Timer.periodic(Duration(milliseconds: _categorySelectionTime), (timer) {
      setState(() {
        _selectedCategoryIndex = (_selectedCategoryIndex + 1) % _templates.keys.length;
      });
    });
  }
  
  // Start template selection for the selected category
  void _startTemplateSelection() {
    _selectionTimer?.cancel();
    
    String currentCategory = _templates.keys.elementAt(_selectedCategoryIndex);
    
    setState(() {
      _currentMode = 3;
      _selectedTemplateIndex = 0;
    });
    
    _selectionTimer = Timer.periodic(Duration(milliseconds: _templateSelectionTime), (timer) {
      setState(() {
        _selectedTemplateIndex = (_selectedTemplateIndex + 1) % _templates[currentCategory]!.length;
      });
    });
  }
  
  // Start settings selection
  void _startSettingsSelection() {
    _selectionTimer?.cancel();
    
    setState(() {
      _currentMode = 4;
      _selectedSettingIndex = 0;
    });
    
    _selectionTimer = Timer.periodic(Duration(milliseconds: _settingSelectionTime), (timer) {
      setState(() {
        _selectedSettingIndex = (_selectedSettingIndex + 1) % _settingsOptions.length;
      });
    });
  }

  // Handle the select button press based on current mode
  void _handleSelectButtonPress() {
    // Use standard haptic feedback instead of Vibration package
    HapticFeedback.mediumImpact();
    
    _scaleAnimController.forward().then((_) => _scaleAnimController.reverse());
    
    switch (_currentMode) {
      case 0: // Row selection mode
        _startCharSelection();
        break;
        
      case 1: // Character selection mode
        _processSelectedCharacter();
        _startRowSelection();
        break;
        
      case 2: // Template category selection mode
        _startTemplateSelection();
        break;
        
      case 3: // Template selection mode
        _applySelectedTemplate();
        _startRowSelection();
        break;
        
      case 4: // Settings selection mode
        _processSelectedSetting();
        break;
    }
  }
  
  // Process the selected setting
  void _processSelectedSetting() {
    String selectedSetting = _settingsOptions[_selectedSettingIndex];
    
    switch (selectedSetting) {
      case 'Scan Speed':
        // Toggle between slow, medium, fast
        double newSpeed;
        if (_scanSpeed == 0.7) newSpeed = 1.0;
        else if (_scanSpeed == 1.0) newSpeed = 1.3;
        else newSpeed = 0.7;
        
        setState(() {
          _scanSpeed = newSpeed;
          _rowSelectionTime = (2000 / _scanSpeed).round();
          _charSelectionTime = (1000 / _scanSpeed).round();
          _categorySelectionTime = (1500 / _scanSpeed).round();
          _templateSelectionTime = (1500 / _scanSpeed).round();
        });
        
        _prefs.setDouble('scanSpeed', _scanSpeed);
        _showSnackBar('Scan speed set to ${_scanSpeed == 0.7 ? "Slow" : _scanSpeed == 1.0 ? "Medium" : "Fast"}');
        break;
        
      case 'Theme':
        // Toggle dark/light theme
        setState(() {
          _darkTheme = !_darkTheme;
        });
        _prefs.setBool('darkTheme', _darkTheme);
        _showSnackBar('Theme set to ${_darkTheme ? "Dark" : "Light"}');
        break;
        
      case 'Text Size':
        // Would adjust text size throughout the app
        _showSnackBar('Text size adjustment will be available in the next update');
        break;
        
      case 'Language':
        // Cycle through available languages
        List<String> languages = ['en-US', 'es-ES', 'fr-FR', 'de-DE'];
        int currentIndex = languages.indexOf(_activeLanguage);
        String newLanguage = languages[(currentIndex + 1) % languages.length];
        
        setState(() {
          _activeLanguage = newLanguage;
        });
        
        _prefs.setString('language', _activeLanguage);
        _initTts(); // Reinitialize TTS with new language
        _showSnackBar('Language set to $_activeLanguage');
        break;
        
      case 'Back to Keyboard':
        _startRowSelection();
        break;
    }
  }
  
  // Process the selected character
  void _processSelectedCharacter() {
    if (_selectedRowIndex >= 0 && _selectedRowIndex < _keyboard.length &&
        _selectedCharIndex >= 0 && _selectedCharIndex < _keyboard[_selectedRowIndex].length) {
      
      String selection = _keyboard[_selectedRowIndex][_selectedCharIndex];
      
      switch (selection) {
        case 'YES':
          // Accept current prediction
          if (_currentPrediction.isNotEmpty) {
            _acceptPrediction();
          }
          break;
          
        case 'NO':
          // Show next prediction alternative
          _showNextPrediction();
          break;
          
        case 'MAYBE':
          // Modify current prediction
          if (_currentPrediction.isNotEmpty) {
            List<String> words = _currentPrediction.split(' ');
            if (words.length > 1) {
              // Keep the first word only
              _currentPrediction = words[0];
              _alternativePredictions[_currentPredictionIndex] = _currentPrediction;
              setState(() {});
            }
          }
          break;
          
        case 'START AGAIN':
          _textController.clear();
          _currentPrediction = "";
          _alternativePredictions = [];
          _typingHistory.clear();
          break;
          
        case 'SWITCH MODE':
          setState(() {
            _useFirstApi = !_useFirstApi;
          });
          _showSnackBar('Switched to ${_useFirstApi ? "First" : "Second"} API');
          break;
          
        case 'SPACE':
          _addTextInput(' ');
          break;
          
        case 'DEL':
          // Delete last character
          String text = _textController.text;
          if (text.isNotEmpty) {
            _textController.text = text.substring(0, text.length - 1);
          }
          break;
          
        case 'SPEAK':
          _speakText();
          break;
          
        case "THAT'S NOT RIGHT":
          // Delete the last word
          String text = _textController.text;
          int lastSpaceIndex = text.lastIndexOf(' ');
          if (lastSpaceIndex != -1) {
            _textController.text = text.substring(0, lastSpaceIndex);
          } else {
            _textController.clear();
          }
          _currentPrediction = "";
          _alternativePredictions = [];
          break;
          
        default:
          // Add the letter
          _addTextInput(selection.toLowerCase());
          break;
      }
      
      // Generate prediction after input changes
      _generatePredictions();
    }
  }
  
  // Show next prediction alternative
  void _showNextPrediction() {
    if (_alternativePredictions.isNotEmpty) {
      setState(() {
        _currentPredictionIndex = (_currentPredictionIndex + 1) % _alternativePredictions.length;
        _currentPrediction = _alternativePredictions[_currentPredictionIndex];
      });
    } else {
      // Generate new predictions if there are none
      _generatePredictions();
    }
  }
  
  // Apply the selected template
  void _applySelectedTemplate() {
    String currentCategory = _templates.keys.elementAt(_selectedCategoryIndex);
    if (_selectedTemplateIndex >= 0 && _selectedTemplateIndex < _templates[currentCategory]!.length) {
      _textController.text = _templates[currentCategory]![_selectedTemplateIndex];
      _textController.selection = TextSelection.fromPosition(
        TextPosition(offset: _textController.text.length),
      );
      _currentPrediction = "";
      _alternativePredictions = [];
      
      // Generate new prediction
      _generatePredictions();
      
      // Log usage of templates
      _typingHistory.add("Used template: ${_templates[currentCategory]![_selectedTemplateIndex]}");
    }
  }

  // Add text input to the text field
  void _addTextInput(String text) {
    _textController.text += text;
    _textController.selection = TextSelection.fromPosition(
      TextPosition(offset: _textController.text.length),
    );
    
    // Log typing for analytics
    if (text != ' ' && text.length == 1) {
      _typingHistory.add("Typed: $text");
    }
  }

  // Speak the current text
  Future<void> _speakText() async {
    if (_textController.text.isNotEmpty) {
      await _flutterTts.speak(_textController.text);
      
      // Log for analytics
      _typingHistory.add("Spoke text: \"${_textController.text}\"");
    } else {
      // Speak the current prediction if available
      if (_currentPrediction.isNotEmpty) {
        await _flutterTts.speak(_currentPrediction);
      }
    }
  }
  
  // Accept the current prediction
  void _acceptPrediction() {
    if (_currentPrediction.isNotEmpty) {
      _textController.text += _currentPrediction;
      _textController.selection = TextSelection.fromPosition(
        TextPosition(offset: _textController.text.length),
      );
      
      // Add to recent predictions for reuse
      if (!_recentPredictions.contains(_currentPrediction)) {
        _recentPredictions.insert(0, _currentPrediction);
        if (_recentPredictions.length > 5) {
          _recentPredictions.removeLast();
        }
      }
      
      // Log for analytics
      _typingHistory.add("Accepted prediction: \"$_currentPrediction\"");
      
      _currentPrediction = "";
      _alternativePredictions = [];
      
      // Generate new prediction
      _generatePredictions();
    }
  }

  // Generate prediction using Gemini
  Future<void> _generatePredictions() async {
    // Don't generate predictions if there's no text
    if (_textController.text.isEmpty) {
      setState(() {
        _currentPrediction = "";
        _alternativePredictions = [];
        _currentPredictionIndex = 0;
        _predictionConfidence = 0;
      });
      return;
    }
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      if (_isConnected) {
        // Check if last character is a space
        bool isLastCharSpace = _textController.text.endsWith(' ');
        
        if (isLastCharSpace) {
          // Call sentence completion API
          final Map<String, dynamic> requestBody = {
            'sentence': _textController.text,
            'temperature': 0.7,
            'max_tokens': 30
          };
          
          List<String> suggestions = [];
          
          // First request
          try {
            final response = await http.post(
              Uri.parse('${_useFirstApi ? _flaskApiBaseUrl : _flaskApiBaseUrl2}api/predict_sentence'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(requestBody),
            );
            
            if (response.statusCode == 200) {
              Map<String, dynamic> data = jsonDecode(response.body);
              String completion = data['completion'] ?? "";
              
              if (completion.isNotEmpty) {
                suggestions.add(completion);
              }
            }
          } catch (e) {
            print('Error calling Flask API: $e');
          }
          
          // Make 3 more requests with different temperatures
          for (double temp in [0.8, 0.9, 1.0]) {
            try {
              requestBody['temperature'] = temp;
              
              final response = await http.post(
                Uri.parse('${_useFirstApi ? _flaskApiBaseUrl : _flaskApiBaseUrl2}api/predict_sentence'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode(requestBody),
              );
              
              if (response.statusCode == 200) {
                Map<String, dynamic> data = jsonDecode(response.body);
                String completion = data['completion'] ?? "";
                
                if (completion.isNotEmpty && !suggestions.contains(completion)) {
                  suggestions.add(completion);
                  if (suggestions.length >= 4) break;
                }
              }
            } catch (e) {
              print('Error calling Flask API with temperature $temp: $e');
            }
          }
          
          setState(() {
            _alternativePredictions = suggestions;
            _currentPredictionIndex = 0;
            _currentPrediction = _alternativePredictions.isNotEmpty 
                ? _alternativePredictions[0] 
                : "";
            _isLoading = false;
            _predictionConfidence = 90;
          });
        } else {
          // Word completion logic
          String lastWord = _textController.text.split(' ').last.toLowerCase();
          
          List<String> suggestions = [];
          
          if (_isWordListLoaded) {
            // Find words that start with the last word
            List<String> fullWords = _wordList
                .where((word) => word.startsWith(lastWord))
                .take(5) // Take top 5 matches
                .toList();
            
            // Convert full words to just the remaining characters
            suggestions = fullWords.map((word) => 
              word.substring(lastWord.length)).toList();
          }
          
          // If no matches found or word list not loaded, use fallback words
          if (suggestions.isEmpty) {
            suggestions = ['e', 'at', 'is', 'ave', 'ith']; // Remaining parts of fallback words
          }
          
          // Add some recent predictions if we don't have enough
          if (suggestions.length < 4 && _recentPredictions.isNotEmpty) {
            for (String recent in _recentPredictions) {
              if (suggestions.length < 4 && 
                  recent.toLowerCase().startsWith(lastWord) && 
                  !suggestions.contains(recent.substring(lastWord.length))) {
                suggestions.add(recent.substring(lastWord.length));
              }
            }
          }
          
          setState(() {
            _alternativePredictions = suggestions;
            _currentPredictionIndex = 0;
            _currentPrediction = _alternativePredictions.isNotEmpty 
                ? _alternativePredictions[0] 
                : "";
            _isLoading = false;
            _predictionConfidence = 85;
          });
        }
      } else {
        // Fallback to sample predictions when offline
        _generateSamplePredictions(
          _textController.text.isNotEmpty && !_textController.text.endsWith(' ')
        );
      }
      
      // Basic sentiment analysis
      _analyzeSentiment();
      
    } catch (e) {
      print('Error generating prediction: $e');
      // Fallback to sample predictions in case of error
      _generateSamplePredictions(
        _textController.text.isNotEmpty && !_textController.text.endsWith(' ')
      );
    }
  }
  
  // Generate fallback sample predictions
  void _generateSamplePredictions(bool needsSpace) {
    // Sample multi-word predictions for demonstration
    final List<String> samplePredictions = [
      "welcome to the",
      "is a great day",
      "would like to have",
      "thank you for your",
      "please help me with",
      "I need to go",
      "let me know when",
      "will be there soon",
      "was thinking about the",
      "should consider this option",
      "and I want to",
      "but I cannot understand",
      "is not working properly"
    ];
    
    // Select 3-4 predictions for alternatives
    List<String> predictions = [];
    for (int i = 0; i < 4; i++) {
      int randomIndex = DateTime.now().millisecond % samplePredictions.length;
      String prediction = samplePredictions[randomIndex];
      
      // Add space at the beginning if needed
      if (needsSpace) {
        prediction = ' ' + prediction;
      }
      
      if (!predictions.contains(prediction)) {
        predictions.add(prediction);
      }
      
      // Ensure we have exactly 4 different predictions
      if (predictions.length >= 4) break;
    }
    
    // Add some recent predictions to maintain context
    if (_recentPredictions.isNotEmpty) {
      for (String recent in _recentPredictions) {
        if (predictions.length < 4) {
          // Add space if needed
          String formatted = recent;
          if (needsSpace && !formatted.startsWith(' ')) {
            formatted = ' ' + formatted;
          }
          
          if (!predictions.contains(formatted)) {
            predictions.add(formatted);
          }
        } else {
          break;
        }
      }
    }
    
    setState(() {
      _alternativePredictions = predictions;
      _currentPredictionIndex = 0;
      _currentPrediction = _alternativePredictions.isNotEmpty 
          ? _alternativePredictions[0] 
          : "";
      _isLoading = false;
      _predictionConfidence = 85; // Simulated confidence score
    });
  }
  
  // Simple sentiment analysis
  void _analyzeSentiment() {
    String text = _textController.text.toLowerCase();
    
    // Simple keyword-based sentiment analysis
    List<String> positiveWords = ['happy', 'good', 'great', 'excellent', 'love', 'like', 'thank'];
    List<String> negativeWords = ['sad', 'bad', 'terrible', 'hate', 'dislike', 'angry', 'pain'];
    
    int positiveScore = 0;
    int negativeScore = 0;
    
    for (String word in text.split(' ')) {
      if (positiveWords.contains(word)) positiveScore++;
      if (negativeWords.contains(word)) negativeScore++;
    }
    
    setState(() {
      if (positiveScore > negativeScore) {
        _messageSentiment = 'positive';
      } else if (negativeScore > positiveScore) {
        _messageSentiment = 'negative';
      } else {
        _messageSentiment = 'neutral';
      }
    });
  }


  
 
  


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            
            // App bar with status indicators
            _buildAppBar(),
            
            // Text area with inline prediction
            _buildTextArea(),
            
            // Mode indicator
            _buildModeIndicator(),
            
            // Main content area (keyboard and templates)
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Left: Keyboard area (2/3 width)
                  Expanded(
                    flex: 2,
                    child: _currentMode == 4 
                        ? _buildSettingsArea()
                        : _buildKeyboardArea(),
                  ),
                  
                  // Divider
                  Container(
                    width: 1,
                    color: Colors.grey.withOpacity(0.2),
                    margin: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  
                  // Right: Templates or Info area (1/3 width)
                  Expanded(
                    flex: 1,
                    child: (_currentMode == 2 || _currentMode == 3)
                        ? _buildTemplatesArea()
                        : _buildPredictionInfoArea(),
                  ),
                ],
              ),
            ),
            
            // Single select button
           // _buildSelectButton(),
          ],
        ),
      ),
    );
  }

  // Build app bar
  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          // Logo
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).colorScheme.primary,
                  Theme.of(context).colorScheme.tertiary,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(
              child: Icon(
                Icons.accessibility_new,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
          const SizedBox(width: 12),
          
          // Title and subtitle
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: (){
                   _handleSelectButtonPress();
                },
                child: const Text(
                  'AUDIATE',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.tertiary.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          size: 10,
                          color: Theme.of(context).colorScheme.tertiary,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          'AI',
                          style: TextStyle(
                            fontSize: 10,
                            color: Theme.of(context).colorScheme.tertiary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'Advanced Communication',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[400],
                    ),
                  ),
                ],
              ),
            ],
          ),
          
          const Spacer(),
          
          // AI indicator
          if (_isLoading)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.tertiary.withOpacity(0.2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(context).colorScheme.tertiary.withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Theme.of(context).colorScheme.tertiary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'AI Thinking',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.tertiary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          
          const SizedBox(width: 8),
          
          // Language indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.language,
                  size: 14,
                  color: Colors.white70,
                ),
                const SizedBox(width: 4),
                Text(
                  _activeLanguage.split('-')[0].toUpperCase(),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(width: 8),
          
          // Network status
          Icon(
            _isConnected ? Icons.wifi : Icons.wifi_off,
            size: 16,
            color: _isConnected ? Colors.green : Colors.red,
          ),
          
          const SizedBox(width: 8),
          
          // Version badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).colorScheme.primary.withOpacity(0.2),
                  Theme.of(context).colorScheme.secondary.withOpacity(0.2),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
              ),
            ),
            child: const Text(
              'v2.1 Enterprise',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Build text area with inline prediction
  Widget _buildTextArea() {
    // Combine text and prediction for display
    String displayText = _textController.text;
    String predictionText = _currentPrediction;
    
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: Colors.grey.withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Text field header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(
                  Icons.message_rounded,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Message',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const Spacer(),
                
                // Sentiment indicator
                if (displayText.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _messageSentiment == 'positive'
                          ? Colors.green.withOpacity(0.2)
                          : _messageSentiment == 'negative'
                              ? Colors.red.withOpacity(0.2)
                              : Colors.grey.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: _messageSentiment == 'positive'
                            ? Colors.green.withOpacity(0.3)
                            : _messageSentiment == 'negative'
                                ? Colors.red.withOpacity(0.3)
                                : Colors.grey.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _messageSentiment == 'positive'
                              ? Icons.sentiment_satisfied_alt
                              : _messageSentiment == 'negative'
                                  ? Icons.sentiment_dissatisfied
                                  : Icons.sentiment_neutral,
                          size: 12,
                          color: _messageSentiment == 'positive'
                              ? Colors.green
                              : _messageSentiment == 'negative'
                                  ? Colors.red
                                  : Colors.grey,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _messageSentiment.substring(0, 1).toUpperCase() + _messageSentiment.substring(1),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: _messageSentiment == 'positive'
                                ? Colors.green
                                : _messageSentiment == 'negative'
                                    ? Colors.red
                                    : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                
                const SizedBox(width: 8),
                
                // Word counter
                if (displayText.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${displayText.split(' ').where((word) => word.isNotEmpty).length} words',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          
          // Text field with inline prediction
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              height: 100,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.grey.withOpacity(0.2),
                ),
              ),
              child: SingleChildScrollView(
                child: RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: displayText,
                        style: const TextStyle(
                          fontSize: 24,
                          height: 1.3,
                          color: Colors.white,
                        ),
                      ),
                      TextSpan(
                        text: predictionText,
                        style: TextStyle(
                          fontSize: 24,
                          height: 1.3,
                          color: Colors.grey.withOpacity(0.7),
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Build mode indicator
  Widget _buildModeIndicator() {
    String modeText;
    Color modeColor;
    IconData modeIcon;
    
    switch (_currentMode) {
      case 0:
        modeText = "Row Selection";
        modeColor = Theme.of(context).colorScheme.primary;
        modeIcon = Icons.keyboard_arrow_right;
        break;
      case 1:
        modeText = "Character Selection";
        modeColor = Colors.green;
        modeIcon = Icons.text_fields;
        break;
      case 2:
        modeText = "Category Selection";
        modeColor = Colors.orange;
        modeIcon = Icons.category;
        break;
      case 3:
        modeText = "Template Selection";
        modeColor = Colors.orange.shade700;
        modeIcon = Icons.format_quote;
        break;
      case 4:
        modeText = "Settings";
        modeColor = Colors.purple;
        modeIcon = Icons.settings;
        break;
      default:
        modeText = "Scanning";
        modeColor = Colors.grey;
        modeIcon = Icons.search;
    }
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: modeColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: modeColor.withOpacity(0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: modeColor.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            modeIcon,
            size: 16,
            color: modeColor,
          ),
          const SizedBox(width: 8),
          Text(
            modeText,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: modeColor,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: modeColor,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }

  // Build keyboard area
  Widget _buildKeyboardArea() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Text(
            'Communication Board',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          
          // Keyboard grid
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
                border: Border.all(
                  color: Colors.grey.withOpacity(0.2),
                ),
              ),
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (int rowIndex = 0; rowIndex < _keyboard.length; rowIndex++)
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          for (int colIndex = 0; colIndex < _keyboard[rowIndex].length; colIndex++)
                            _buildKeyboardKey(rowIndex, colIndex),
                        ],
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

  // Build keyboard key
  Widget _buildKeyboardKey(int rowIndex, int colIndex) {
    bool isRowSelected = _currentMode == 0 && rowIndex == _selectedRowIndex;
    bool isCharSelected = _currentMode == 1 && rowIndex == _selectedRowIndex && colIndex == _selectedCharIndex;
    bool isHighlighted = isRowSelected || isCharSelected;
    
    String keyText = _keyboard[rowIndex][colIndex];
    bool isCommand = keyText.contains(' ') || 
                     ['YES', 'NO', 'MAYBE', 'SPACE', 'DEL', 'SPEAK'].contains(keyText);
    bool isPredictionControl = ['YES', 'NO', 'MAYBE'].contains(keyText);
    bool isSpecialFunction = ['SPACE', 'DEL', 'SPEAK'].contains(keyText);
    
    // Special coloring for function buttons
    Color keyColor;
    IconData? keyIcon;
    
    if (isPredictionControl) {
      keyColor = keyText == 'YES' 
          ? Colors.green 
          : keyText == 'NO' 
              ? Colors.red 
              : Colors.amber;
      keyIcon = keyText == 'YES' 
          ? Icons.check_circle_outline 
          : keyText == 'NO' 
              ? Icons.cancel_outlined 
              : Icons.help_outline;
    } else if (isSpecialFunction) {
      keyColor = Theme.of(context).colorScheme.secondary;
      switch (keyText) {
        case 'SPACE':
          keyIcon = Icons.space_bar;
          break;
        case 'DEL':
          keyIcon = Icons.backspace_outlined;
          break;
        case 'SPEAK':
          keyIcon = Icons.record_voice_over;
          break;
      }
    } else if (isCharSelected) {
      keyColor = Colors.green;
      keyIcon = null;
    } else if (isRowSelected) {
      keyColor = Theme.of(context).colorScheme.primary;
      keyIcon = null;
    } else {
      keyColor = Colors.grey;
      keyIcon = null;
    }
    
    return Expanded(
      flex: isCommand ? 2 : 1,
      child: AnimatedBuilder(
        animation: isHighlighted ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
        builder: (context, child) {
          return Transform.scale(
            scale: isHighlighted ? _pulseAnimation.value : 1.0,
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Container(
                decoration: BoxDecoration(
                  color: isPredictionControl
                    ? keyColor.withOpacity(0.2)
                    : isSpecialFunction
                      ? Theme.of(context).colorScheme.secondary.withOpacity(0.2)
                      : isCharSelected 
                        ? Colors.green.withOpacity(0.2)
                        : isRowSelected
                          ? Theme.of(context).colorScheme.primary.withOpacity(0.2)
                          : Colors.grey.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isPredictionControl
                      ? keyColor
                      : isSpecialFunction
                        ? Theme.of(context).colorScheme.secondary
                        : isCharSelected 
                          ? Colors.green
                          : isRowSelected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey.withOpacity(0.2),
                    width: 1.5,
                  ),
                  boxShadow: isHighlighted ? [
                    BoxShadow(
                      color: keyColor.withOpacity(0.3),
                      blurRadius: 8,
                      spreadRadius: 0,
                    ),
                  ] : null,
                ),
                child: Center(
                  child: keyIcon != null 
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              keyIcon,
                              size: 16,
                              color: isHighlighted ? keyColor : Colors.white70,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              keyText,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: isCommand ? 12 : 18,
                                fontWeight: isHighlighted ? FontWeight.bold : FontWeight.normal,
                                color: isHighlighted ? keyColor : Colors.white,
                              ),
                            ),
                          ],
                        )
                      : Text(
                          keyText,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: isCommand ? 12 : 18,
                            fontWeight: isHighlighted ? FontWeight.bold : FontWeight.normal,
                            color: isHighlighted ? keyColor : Colors.white,
                          ),
                        ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // Build settings area
  Widget _buildSettingsArea() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(
                Icons.settings,
                size: 20,
                color: Colors.purple,
              ),
              const SizedBox(width: 8),
              Text(
                'Settings',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Settings list
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
                border: Border.all(
                  color: Colors.grey.withOpacity(0.2),
                ),
              ),
              padding: const EdgeInsets.all(16),
              child: ListView.separated(
                itemCount: _settingsOptions.length,
                separatorBuilder: (context, index) => Divider(
                  color: Colors.grey.withOpacity(0.2),
                  height: 1,
                ),
                itemBuilder: (context, index) {
                  bool isSelected = index == _selectedSettingIndex;
                  String settingText = _settingsOptions[index];
                  
                  // Get the current setting value
                  String settingValue = '';
                  switch (settingText) {
                    case 'Scan Speed':
                      settingValue = _scanSpeed == 0.7 
                          ? 'Slow' 
                          : _scanSpeed == 1.0 
                              ? 'Medium' 
                              : 'Fast';
                      break;
                    case 'Theme':
                      settingValue = _darkTheme ? 'Dark' : 'Light';
                      break;
                    case 'Text Size':
                      settingValue = 'Normal';
                      break;
                    case 'Language':
                      settingValue = _activeLanguage.split('-')[0].toUpperCase();
                      break;
                  }
                  
                  // Get setting icon
                  IconData settingIcon;
                  switch (settingText) {
                    case 'Scan Speed':
                      settingIcon = Icons.speed;
                      break;
                    case 'Theme':
                      settingIcon = _darkTheme ? Icons.dark_mode : Icons.light_mode;
                      break;
                    case 'Text Size':
                      settingIcon = Icons.text_fields;
                      break;
                    case 'Language':
                      settingIcon = Icons.language;
                      break;
                    case 'Back to Keyboard':
                      settingIcon = Icons.keyboard_return;
                      break;
                    default:
                      settingIcon = Icons.settings;
                  }
                  
                  return AnimatedBuilder(
                    animation: isSelected ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
                    builder: (context, child) {
                      return Transform.scale(
                        scale: isSelected ? _pulseAnimation.value : 1.0,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isSelected 
                                ? Colors.purple.withOpacity(0.2)
                                : Colors.grey.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected 
                                  ? Colors.purple 
                                  : Colors.grey.withOpacity(0.2),
                              width: isSelected ? 2 : 1,
                            ),
                            boxShadow: isSelected ? [
                              BoxShadow(
                                color: Colors.purple.withOpacity(0.2),
                                blurRadius: 8,
                                spreadRadius: 0,
                              ),
                            ] : null,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                settingIcon,
                                size: 20,
                                color: isSelected ? Colors.purple : Colors.grey,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      settingText,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                        color: isSelected ? Colors.purple : Colors.white,
                                      ),
                                    ),
                                    if (settingValue.isNotEmpty)
                                      Text(
                                        settingValue,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isSelected ? Colors.purple.withOpacity(0.8) : Colors.grey,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              if (settingText != 'Back to Keyboard')
                                Icon(
                                  Icons.arrow_forward_ios,
                                  size: 14,
                                  color: isSelected ? Colors.purple : Colors.grey,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Build prediction info area
  Widget _buildPredictionInfoArea() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with AI badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.tertiary.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      size: 14,
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'AI',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.tertiary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                'Smart Predictions',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Prediction info
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
                border: Border.all(
                  color: Colors.grey.withOpacity(0.2),
                ),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Current prediction with confidence
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.tertiary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.tertiary.withOpacity(0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'AI Suggestion:',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[400],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (_predictionConfidence > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _predictionConfidence > 80
                                      ? Colors.green.withOpacity(0.2)
                                      : _predictionConfidence > 60
                                          ? Colors.amber.withOpacity(0.2)
                                          : Colors.grey.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      _predictionConfidence > 80
                                          ? Icons.check_circle_outline
                                          : _predictionConfidence > 60
                                              ? Icons.info_outline
                                              : Icons.help_outline,
                                      size: 10,
                                      color: _predictionConfidence > 80
                                          ? Colors.green
                                          : _predictionConfidence > 60
                                              ? Colors.amber
                                              : Colors.grey,
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      '$_predictionConfidence%',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w500,
                                        color: _predictionConfidence > 80
                                            ? Colors.green
                                            : _predictionConfidence > 60
                                                ? Colors.amber
                                                : Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _currentPrediction.isEmpty 
                              ? 'No prediction available'
                              : '"$_currentPrediction"',
                          style: TextStyle(
                            fontSize: 18,
                            color: _currentPrediction.isEmpty 
                                ? Colors.grey 
                                : Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        
                        if (_alternativePredictions.length > 1)
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Row(
                              children: [
                                Text(
                                  'Prediction ${_currentPredictionIndex + 1} of ${_alternativePredictions.length}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[400],
                                  ),
                                ),
                                const Spacer(),
                                Row(
                                  children: [
                                    for (int i = 0; i < _alternativePredictions.length; i++)
                                      Container(
                                        width: 8,
                                        height: 8,
                                        margin: const EdgeInsets.symmetric(horizontal: 2),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: i == _currentPredictionIndex
                                              ? Theme.of(context).colorScheme.tertiary
                                              : Colors.grey.withOpacity(0.3),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Instructions
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.green.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.check_circle_outline,
                              size: 14,
                              color: Colors.green,
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              'YES',
                              style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Accept prediction',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 12),
                  
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.red.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.cancel_outlined,
                              size: 14,
                              color: Colors.red,
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              'NO',
                              style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Show next prediction',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 12),
                  
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.amber.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.help_outline,
                              size: 14,
                              color: Colors.amber,
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              'MAYBE',
                              style: TextStyle(
                                color: Colors.amber,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Modify prediction',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  
                  const Spacer(),
                  
                  // Quick tip
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Theme.of(context).colorScheme.primary.withOpacity(0.1),
                          Theme.of(context).colorScheme.tertiary.withOpacity(0.1),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.tips_and_updates,
                          color: Theme.of(context).colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'AI analyzes context to suggest the most relevant completions. Selection choices improve future predictions.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
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

  // Build templates area
  Widget _buildTemplatesArea() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Text(
            'Quick Templates',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          
          // Category tabs (visible only in category selection mode)
          if (_currentMode == 2)
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _templates.keys.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  String category = _templates.keys.elementAt(index);
                  bool isSelected = index == _selectedCategoryIndex;
                  
                  // Category icons
                  IconData categoryIcon;
                  switch (category) {
                    case 'Greetings':
                      categoryIcon = Icons.waving_hand;
                      break;
                    case 'Requests':
                      categoryIcon = Icons.help_outline;
                      break;
                    case 'Needs':
                      categoryIcon = Icons.access_time_filled;
                      break;
                    case 'Responses':
                      categoryIcon = Icons.reply;
                      break;
                    case 'Feelings':
                      categoryIcon = Icons.mood;
                      break;
                    case 'Medical':
                      categoryIcon = Icons.medical_services;
                      break;
                    case 'Emergency':
                      categoryIcon = Icons.warning;
                      break;
                    default:
                      categoryIcon = Icons.category;
                  }
                  
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      gradient: isSelected 
                        ? LinearGradient(
                            colors: [
                              Colors.orange.withOpacity(0.7),
                              Colors.deepOrange.withOpacity(0.7),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                      color: isSelected 
                        ? null
                        : Colors.grey.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected 
                          ? Colors.orange
                          : Colors.grey.withOpacity(0.2),
                        width: 1.5,
                      ),
                      boxShadow: isSelected ? [
                        BoxShadow(
                          color: Colors.orange.withOpacity(0.3),
                          blurRadius: 8,
                          spreadRadius: -2,
                          offset: const Offset(0, 2),
                        ),
                      ] : null,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          categoryIcon,
                          size: 16,
                          color: isSelected ? Colors.white : Colors.grey,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          category,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected 
                              ? Colors.white
                              : Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          
          if (_currentMode == 2) const SizedBox(height: 16),
          
          // Templates list
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
                border: Border.all(
                  color: Colors.grey.withOpacity(0.2),
                ),
              ),
              padding: const EdgeInsets.all(16),
              child: _buildTemplatesList(),
            ),
          ),
        ],
      ),
    );
  }
  
  // Build templates list
  Widget _buildTemplatesList() {
    // Selected category
    String category = _currentMode == 2 || _currentMode == 3
        ? _templates.keys.elementAt(_selectedCategoryIndex)
        : _templates.keys.first;
    
    // Category icon
    IconData categoryIcon;
    switch (category) {
      case 'Greetings':
        categoryIcon = Icons.waving_hand;
        break;
      case 'Requests':
        categoryIcon = Icons.help_outline;
        break;
      case 'Needs':
        categoryIcon = Icons.access_time_filled;
        break;
      case 'Responses':
        categoryIcon = Icons.reply;
        break;
      case 'Feelings':
        categoryIcon = Icons.mood;
        break;
      case 'Medical':
        categoryIcon = Icons.medical_services;
        break;
      case 'Emergency':
        categoryIcon = Icons.warning;
        break;
      default:
        categoryIcon = Icons.category;
    }
    
    return ListView.separated(
      itemCount: _templates[category]!.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        bool isSelected = _currentMode == 3 && index == _selectedTemplateIndex;
        String template = _templates[category]![index];
        
        return AnimatedBuilder(
          animation: isSelected ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
          builder: (context, child) {
            return Transform.scale(
              scale: isSelected ? _pulseAnimation.value : 1.0,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: isSelected 
                    ? LinearGradient(
                        colors: [
                          Colors.orange.withOpacity(0.3),
                          Colors.deepOrange.withOpacity(0.3),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                  color: isSelected 
                    ? null
                    : Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected 
                      ? Colors.orange
                      : Theme.of(context).colorScheme.secondary.withOpacity(0.3),
                    width: isSelected ? 2 : 1,
                  ),
                  boxShadow: isSelected ? [
                    BoxShadow(
                      color: Colors.orange.withOpacity(0.3),
                      blurRadius: 8,
                      spreadRadius: 0,
                    ),
                  ] : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_currentMode == 2)  // Show category name in category selection mode
                      Row(
                        children: [
                          Icon(
                            categoryIcon,
                            size: 12,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            category,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[400],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    if (_currentMode == 2)
                      const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            template,
                            style: TextStyle(
                              fontSize: 16,
                              color: isSelected ? Colors.orange : Colors.white,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                        if (isSelected)
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.check,
                                size: 16,
                                color: Colors.orange,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
  
  // Build select button
  Widget _buildSelectButton() {
    Color buttonColor;
    IconData buttonIcon;
    String buttonText = 'SELECT';
    
    switch (_currentMode) {
      case 0:
        buttonColor = Theme.of(context).colorScheme.primary;
        buttonIcon = Icons.keyboard_arrow_right;
        break;
      case 1:
        // Special case for YES/NO buttons
        if (_selectedRowIndex == 6 && _selectedCharIndex < 3) {
          if (_keyboard[_selectedRowIndex][_selectedCharIndex] == 'YES') {
            buttonColor = Colors.green;
            buttonIcon = Icons.check_circle;
          } else if (_keyboard[_selectedRowIndex][_selectedCharIndex] == 'NO') {
            buttonColor = Colors.red;
            buttonIcon = Icons.cancel;
          } else {
            buttonColor = Colors.amber;
            buttonIcon = Icons.help;
          }
        } else if (_keyboard[_selectedRowIndex][_selectedCharIndex] == 'SPEAK') {
          buttonColor = Colors.teal;
          buttonIcon = Icons.record_voice_over;
          buttonText = 'SPEAK';
        } else {
          buttonColor = Colors.green;
          buttonIcon = Icons.text_fields;
        }
        break;
      case 2:
        buttonColor = Colors.orange;
        buttonIcon = Icons.category;
        break;
      case 3:
        buttonColor = Colors.orange.shade700;
        buttonIcon = Icons.format_quote;
        buttonText = 'USE TEMPLATE';
        break;
      case 4:
        buttonColor = Colors.purple;
        buttonIcon = Icons.settings;
        buttonText = 'APPLY SETTING';
        break;
      default:
        buttonColor = Theme.of(context).colorScheme.primary;
        buttonIcon = Icons.keyboard_arrow_right;
    }
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: SizedBox(
              width: double.infinity,
              height: 70,
              child: ElevatedButton(
                onPressed: _handleSelectButtonPress,
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: buttonColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 8,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shadowColor: buttonColor.withOpacity(0.5),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      buttonIcon,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      buttonText,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}