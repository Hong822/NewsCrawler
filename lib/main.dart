import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/intl.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:devicelocale/devicelocale.dart';
import 'package:upgrader/upgrader.dart';
import 'firebase_options.dart';
import 'news_collector_service.dart';
import 'ad_helper.dart';

// --- Custom Date Formatter ---
class DateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (text.length > 8) return oldValue;

    var formatted = '';
    for (var i = 0; i < text.length; i++) {
      formatted += text[i];
      if ((i == 1 || i == 3) && i != text.length - 1) {
        formatted += '/';
      }
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

// --- Custom Localizations for 3-letter weekdays and coloring ---
class CustomMaterialLocalizations extends DefaultMaterialLocalizations {
  const CustomMaterialLocalizations();

  @override
  List<String> get narrowWeekdays => ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
}

class CustomMaterialLocalizationsDelegate extends LocalizationsDelegate<MaterialLocalizations> {
  const CustomMaterialLocalizationsDelegate();
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<MaterialLocalizations> load(Locale locale) async => const CustomMaterialLocalizations();
  @override
  bool shouldReload(CustomMaterialLocalizationsDelegate old) => false;
}

// --- Custom Simple Calendar for Weekend Colors ---
class CollectorCalendar extends StatefulWidget {
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final ValueChanged<DateTime> onDateChanged;

  const CollectorCalendar({
    super.key,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.onDateChanged,
  });

  @override
  State<CollectorCalendar> createState() => _CollectorCalendarState();
}

class _CollectorCalendarState extends State<CollectorCalendar> {
  late DateTime _currentMonth;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _currentMonth = DateTime(widget.initialDate.year, widget.initialDate.month);
    _selectedDate = widget.initialDate;
  }

  @override
  void didUpdateWidget(CollectorCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialDate != widget.initialDate) {
      _selectedDate = widget.initialDate;
      _currentMonth = DateTime(_selectedDate.year, _selectedDate.month);
    }
  }

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateUtils.getDaysInMonth(_currentMonth.year, _currentMonth.month);
    final firstDayOffset = DateUtils.firstDayOffset(_currentMonth.year, _currentMonth.month, const DefaultMaterialLocalizations());
    
    return Column(
      children: [
        // Month Selector
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left, size: 20),
              onPressed: () => setState(() => _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1)),
            ),
            Text(
              DateFormat('MMMM yyyy').format(_currentMonth),
              style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Serif', fontSize: 15),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right, size: 20),
              onPressed: () => setState(() => _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1)),
            ),
          ],
        ),
        // Weekday Header
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildWeekday('Sun', Colors.red),
              _buildWeekday('Mon', Colors.black87),
              _buildWeekday('Tue', Colors.black87),
              _buildWeekday('Wed', Colors.black87),
              _buildWeekday('Thu', Colors.black87),
              _buildWeekday('Fri', Colors.black87),
              _buildWeekday('Sat', Colors.blue),
            ],
          ),
        ),
        // Days Grid
        GridView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7),
          itemCount: daysInMonth + firstDayOffset,
          itemBuilder: (context, index) {
            if (index < firstDayOffset) return const SizedBox();
            final day = index - firstDayOffset + 1;
            final date = DateTime(_currentMonth.year, _currentMonth.month, day);
            final isSelected = DateUtils.isSameDay(date, _selectedDate);
            final isOutOfRange = date.isBefore(widget.firstDate) || date.isAfter(widget.lastDate);
            
            Color textColor = Colors.black;
            if (date.weekday == DateTime.sunday) textColor = Colors.red;
            if (date.weekday == DateTime.saturday) textColor = Colors.blue;
            if (isOutOfRange) textColor = Colors.grey.withOpacity(0.3);

            return InkWell(
              onTap: isOutOfRange ? null : () {
                setState(() => _selectedDate = date);
                widget.onDateChanged(date);
              },
              child: Container(
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.black : Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '$day',
                    style: TextStyle(
                      color: isSelected ? Colors.white : textColor,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildWeekday(String label, Color color) {
    return Expanded(
      child: Center(
        child: Text(
          label,
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}


void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint("✅ Firebase initialized successfully");
  } catch (e) {
    debugPrint("❌ Firebase initialization failed: $e");
  }
  
  // 폰트 깜빡임 방지: 주요 폰트 미리 로드
  await GoogleFonts.pendingFonts([
    GoogleFonts.unifrakturCook(),
    GoogleFonts.playfairDisplay(),
    GoogleFonts.libreBaskerville(),
  ]);

  // 광고 SDK 초기화 (모바일 플랫폼에서만 실행)
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    await MobileAds.instance.initialize();
  }
  
  runApp(const NewsCollectorApp());
}

class NewsCollectorApp extends StatelessWidget {
  const NewsCollectorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'News Collector',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E3A8A),
          surface: Colors.white.withOpacity(0.9), // Aged paper background
          primary: const Color(0xFF1E3A8A), // Blue from the vest
          secondary: const Color(0xFF8B4513), // Stool/Earth tone
          onSurface: const Color(0xFF1A1A1A), // Ink black
        ),
        // Vintage newspaper typography
        textTheme: TextTheme(
          displayLarge: GoogleFonts.playfairDisplay(fontWeight: FontWeight.w900, color: const Color(0xFF1A1A1A)),
          titleLarge: GoogleFonts.playfairDisplay(fontWeight: FontWeight.bold, color: const Color(0xFF1A1A1A)),
          titleMedium: GoogleFonts.libreBaskerville(fontWeight: FontWeight.bold, color: const Color(0xFF1A1A1A)),
          bodyLarge: GoogleFonts.libreBaskerville(color: const Color(0xFF1A1A1A)),
          bodyMedium: GoogleFonts.libreBaskerville(color: const Color(0xFF2C2C2C), height: 1.4),
          labelSmall: GoogleFonts.libreBaskerville(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black54),
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFF1A1A1A),
          thickness: 0.8,
          space: 1,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF1EEE4),
          foregroundColor: Color(0xFF1A1A1A),
          elevation: 0,
        ),
        scaffoldBackgroundColor: const Color(0xFFF1EEE4),
        checkboxTheme: CheckboxThemeData(
          fillColor: MaterialStateProperty.resolveWith((states) => states.contains(MaterialState.selected) ? const Color(0xFF1A1A1A) : null),
          side: const BorderSide(color: Color(0xFF1A1A1A), width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(0)),
        ),
        datePickerTheme: DatePickerThemeData(
          backgroundColor: const Color(0xFFF1EEE4),
          headerBackgroundColor: const Color(0xFF1A1A1A),
          headerForegroundColor: const Color(0xFFF1EEE4),
          surfaceTintColor: Colors.transparent,
          dayStyle: GoogleFonts.libreBaskerville(),
          yearStyle: GoogleFonts.libreBaskerville(),
          shape: const RoundedRectangleBorder(),
          dividerColor: const Color(0xFF1A1A1A),
        ),
      ),
      home: UpgradeAlert(
        child: const CustomSplashScreen(),
      ),
    );
  }
}

class CustomSplashScreen extends StatefulWidget {
  const CustomSplashScreen({super.key});

  @override
  State<CustomSplashScreen> createState() => _CustomSplashScreenState();
}

class _CustomSplashScreenState extends State<CustomSplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500), // 서서히 나타나는 효과를 위해 시간 조절
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _startAnimation();
  }

  void _startAnimation() async {
    // Wait a bit to ensure smooth transition from native splash
    await Future.delayed(const Duration(milliseconds: 100));
    FlutterNativeSplash.remove();

    // Start fade-in animation
    await _controller.forward();
    
    // Show splash image for 2 seconds then navigate
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const NewsCollectorHomePage()),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1EEE4),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SizedBox.expand(
          child: Image.asset(
            'assets/images/splash_image.png',
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}

class LogEntry {
  final String message;
  final Color? color;
  final bool isHeader;
  final bool isSummary;
  LogEntry(this.message, {this.color, this.isHeader = false, this.isSummary = false});
}

class NewsCollectorHomePage extends StatefulWidget {
  const NewsCollectorHomePage({super.key});

  @override
  State<NewsCollectorHomePage> createState() => _NewsCollectorHomePageState();
}

class _NewsCollectorHomePageState extends State<NewsCollectorHomePage> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _aiPromptController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _aiPromptFocusNode = FocusNode();
  final NewsCollectorService _crawlerService = NewsCollectorService();
  final ScrollController _logScrollController = ScrollController();
  
  Map<String, List<Map<String, dynamic>>> _newsSourcesMap = {};
  bool _isSourceLoading = true;
  int _totalPublishersCount = 0;
  List<String> _availableCategories = [];

  final Set<String> _selectedSources = {};
  String _selectedPeriod = '1 Day';
  final List<String> _periods = ['1 Day', '3 Days', '1 Week', '1 Month', '1 Year', 'Dynamic'];
  DateTimeRange? _selectedDateRange;

  bool _isLoading = false;
  List<NewsArticle> _results = [];
  Timer? _periodicTimer;
  List<String> _searchHistory = [];
  List<String> _emailHistory = [];
  List<String> _aiHistory = [];
  
  // UI states
  double _splitRatio = 0.5;
  bool _isResultVisible = true;
  bool _isLogVisible = true;
  bool _isLogAutoScrollEnabled = true;
  double _logPanelHeight = 250.0;
  List<LogEntry> _logs = [];
  double _progress = 0.0;
  bool _isCancelled = false;
  bool _isTranslating = false;
  bool _suppressSearchHistoryAuto = false;
  bool _suppressAiHistoryAuto = false;
  bool _suppressEmailHistoryAuto = false;
  String _targetLanguage = 'ko'; // Default to Korean
  String _sortBy = 'Latest';
  final List<String> _sortOptions = ['Latest', 'Oldest', 'Publisher', 'Accuracy'];
  bool _showMobileResults = false; // Mobile navigation state
  String? _aiInsight;
  bool _isAIAnalyzing = false;
  bool _isAIExpanded = true;
  String _aiProgressMsg = "";
  List<NewsArticle> _aiReferencedArticles = [];
  final Set<String> _visitedUrls = {};

  InterstitialAd? _interstitialAd;
  bool _isInterstitialAdLoaded = false;
  RewardedAd? _rewardedAd;
  bool _isRewardedAdLoaded = false;
  BannerAd? _bottomBannerAd;
  bool _isBottomBannerAdLoaded = false;

  String _selectedAIProvider = 'Gemini';
  String _selectedAIModel = 'gemini-3.1-flash-lite';
  final Map<String, List<String>> _aiModelOptions = {
    'ChatGPT': ['gpt-4o', 'gpt-4o-mini', 'gpt-3.5-turbo'],
    'Gemini': [
      'gemini-3.8-flash',
      'gemini-3.7-flash',
      'gemini-3.6-flash',
      'gemini-3.5-flash',
      'gemini-3.5-flash-lite',
      'gemini-3.1-flash-lite'
    ],
    'Claude': ['claude-3-5-sonnet-20240620', 'claude-3-opus-20240229', 'claude-3-haiku-20240307'],
  };
  final Map<String, String> _aiApiKeys = {};

  Future<void> _loadSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() { _searchHistory = prefs.getStringList('search_history') ?? []; });
  }

  Future<void> _loadEmailHistory() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() { _emailHistory = prefs.getStringList('email_history') ?? []; });
  }

  Future<void> _loadAiHistory() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() { _aiHistory = prefs.getStringList('ai_history') ?? []; });
  }

  Future<void> _saveSearchQuery(String query) async {
    if (query.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    List<String> history = prefs.getStringList('search_history') ?? [];
    history.remove(query);
    history.insert(0, query);
    if (history.length > 20) history = history.sublist(0, 20);
    await prefs.setStringList('search_history', history);
    setState(() { _searchHistory = history; });
  }

  Future<void> _saveEmailQuery(String email) async {
    if (email.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    List<String> history = prefs.getStringList('email_history') ?? [];
    history.remove(email);
    history.insert(0, email);
    if (history.length > 20) history = history.sublist(0, 20);
    await prefs.setStringList('email_history', history);
    setState(() { _emailHistory = history; });
  }

  Future<void> _saveAiQuery(String prompt) async {
    if (prompt.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    List<String> history = prefs.getStringList('ai_history') ?? [];
    history.remove(prompt);
    history.insert(0, prompt);
    if (history.length > 20) history = history.sublist(0, 20);
    await prefs.setStringList('ai_history', history);
    setState(() { _aiHistory = history; });
  }

  Future<void> _deleteHistoryItem(String query) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> history = prefs.getStringList('search_history') ?? [];
    history.remove(query);
    await prefs.setStringList('search_history', history);
    setState(() { _searchHistory = history; });
  }

  Future<void> _deleteEmailHistoryItem(String email) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> history = prefs.getStringList('email_history') ?? [];
    history.remove(email);
    await prefs.setStringList('email_history', history);
    setState(() { _emailHistory = history; });
  }

  Future<void> _deleteAiHistoryItem(String prompt) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> history = prefs.getStringList('ai_history') ?? [];
    history.remove(prompt);
    await prefs.setStringList('ai_history', history);
    setState(() { _aiHistory = history; });
  }

  void _showHistoryDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            const Icon(Icons.history, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: const Text('Search History', style: TextStyle(fontFamily: 'Serif', fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.8, // 가로폭 확대
          child: _searchHistory.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text('No history yet.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: _searchHistory.length,
                  separatorBuilder: (context, index) => const Divider(height: 1, thickness: 0.5),
                  itemBuilder: (context, index) {
                    final item = _searchHistory[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      title: Text(item, style: const TextStyle(fontSize: 14)),
                      onTap: () {
                        setState(() {
                          _suppressSearchHistoryAuto = true;
                          _searchController.text = item;
                        });
                        Navigator.pop(context);
                      },
                      trailing: IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.clear, size: 16, color: Colors.grey),
                        onPressed: () { _deleteHistoryItem(item); Navigator.pop(context); _showHistoryDialog(); },
                      ),
                    );
                  },
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('CLOSE', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)))],
      ),
    );
  }

  void _showAiHistoryDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            const Icon(Icons.auto_awesome, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: const Text('AI Prompt History', style: TextStyle(fontFamily: 'Serif', fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.8,
          child: _aiHistory.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text('No history yet.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: _aiHistory.length,
                  separatorBuilder: (context, index) => const Divider(height: 1, thickness: 0.5),
                  itemBuilder: (context, index) {
                    final item = _aiHistory[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      title: Text(item, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, height: 1.3)),
                      onTap: () {
                        setState(() {
                          _suppressAiHistoryAuto = true;
                          _aiPromptController.text = item;
                        });
                        Navigator.pop(context);
                      },
                      trailing: IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.clear, size: 16, color: Colors.grey),
                        onPressed: () { _deleteAiHistoryItem(item); Navigator.pop(context); _showAiHistoryDialog(); },
                      ),
                    );
                  },
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('CLOSE', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)))],
      ),
    );
  }

  void _showEmailHistoryDialog(TextEditingController ctrl, Function(String) onSelected) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            const Icon(Icons.email, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: const Text('Email History', style: TextStyle(fontFamily: 'Serif', fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.8,
          child: _emailHistory.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text('No history yet.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: _emailHistory.length,
                  separatorBuilder: (context, index) => const Divider(height: 1, thickness: 0.5),
                  itemBuilder: (context, index) {
                    final item = _emailHistory[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      title: Text(item, style: const TextStyle(fontSize: 14)),
                      onTap: () {
                        setState(() {
                          _suppressEmailHistoryAuto = true;
                        });
                        ctrl.text = item;
                        Navigator.pop(context);
                        onSelected(item);
                      },
                      trailing: IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.clear, size: 16, color: Colors.grey),
                        onPressed: () { _deleteEmailHistoryItem(item); Navigator.pop(context); _showEmailHistoryDialog(ctrl, onSelected); },
                      ),
                    );
                  },
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('CLOSE', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)))],
      ),
    );
  }

  void _showEmailDialog() {
    if (_results.isEmpty) {
      _showSnackBar('검색 결과가 없습니다.');
      return;
    }

    final dialogEmailController = TextEditingController(text: _emailController.text);
    final dialogEmailFocusNode = FocusNode();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('이메일로 결과 보내기'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('수집된 기사 리스트를 이메일로 전송합니다.', style: TextStyle(fontSize: 13, color: Colors.grey)),
                const SizedBox(height: 16),
                Autocomplete<String>(
                  textEditingController: dialogEmailController,
                  focusNode: dialogEmailFocusNode,
                  optionsBuilder: (textValue) {
                    if (_suppressEmailHistoryAuto) {
                      _suppressEmailHistoryAuto = false;
                      return const Iterable<String>.empty();
                    }
                    return textValue.text == '' 
                        ? const Iterable<String>.empty() 
                        : _emailHistory.where((opt) => opt.toLowerCase().contains(textValue.text.toLowerCase()));
                  },
                  onSelected: (sel) => setDialogState(() => dialogEmailController.text = sel),
                  fieldViewBuilder: (ctx, ctrl, focus, onSub) {
                    return TextField(
                      controller: ctrl,
                      focusNode: focus,
                      decoration: InputDecoration(
                        hintText: '이메일 주소 입력',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.email),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.history), 
                          onPressed: () => _showEmailHistoryDialog(ctrl, (val) => setDialogState(() => dialogEmailController.text = val))
                        ),
                      ),
                      onSubmitted: (v) => onSub(),
                    );
                  },
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
              ElevatedButton(
                onPressed: () async {
                  final email = dialogEmailController.text.trim();
                  if (email.isEmpty || !email.contains('@')) {
                    _showSnackBar('유효한 이메일을 입력하세요.');
                    return;
                  }
                  
                  Navigator.pop(context);
                  _showSnackBar('이메일 발송 중...');
                  
                  final success = await _crawlerService.sendEmail(email, _results);
                  if (success) {
                    _saveEmailQuery(email);
                    _emailController.text = email;
                    _showSnackBar('이메일이 성공적으로 발송되었습니다.');
                  } else {
                    _showSnackBar('이메일 발송에 실패했습니다.');
                  }
                },
                child: const Text('전송'),
              ),
            ],
          );
        }
      ),
    ).whenComplete(() {
      dialogEmailFocusNode.dispose();
    });
  }

  Future<void> _loadInterstitialAd() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    InterstitialAd.load(
      adUnitId: AdHelper.interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isInterstitialAdLoaded = true;
          _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _isInterstitialAdLoaded = false;
              _loadInterstitialAd(); // Load next one
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _isInterstitialAdLoaded = false;
              _loadInterstitialAd();
            },
          );
        },
        onAdFailedToLoad: (err) {
          debugPrint('InterstitialAd failed to load: $err');
          _isInterstitialAdLoaded = false;
        },
      ),
    );
  }

  Future<void> _loadRewardedAd() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    RewardedAd.load(
      adUnitId: AdHelper.rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _isRewardedAdLoaded = true;
          _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _isRewardedAdLoaded = false;
              _loadRewardedAd(); // Load next one
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _isRewardedAdLoaded = false;
              _loadRewardedAd();
            },
          );
        },
        onAdFailedToLoad: (err) {
          debugPrint('RewardedAd failed to load: $err');
          _isRewardedAdLoaded = false;
        },
      ),
    );
  }

  void _loadBottomBannerAd() {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    _bottomBannerAd = BannerAd(
      adUnitId: AdHelper.bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          setState(() {
            _isBottomBannerAdLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          debugPrint('BannerAd failed to load: $error');
        },
      ),
    )..load();
  }

  void _showInterstitialAd(VoidCallback onAdClosed) {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS) && _isInterstitialAdLoaded && _interstitialAd != null) {
      _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          _isInterstitialAdLoaded = false;
          _loadInterstitialAd();
          onAdClosed();
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          ad.dispose();
          _isInterstitialAdLoaded = false;
          _loadInterstitialAd();
          onAdClosed();
        },
      );
      _interstitialAd!.show();
    } else {
      onAdClosed();
    }
  }

  void _showRewardedAd(VoidCallback onAdClosed) {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS) && _isRewardedAdLoaded && _rewardedAd != null) {
      _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          _isRewardedAdLoaded = false;
          _loadRewardedAd();
          onAdClosed();
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          ad.dispose();
          _isRewardedAdLoaded = false;
          _loadRewardedAd();
          onAdClosed();
        },
      );
      _rewardedAd!.show(onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
        debugPrint('User earned reward: ${reward.amount} ${reward.type}');
      });
    } else {
      onAdClosed();
    }
  }

  @override
  void initState() {
    super.initState();
    _loadNewsSources();
    _loadAllAiKeys();
    _loadSearchHistory();
    _loadEmailHistory();
    _loadAiHistory();
    _loadInterstitialAd();
    _loadRewardedAd();
    _loadBottomBannerAd();
  }

  Future<void> _loadAllAiKeys() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _aiApiKeys['ChatGPT'] = prefs.getString('key_chatgpt') ?? '';
      _aiApiKeys['Gemini'] = prefs.getString('key_gemini') ?? '';
      _aiApiKeys['Claude'] = prefs.getString('key_claude') ?? '';
    });
  }

  Future<void> _saveAiKey(String provider, String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('key_${provider.toLowerCase()}', key);
    setState(() { _aiApiKeys[provider] = key; });
    
    if (provider == 'Gemini') {
      // _updateGeminiModels(); // Dynamic model update disabled, using static list
    }
  }

  Future<void> _updateGeminiModels() async {
    final key = _aiApiKeys['Gemini'];
    if (key == null || key.isEmpty) return;

    final models = await _crawlerService.fetchGeminiModels(key);
    if (models.isNotEmpty) {
      setState(() {
        _aiModelOptions['Gemini'] = models;
        // If current model is not in the new list, and we are on Gemini, 
        // update to the best match or first available
        if (_selectedAIProvider == 'Gemini' && !models.contains(_selectedAIModel)) {
          if (models.contains('gemini-1.5-flash')) {
            _selectedAIModel = 'gemini-1.5-flash';
          } else {
            _selectedAIModel = models.first;
          }
        }
      });
      _addLog('[System] Gemini models updated dynamically: ${models.length} models found.');
    } else {
      _addLog('[System] Could not fetch Gemini models. Using defaults.', isError: true);
    }
  }

  void _showApiKeyGuide(String provider) {
    String title = "How to get $provider API Key";
    String url = "";
    String steps = "";

    if (provider == 'Gemini') {
      url = "https://aistudio.google.com/app/apikey";
      steps = "1. Visit Google AI Studio.\n2. Sign in with your Google account.\n3. Click 'Create API key' button.\n4. Copy and paste the key into this app.";
    } else if (provider == 'ChatGPT') {
      url = "https://platform.openai.com/api-keys";
      steps = "1. Visit OpenAI Platform.\n2. Sign in and go to the API Keys section.\n3. Click 'Create new secret key'.\n4. Copy and paste the key into this app.";
    } else if (provider == 'Claude') {
      url = "https://console.anthropic.com/settings/keys";
      steps = "1. Visit Anthropic Console.\n2. Sign in and go to Settings > API Keys.\n3. Create a new key.\n4. Copy and paste the key into this app.";
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(steps, style: const TextStyle(fontSize: 13, height: 1.5)),
            const SizedBox(height: 16),
            const Text("Link:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
            InkWell(
              onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
              child: Text(
                url,
                style: const TextStyle(fontSize: 12, color: Colors.blue, decoration: TextDecoration.underline),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("GOT IT")),
        ],
      ),
    );
  }

  void _showAiSettingDialog() {
    String tempProvider = _selectedAIProvider;
    String tempModel = _selectedAIModel;
    bool isKeyVisible = false;
    final controller = TextEditingController(text: _aiApiKeys[tempProvider]);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('AI SETTING', style: TextStyle(fontFamily: 'Serif', fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: const Text('AI PROVIDER', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black54)),
                  ),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    value: tempProvider,
                    decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12)),
                    items: _aiModelOptions.keys.map((ai) => DropdownMenuItem(value: ai, child: Text(ai.toUpperCase(), style: const TextStyle(fontSize: 13)))).toList(),
                    onChanged: (val) {
                      setDialogState(() {
                        tempProvider = val!;
                        tempModel = _aiModelOptions[val]!.first;
                        controller.text = _aiApiKeys[tempProvider] ?? '';
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: const Text('AI MODEL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black54)),
                  ),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    value: tempModel,
                    decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12)),
                    items: _aiModelOptions[tempProvider]!.map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontSize: 12)))).toList(),
                    onChanged: (val) => setDialogState(() => tempModel = val!),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('API KEY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black54)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: InkWell(
                          onTap: () => _showApiKeyGuide(tempProvider),
                          child: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'How to Get API Key?', 
                              style: TextStyle(fontSize: 10, color: Colors.blue, fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: controller,
                    obscureText: !isKeyVisible,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: 'Enter API Key for $tempProvider',
                      suffixIcon: IconButton(
                        icon: Icon(isKeyVisible ? Icons.visibility_off : Icons.visibility, size: 20),
                        onPressed: () => setDialogState(() => isKeyVisible = !isKeyVisible),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('Your key is saved locally on this device.', style: TextStyle(fontSize: 9, color: Colors.grey)),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
              ElevatedButton(
                onPressed: () {
                  _saveAiKey(tempProvider, controller.text.trim());
                  setState(() {
                    _selectedAIProvider = tempProvider;
                    _selectedAIModel = tempModel;
                  });
                  Navigator.pop(context);
                  _showSnackBar('$tempProvider SETTING UPDATED.');
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white),
                child: const Text('SAVE SETTING'),
              ),
            ],
          );
        }
      ),
    );
  }

  Future<void> _loadNewsSources() async {
    try {
      // 1. Core Config 로드
      final String countriesRes = await rootBundle.loadString('assets/config/core/countries.json');
      final Map<String, dynamic> countriesData = json.decode(countriesRes);
      
      final String categoriesRes = await rootBundle.loadString('assets/config/core/categories.json');
      final Map<String, dynamic> categoriesData = json.decode(categoriesRes);
      
      final String publishersRes = await rootBundle.loadString('assets/config/publishers/all_publishers.json');
      final Map<String, dynamic> publishersData = json.decode(publishersRes);
      
      // 플랫폼별 국가 코드 가져오기 (Web, Windows, Mobile 통합)
      String? deviceLocale;
      try {
        if (kIsWeb) {
          deviceLocale = await Devicelocale.currentLocale;
        } else if (Platform.isWindows) {
          deviceLocale = Platform.localeName;
        } else {
          deviceLocale = await Devicelocale.currentLocale;
        }
      } catch (e) {
        debugPrint('Locale detection error: $e');
      }

      String deviceCountryCode = 'US';
      if (deviceLocale != null) {
        final parts = deviceLocale.contains('_') ? deviceLocale.split('_') : deviceLocale.split('-');
        if (parts.length > 1) {
          deviceCountryCode = parts.last.toUpperCase();
        } else if (deviceLocale.length == 2) {
          final lang = deviceLocale.toLowerCase();
          if (lang == 'ko') deviceCountryCode = 'KR';
          else if (lang == 'ja') deviceCountryCode = 'JP';
          else if (lang == 'zh') deviceCountryCode = 'CN';
          else if (lang == 'de') deviceCountryCode = 'DE';
          else if (lang == 'fr') deviceCountryCode = 'FR';
          else if (lang == 'en') deviceCountryCode = 'US';
        }
      }

      // 국가 순서 결정 (사용자 국가 우선)
      final List<String> countryOrder = ['US', 'DE', 'GB', 'FR', 'KR', 'JP', 'CN'];
      if (countryOrder.contains(deviceCountryCode)) {
        countryOrder.remove(deviceCountryCode);
        countryOrder.insert(0, deviceCountryCode);
      }

      final Map<String, List<Map<String, dynamic>>> tempMap = {};
      int totalCount = 0;
      final Set<String> categories = {};

      for (var code in countryOrder) {
        if (!countriesData.containsKey(code)) continue;
        
        final countryInfo = countriesData[code];
        final String countryName = countryInfo['name'];
        final String countryLang = countryInfo['language'];
        
        final List<Map<String, dynamic>> publishersInCountry = [];
        
        publishersData.forEach((id, data) {
          final publisherData = data as Map<String, dynamic>;
          if (publisherData['country'] == code) {
            final pub = Map<String, dynamic>.from(publisherData);
            pub['id'] = id;
            pub['countryName'] = countryName;
            pub['lang'] = countryLang;
            publishersInCountry.add(pub);
            
            if (pub['type'] != null) categories.add(pub['type'] as String);
          }
        });
        
        if (publishersInCountry.isNotEmpty) {
          tempMap[countryName] = publishersInCountry;
          totalCount += publishersInCountry.length;
        }
      }

      // 4. 카테고리 목록 설정 (categories.json 기반)
      final List<String> sortedCategories = categoriesData.keys.toList();
      // 순서 조정 (원하는 경우)
      const preferredOrder = ['general', 'politics', 'economy', 'technology', 'ai', 'science', 'automotive', 'energy', 'sports_entertainment'];
      sortedCategories.sort((a, b) {
        int idxA = preferredOrder.indexOf(a);
        int idxB = preferredOrder.indexOf(b);
        if (idxA == -1) idxA = 99;
        if (idxB == -1) idxB = 99;
        return idxA.compareTo(idxB);
      });

      setState(() {
        _newsSourcesMap = tempMap;
        _totalPublishersCount = totalCount;
        _availableCategories = sortedCategories;
        _isSourceLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading news sources: $e');
      setState(() { _isSourceLoading = false; });
      _showSnackBar('Failed to load news sources: $e');
    }
  }

  void _sortResults() {
    setState(() {
      if (_sortBy == 'Latest') {
        _results.sort((a, b) => (b.pubDate ?? '').compareTo(a.pubDate ?? ''));
      } else if (_sortBy == 'Oldest') {
        _results.sort((a, b) => (a.pubDate ?? '').compareTo(b.pubDate ?? ''));
      } else if (_sortBy == 'Publisher') {
        _results.sort((a, b) => a.source.compareTo(b.source));
      } else if (_sortBy == 'Accuracy') {
        final query = _searchController.text.toLowerCase();
        _results.sort((a, b) {
          int scoreA = _calculateAccuracy(a, query);
          int scoreB = _calculateAccuracy(b, query);
          return scoreB.compareTo(scoreA);
        });
      }
    });
  }

  int _calculateAccuracy(NewsArticle article, String query) {
    int score = 0;
    final title = article.title.toLowerCase();
    final snippet = article.snippet.toLowerCase();
    final terms = query.split(RegExp(r'\s+')).where((t) => t.length > 1);
    for (var term in terms) {
      if (title.contains(term)) score += 5;
      if (snippet.contains(term)) score += 1;
    }
    return score;
  }

  void _addLog(String message, {bool? isMatch, bool? isError, bool? isHeader, bool? isSummary}) {
    Color? color;
    if (isMatch == true) color = Colors.green;
    else if (isMatch == false) color = Colors.red;
    else if (isError == true) color = Colors.orange;
    else if (isHeader == true || isSummary == true) color = Colors.blue[900];

    setState(() {
      _logs.add(LogEntry(message, color: color, isHeader: isHeader ?? false, isSummary: isSummary ?? false));
    });
    
    // Auto scroll to bottom if enabled
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isLogAutoScrollEnabled && _logScrollController.hasClients) {
        final double target = _logScrollController.position.maxScrollExtent;
        _logScrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _buildEstimationRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.libreBaskerville(fontSize: 11, color: Colors.black87)),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'Serif')),
        ],
      ),
    );
  }

  Future<DateTime?> _showCollectorDatePicker(BuildContext context, DateTime initialDate, DateTime firstDate, DateTime lastDate) async {
    DateTime selectedDate = initialDate;
    String? dateError;
    final controller = TextEditingController(text: DateFormat('MM/dd/yyyy').format(initialDate));
    
    return showDialog<DateTime>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: const Color(0xFFF1EEE4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: EdgeInsets.zero,
            content: SingleChildScrollView(
              child: SizedBox(
                width: 330,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Custom Header
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: const BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                      ),
                      width: double.infinity,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('SELECT DATE', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                          const SizedBox(height: 8),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              DateFormat('EEE, MMM d, yyyy').format(selectedDate),
                              style: const TextStyle(color: Colors.white, fontSize: 24, fontFamily: 'Serif', fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Input Area
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: TextField(
                        controller: controller,
                        keyboardType: TextInputType.number,
                        inputFormatters: [DateInputFormatter()],
                        style: const TextStyle(fontSize: 14, fontFamily: 'Serif'),
                        decoration: InputDecoration(
                          labelText: 'Enter Date',
                          hintText: 'mm/dd/yyyy',
                          isDense: true,
                          border: const OutlineInputBorder(),
                          errorText: dateError,
                          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54),
                        ),
                        onChanged: (v) {
                          setState(() => dateError = null);
                          if (v.length == 10) {
                            try {
                              final d = DateFormat('MM/dd/yyyy').parseStrict(v);
                              if (d.isBefore(firstDate) || d.isAfter(lastDate)) {
                                setState(() => dateError = 'Out of range');
                              } else {
                                setState(() {
                                  selectedDate = d;
                                  dateError = null;
                                });
                              }
                            } catch (_) {
                              setState(() => dateError = 'Invalid Date');
                            }
                          }
                        },
                      ),
                    ),
                    // Calendar Area
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: CollectorCalendar(
                        initialDate: selectedDate,
                        firstDate: firstDate,
                        lastDate: lastDate,
                        onDateChanged: (d) {
                          setState(() {
                            selectedDate = d;
                            dateError = null;
                            controller.text = DateFormat('MM/dd/yyyy').format(d);
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Footer Actions
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 0, 12, 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context), 
                            child: const Text('CANCEL', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 13))
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: dateError != null ? null : () => Navigator.pop(context, selectedDate), 
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black, 
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                              elevation: 0,
                            ),
                            child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))
                          ),
                        ],
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

  Future<void> _showCustomDateRangePicker() async {
    DateTime tempStart = _selectedDateRange?.start ?? DateTime.now().subtract(const Duration(days: 7));
    DateTime tempEnd = _selectedDateRange?.end ?? DateTime.now();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFFF1EEE4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("Select Date Range", style: TextStyle(fontFamily: 'Serif', fontWeight: FontWeight.bold, fontSize: 18)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildCustomDateTile(
                label: "Start Date", 
                date: tempStart, 
                onTap: () async {
                  final picked = await _showCollectorDatePicker(
                    context,
                    tempStart,
                    DateTime(1900),
                    DateTime.now(),
                  );
                  if (picked != null) setDialogState(() => tempStart = picked);
                }
              ),
              const SizedBox(height: 12),
              _buildCustomDateTile(
                label: "End Date", 
                date: tempEnd, 
                onTap: () async {
                  final picked = await _showCollectorDatePicker(
                    context,
                    tempEnd,
                    tempStart,
                    DateTime.now(),
                  );
                  if (picked != null) setDialogState(() => tempEnd = picked);
                }
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx), 
              child: const Text("CANCEL", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))
            ),
            ElevatedButton(
              onPressed: () {
                if (tempEnd.isBefore(tempStart)) {
                  _showSnackBar("End date cannot be before start date");
                  return;
                }
                setState(() {
                  _selectedDateRange = DateTimeRange(start: tempStart, end: tempEnd);
                });
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text("OK", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomDateTile({required String label, required DateTime date, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.bold)),
            Text("${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}", 
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, fontFamily: 'Serif')),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeForPicker(BuildContext context, Widget child) {
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: const ColorScheme.light(
          primary: Colors.black,
          onPrimary: Colors.white,
          onSurface: Colors.black,
          surface: Color(0xFFF1EEE4),
        ),
        datePickerTheme: DatePickerThemeData(
          headerBackgroundColor: Colors.black,
          headerForegroundColor: Colors.white,
          backgroundColor: const Color(0xFFF1EEE4),
          dayStyle: GoogleFonts.libreBaskerville(fontSize: 14),
          weekdayStyle: GoogleFonts.libreBaskerville(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        textTheme: Theme.of(context).textTheme.copyWith(
          labelLarge: GoogleFonts.libreBaskerville(fontSize: 14),
        ),
      ),
      child: Localizations.override(
        context: context,
        delegates: const [CustomMaterialLocalizationsDelegate()],
        child: child,
      ),
    );
  }

  void _showSearchInfoDialog(bool isDetail) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFF1EEE4),
        shape: const RoundedRectangleBorder(side: BorderSide(color: Colors.black, width: 0.5)),
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isDetail ? Icons.travel_explore : Icons.bolt, 
                size: 20, 
                color: isDetail ? Colors.amber[800] : const Color(0xFF722F37)
              ),
              const SizedBox(width: 10),
              Text(
                isDetail ? 'DETAIL SEARCH' : 'SIMPLE SEARCH', 
                style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 0.5)
              ),
            ],
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              _buildEstimationRowItem(
                isDetail 
                  ? "Performs a deep scan of historical archives."
                  : "Scans current top headlines quickly."
              ),
              _buildEstimationRowItem(
                isDetail 
                  ? "Splits complex keywords into batches for higher accuracy."
                  : "Sends a single request without splitting keywords or dates."
              ),
              _buildEstimationRowItem(
                isDetail 
                  ? "Automatically segments the time period into multiple slots (up to 12) to ensure no articles are missed."
                  : "Much faster than Detail Search but may miss some older or niche results due to engine limitations."
              ),
              _buildEstimationRowItem(
                isDetail 
                  ? "Best for comprehensive research and finding older reports."
                  : "Best for a quick overview of the latest news."
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black, 
              foregroundColor: Colors.white,
              shape: const RoundedRectangleBorder(),
              elevation: 0,
            ),
            child: const Text('GOT IT', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildEstimationRowItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
          Expanded(
            child: Text(
              text, 
              style: GoogleFonts.libreBaskerville(fontSize: 13, height: 1.4, color: Colors.black87)
            ),
          ),
        ],
      ),
    );
  }


  void _showSearchQueryGuide() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFF1EEE4),
        shape: const RoundedRectangleBorder(side: BorderSide(color: Colors.black, width: 0.5)),
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.info_outline, size: 20, color: Colors.black),
              const SizedBox(width: 10),
              Text(
                'SEARCH QUERY GUIDE', 
                style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 0.5)
              ),
            ],
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Use logical operators to refine your search:', 
                style: GoogleFonts.libreBaskerville(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)
              ),
              const SizedBox(height: 16),
              _buildQueryGuideItem('AND / &&', 'Both terms must exist.', 'apple AND banana'),
              _buildQueryGuideItem('OR / ||', 'Either term can exist.', 'apple OR banana'),
              _buildQueryGuideItem('NOT / !', 'Exclude specific terms.', 'apple NOT rotten'),
              _buildQueryGuideItem('()', 'Group multiple terms.', '(apple OR banana) AND fruit'),
              _buildQueryGuideItem('""', 'Search for exact phrase.', '"Stock Market"'),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(color: Colors.black26),
              ),
              Text(
                '* Operators must be in UPPERCASE.', 
                style: GoogleFonts.libreBaskerville(fontSize: 11, color: const Color(0xFF722F37), fontWeight: FontWeight.bold)
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black, 
              foregroundColor: Colors.white,
              shape: const RoundedRectangleBorder(),
              elevation: 0,
            ),
            child: const Text('GOT IT', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildQueryGuideItem(String op, String desc, String example) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(op, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'Serif')),
              const SizedBox(width: 8),
              Expanded(child: Text(desc, style: GoogleFonts.libreBaskerville(fontSize: 12, color: Colors.black87))),
            ],
          ),
          const SizedBox(height: 4),
          Text('  Ex: $example', style: GoogleFonts.libreBaskerville(fontSize: 11, color: Colors.black54, fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }

  Future<bool> _showExitDialog() async {
    return await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFF1EEE4),
        shape: const RoundedRectangleBorder(side: BorderSide(color: Colors.black, width: 0.5)),
        title: Text(
          'EXIT APPLICATION', 
          style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 0.5),
          textAlign: TextAlign.center,
        ),
        content: Text(
          'Are you sure you want to exit the app?', 
          style: GoogleFonts.libreBaskerville(fontSize: 13, color: Colors.black87),
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF722F37), // Dark red for exit
              foregroundColor: Colors.white,
              shape: const RoundedRectangleBorder(),
              elevation: 0,
            ),
            child: const Text('YES, EXIT', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    ) ?? false;
  }

  void _runCrawler({required bool periodic, bool isDetail = true}) async {
    final query = _searchController.text;
    final sourceIds = _selectedSources.toList();
    final period = _selectedPeriod;

    if (query.isEmpty) { _showSnackBar('Please enter a search query'); return; }
    if (sourceIds.isEmpty) { _showSnackBar('Please select at least one news source'); return; }
    if (period == 'Dynamic' && _selectedDateRange == null) { _showSnackBar('Please select a date range'); return; }

    // Dynamic일 경우 실제 날짜 범위를 계산 로직에 전달
    final effectivePeriod = period == 'Dynamic' 
        ? '${_selectedDateRange!.start.toString().split(' ')[0]} to ${_selectedDateRange!.end.toString().split(' ')[0]}' 
        : period;

    // --- Detail Search 전용 안내 팝업 ---
    if (isDetail && !periodic) {
      final batches = _crawlerService.getQueryBatches(query).length;
      final publishers = sourceIds.length;
      final dateSegments = _crawlerService.getDateSegments(effectivePeriod).length;
      final totalAttempts = batches * publishers * dateSegments;
      
      // 회당 약 1.8초 계산 (사용자 측정 기반)
      final estimatedSeconds = (totalAttempts * 1.8).round();
      final estHour = estimatedSeconds ~/ 3600;
      final estMin = (estimatedSeconds % 3600) ~/ 60;
      final estSec = estimatedSeconds % 60;
      
      String timeStr = "";
      if (estHour > 0) timeStr += "$estHour hour${estHour > 1 ? 's' : ''} ";
      if (estMin > 0) timeStr += "$estMin min ";
      if (estSec > 0 || timeStr.isEmpty) timeStr += "$estSec sec";
      timeStr = timeStr.trim();

      final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFFF1EEE4),
          shape: const RoundedRectangleBorder(side: BorderSide(color: Colors.black, width: 0.5)),
          title: Text(
            'DEEP SEARCH ESTIMATION', 
            style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 0.5),
            textAlign: TextAlign.center,
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildEstimationRow('Query Batches', '$batches'),
                _buildEstimationRow('Target Publishers', '$publishers'),
                _buildEstimationRow('Time-based Splits', '$dateSegments'),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(color: Colors.black26),
                ),
                Text('TOTAL SEARCH OPERATIONS', style: GoogleFonts.libreBaskerville(fontSize: 8, color: Colors.black54, letterSpacing: 1)),
                const SizedBox(height: 2),
                Text(
                  NumberFormat('#,###').format(totalAttempts), 
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w300, fontFamily: 'Serif')
                ),
                const SizedBox(height: 12),
                Text('ESTIMATED DURATION', style: GoogleFonts.libreBaskerville(fontSize: 8, color: Colors.black54, letterSpacing: 1)),
                const SizedBox(height: 2),
                Text(timeStr, style: TextStyle(fontSize: 16, color: Colors.blue[900], fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                const Text('Proceed with this search?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false), 
              child: const Text('CANCEL', style: TextStyle(color: Colors.grey, fontSize: 12))
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black, 
                foregroundColor: Colors.white,
                shape: const RoundedRectangleBorder(),
                elevation: 0,
              ),
              child: const Text('START SEARCH', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      );

      if (confirm != true) return;
    }

    if (periodic) { _startPeriodicTask(); _saveSearchQuery(query); return; }

    setState(() {
      _isLoading = true;
      _isTranslating = false;
      _results = [];
      _logs = [];
      _progress = 0.0;
      _isCancelled = false;
      _isResultVisible = true;
      _aiInsight = null;
      _aiReferencedArticles = [];
      _isAIAnalyzing = false;
      _aiProgressMsg = "";
      _isLogVisible = true;
      _showMobileResults = true; // Switch to results view on mobile
    });

    _saveSearchQuery(query);

    try {
      final articles = await _crawlerService.crawl(
        query: query,
        sources: _newsSourcesMap.values
            .expand((list) => list)
            .where((p) => _selectedSources.contains(p['id']))
            .toList(),
        period: effectivePeriod,
        apiKey: _apiKeyController.text,
        selectedCategory: _availableCategories.firstWhere((cat) => _isTypeSelected(cat), orElse: () => 'general'),
        onLog: (msg, {isMatch, isError, isHeader, isSummary}) => 
            _addLog(msg, isMatch: isMatch, isError: isError, isHeader: isHeader, isSummary: isSummary),
        onProgress: (p) => setState(() => _progress = p),
        isCancelled: () => _isCancelled,
        isDetail: isDetail,
        onResult: (article) {
          setState(() {
            // 실시간으로 결과 추가
            _results.add(article);
            // 정렬 기준 유지
            _sortResults();
            // 첫 번째 기사 발견 시 전면 광고 로드
            if (_results.length == 1) {
              _showInterstitialAd(() {});
            }
          });
        },
      );

      setState(() {
        _isLoading = false;
        // 최종 정렬 확인
        _sortResults();
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _addLog('Error: $e', isError: true);
    }
  }

  Future<void> _triggerAIAnalysis({String? newProvider, String? newModel}) async {
    if (_results.isEmpty) return;
    
    final aiPrompt = _aiPromptController.text;
    if (aiPrompt.isEmpty) {
      _showSnackBar('Please enter AI Insight request');
      return;
    }

    setState(() {
      if (newProvider != null) _selectedAIProvider = newProvider;
      if (newModel != null) _selectedAIModel = newModel;
      _isAIAnalyzing = true;
      _aiInsight = null;
      _isCancelled = false; // Reset cancellation flag
      _aiProgressMsg = "AI 분석 준비 중...";
    });

    _saveAiQuery(aiPrompt);
    _addLog('\n[AI Insight] Generating analysis with $_selectedAIProvider ($_selectedAIModel)...', isHeader: true);

    try {
      final insight = await _crawlerService.getAIInsight(
        provider: _selectedAIProvider,
        model: _selectedAIModel,
        apiKey: _aiApiKeys[_selectedAIProvider] ?? '',
        userPrompt: aiPrompt,
        articles: _results,
        onProgress: (msg) => setState(() => _aiProgressMsg = msg),
        isCancelled: () => _isCancelled,
      );

      String displayInsight = insight;
      List<NewsArticle> referenced = [];

      // Extract referenced article numbers
      final sourceMatch = RegExp(r'Primary Sources:\s*([\d\s,]+)').firstMatch(insight);
      if (sourceMatch != null) {
        final numbersStr = sourceMatch.group(1) ?? "";
        final indices = numbersStr.split(',').map((s) => int.tryParse(s.trim())).whereType<int>();
        
        for (var idx in indices) {
          if (idx > 0 && idx <= _results.length) {
            referenced.add(_results[idx - 1]);
          }
        }
        displayInsight = insight.substring(0, sourceMatch.start).trim();
      }

      if (insight == "API Credentials or Articles are missing.") {
        displayInsight = "API Key is missing for $_selectedAIProvider. Please click the 'AI SETTING' button, select '$_selectedAIProvider', and enter your API key.";
      } else if (insight.startsWith("AI Insight Error:") || insight.startsWith("Claude API Error:")) {
        if (insight.toLowerCase().contains("credits") || 
            insight.toLowerCase().contains("quota") || 
            insight.toLowerCase().contains("billing") ||
            insight.toLowerCase().contains("balance is too low")) {
          displayInsight = "You have no credits remaining or your quota has been exceeded. Please check your $_selectedAIProvider billing settings.";
        } else if (insight.contains("503")) {
          displayInsight = "The AI service is currently overwhelmed. Please try again in a few moments.";
        } else if (insight.contains("429")) {
          displayInsight = "Too many requests in a short time. Please wait a bit.";
        } else if (insight.contains("400") || insight.contains("401") || insight.contains("403") || insight.toLowerCase().contains("invalid_request_error")) {
          displayInsight = "Invalid API key or insufficient permissions. Please check your settings.";
        } else {
          displayInsight = "An error occurred during AI analysis. Please try again.";
        }
      }

      setState(() {
        _aiInsight = displayInsight;
        _aiReferencedArticles = referenced;
        _isAIAnalyzing = false;
        _isAIExpanded = true;
      });
      _addLog('\n--- AI Insight Result ---\n$insight', isHeader: true, isSummary: true);
    } catch (e) {
      setState(() {
        _isAIAnalyzing = false;
      });
      _addLog('AI Analysis Error: $e', isError: true);
    }
  }

  void _runTranslation() async {
    if (_results.isEmpty) return;

    setState(() {
      _isLoading = true;
      _isTranslating = true;
      _progress = 0.0;
      _isCancelled = false;
    });

    try {
      await _crawlerService.translateArticles(
        articles: _results,
        targetLang: _targetLanguage == 'original' ? 'original' : _targetLanguage,
        onLog: (msg, {isMatch, isError, isHeader, isSummary}) => 
            _addLog(msg, isMatch: isMatch, isError: isError, isHeader: isHeader, isSummary: isSummary),
        onProgress: (p) => setState(() => _progress = p),
        isCancelled: () => _isCancelled,
      );
      
      setState(() {
        _isLoading = false;
        _isTranslating = false;
      });
      _showSnackBar('Translation Complete');
    } catch (e) {
      setState(() {
        _isLoading = false;
        _isTranslating = false;
      });
      _addLog('Translation error: $e', isError: true);
    }
  }

  void _startPeriodicTask() {
    _periodicTimer?.cancel();
    _showSnackBar('Periodic task started (Every 5 mins)');
    _runCrawler(periodic: false);
    _periodicTimer = Timer.periodic(const Duration(minutes: 5), (timer) { _runCrawler(periodic: false); });
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))));
  }

  void _selectAll(bool select) {
    setState(() {
      if (select) {
        for (var pubs in _newsSourcesMap.values) {
          for (var pub in pubs) { _selectedSources.add(pub['id']); }
        }
      } else { _selectedSources.clear(); }
    });
  }

  void _selectByCategory(String type) {
    setState(() {
      final targetIds = <String>[];
      for (var pubs in _newsSourcesMap.values) {
        for (var pub in pubs) { if (pub['type'] == type) targetIds.add(pub['id']); }
      }
      final allSelected = targetIds.every((id) => _selectedSources.contains(id));
      if (allSelected) { for (var id in targetIds) _selectedSources.remove(id); }
      else { for (var id in targetIds) _selectedSources.add(id); }
    });
  }

  bool _isTypeSelected(String type) {
    final targetIds = <String>[];
    for (var pubs in _newsSourcesMap.values) {
      for (var pub in pubs) { if (pub['type'] == type) targetIds.add(pub['id']); }
    }
    if (targetIds.isEmpty) return false;
    return targetIds.every((id) => _selectedSources.contains(id));
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _aiPromptFocusNode.dispose();
    _interstitialAd?.dispose();
    _rewardedAd?.dispose();
    _bottomBannerAd?.dispose();
    _periodicTimer?.cancel();
    _searchController.dispose();
    _emailController.dispose();
    _apiKeyController.dispose();
    _aiPromptController.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 화면이 너무 작아 프로그램을 표시할 수 없는 경우 처리
        if (constraints.maxWidth < 320 || constraints.maxHeight < 400) {
          return Scaffold(
            backgroundColor: const Color(0xFFE8D4AD),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.screen_lock_portrait, size: 48, color: Colors.black54),
                    const SizedBox(height: 16),
                    Text(
                      'SCREEN SIZE TOO SMALL',
                      style: GoogleFonts.grenzeGotisch(fontSize: 20, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Please enlarge the window to use the application.',
                      style: TextStyle(fontSize: 13, color: Colors.black54),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final bool isMobile = constraints.maxWidth < 600;

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;

            if (isMobile && _showMobileResults) {
              setState(() => _showMobileResults = false);
              return;
            }

            final shouldExit = await _showExitDialog();
            if (shouldExit) {
              SystemNavigator.pop();
            }
          },
          child: Builder(
              builder: (context) {
                // 신문 제호 스타일의 AppBar
                final appBar = AppBar(
                  centerTitle: true,
                  toolbarHeight: 85, // 높이를 줄여서 더 compact하게 변경
                  title: Column(
                    children: [
                      const SizedBox(height: 5),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                        'The News Collector',
                        style: TextStyle(
                          fontFamily: 'OldEnglishTextMT',
                          fontSize: isMobile ? 32 : 42,
                          color: Colors.black,
                          letterSpacing: -0.5,
                        ),
                      ),
                      ),
                      Container(
                        height: 1.2,
                        width: isMobile ? 180 : 280,
                        color: Colors.black,
                        margin: const EdgeInsets.only(top: 2, bottom: 4),
                      ),
                      Text(
                        DateTime.now().toString().split(' ')[0].toUpperCase(),
                        style: TextStyle(
                          fontFamily: 'OldEnglishTextMT',
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                          letterSpacing: 3,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                  ),
                  backgroundColor: const Color(0xFFF1EEE4), // 배경색 변경
                  elevation: 0,
                  bottom: const PreferredSize(
                    preferredSize: Size.fromHeight(1),
                    child: Divider(color: Colors.black, thickness: 2),
                  ),
                  leading: _showMobileResults && isMobile
                      ? IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.black),
                          onPressed: () => setState(() => _showMobileResults = false),
                        )
                      : null,
                );

                if (isMobile) {
                  return Scaffold(
                    appBar: appBar,
                    backgroundColor: const Color(0xFFF1EEE4), // 배경색 변경
                    body: SafeArea(
                      child: _showMobileResults ? _buildRightPanel(isMobile: true) : _buildLeftPanel(isMobile: true),
                    ),
                    bottomNavigationBar: _isBottomBannerAdLoaded && _bottomBannerAd != null
                        ? SafeArea(
                            child: Container(
                              color: const Color(0xFFF1EEE4), // 배경색 변경
                              height: _bottomBannerAd!.size.height.toDouble(),
                              width: double.infinity,
                              alignment: Alignment.center,
                              child: AdWidget(ad: _bottomBannerAd!),
                            ),
                          )
                        : null,
                  );
                }

                return Scaffold(
                  appBar: appBar,
                  backgroundColor: const Color(0xFFF1EEE4), // 배경색 변경
                  body: SafeArea(
                    child: Row(
                      children: [
                        SizedBox(
                          width: _isResultVisible 
                              ? (constraints.maxWidth > 850 
                                  ? (constraints.maxWidth * _splitRatio).clamp(650.0, constraints.maxWidth - 200.0)
                                  : constraints.maxWidth * _splitRatio)
                              : constraints.maxWidth - 40,
                          height: constraints.maxHeight,
                          child: _buildLeftPanel(isMobile: false),
                        ),
                        if (_isResultVisible)
                          GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onHorizontalDragUpdate: (details) {
                              setState(() {
                                double newWidth = (constraints.maxWidth * _splitRatio) + details.delta.dx;
                                // Enforce minimum width of 650px to prevent content overflow
                                if (newWidth < 650.0) newWidth = 650.0;
                                if (newWidth > constraints.maxWidth - 200.0) newWidth = constraints.maxWidth - 200.0;
                                
                                _splitRatio = newWidth / constraints.maxWidth;
                              });
                            },
                            child: MouseRegion(
                              cursor: SystemMouseCursors.resizeLeftRight,
                              child: Container(
                                width: 4,
                                color: Colors.black,
                                child: const Center(child: Icon(Icons.more_vert, size: 16, color: Colors.white)),
                              ),
                            ),
                          ),
                        if (_isResultVisible)
                          Expanded(child: _buildRightPanel(isMobile: false))
                        else
                          Material(
                            color: Colors.black.withOpacity(0.05),
                            child: InkWell(
                              onTap: () => setState(() => _isResultVisible = true),
                              child: Container(
                                width: 40,
                                decoration: const BoxDecoration(border: Border(left: BorderSide(color: Colors.black))),
                                child: const Center(child: Icon(Icons.keyboard_arrow_left, color: Colors.black)),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  bottomNavigationBar: _isBottomBannerAdLoaded && _bottomBannerAd != null
                      ? SafeArea(
                          child: Container(
                            color: const Color(0xFFF1EEE4), // 배경색 변경
                            height: _bottomBannerAd!.size.height.toDouble(),
                            width: double.infinity,
                            alignment: Alignment.center,
                            child: AdWidget(ad: _bottomBannerAd!),
                          ),
                        )
                      : null,
                  );
              },
            ),
          );
      },
    );
  }

  Widget _buildLeftPanel({required bool isMobile}) {
    // Helper function for building sections
    Widget buildAlignedSection(String title, Widget content, {bool isScrollable = false, Widget? trailing}) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(title, trailing: trailing),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black12),
                color: Colors.white.withOpacity(0.3),
              ),
              child: isScrollable ? SingleChildScrollView(child: content) : content,
            ),
          ),
        ],
      );
    }

    final searchUI = Column(
      children: [
        Autocomplete<String>(
          textEditingController: _searchController,
          focusNode: _searchFocusNode,
          optionsBuilder: (textValue) {
            if (_suppressSearchHistoryAuto) {
              _suppressSearchHistoryAuto = false;
              return const Iterable<String>.empty();
            }
            return textValue.text == '' ? const Iterable<String>.empty() : _searchHistory.where((opt) => opt.toLowerCase().contains(textValue.text.toLowerCase()));
          },
          onSelected: (sel) => setState(() => _searchController.text = sel),
          fieldViewBuilder: (ctx, ctrl, focus, onSub) {
            return TextField(
              controller: ctrl,
              focusNode: focus,
              style: const TextStyle(fontFamily: 'Serif'),
              decoration: InputDecoration(
                hintText: 'Enter keywords...',
                filled: true,
                fillColor: Colors.white.withOpacity(0.5),
                border: const OutlineInputBorder(borderSide: BorderSide(color: Colors.black)),
                enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.black54)),
                prefixIcon: const Icon(Icons.search, color: Colors.black),
                suffixIcon: IconButton(icon: const Icon(Icons.history, color: Colors.black), onPressed: _showHistoryDialog),
              ),
              onSubmitted: (v) => onSub(),
            );
          },
        ),
      ],
    );

    final sourcesUI = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('SELECTED: ${_selectedSources.length} / $_totalPublishersCount', 
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            SizedBox(
              height: 32, // Match FilterChip height
              child: OutlinedButton(
                onPressed: () => _selectAll(true),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.black, 
                  side: const BorderSide(color: Colors.black, width: 0.5),
                  shape: const RoundedRectangleBorder(),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: const Text('SELECT ALL', style: TextStyle(fontSize: 9)),
              ),
            ),
            SizedBox(
              height: 32,
              child: OutlinedButton(
                onPressed: () => _selectAll(false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.black, 
                  side: const BorderSide(color: Colors.black, width: 0.5),
                  shape: const RoundedRectangleBorder(),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: const Text('CLEAR ALL', style: TextStyle(fontSize: 9)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text('BY CATEGORY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black54)),
        Wrap(
          spacing: 4,
          children: _availableCategories.map<Widget>((cat) {
            final isSelected = _isTypeSelected(cat);
            return FilterChip(
              selected: isSelected,
              label: Text(cat.toUpperCase(), style: TextStyle(fontSize: 9, color: isSelected ? Colors.white : Colors.black)),
              selectedColor: Colors.black,
              backgroundColor: Colors.transparent,
              side: const BorderSide(color: Colors.black, width: 0.5),
              shape: const RoundedRectangleBorder(),
              onSelected: (_) => _selectByCategory(cat),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        ..._newsSourcesMap.entries.map((entry) {
          final countryName = entry.key;
          final publishers = entry.value;
          final publisherIds = publishers.map((p) => p['id'] as String).toList();
          final allInCountrySelected = publisherIds.every((id) => _selectedSources.contains(id));

          // 국가별 플래그 이미지 및 코드 매핑
          String flagAsset = 'assets/images/usaflag.png';
          String countryCode = 'US';
          
          if (countryName.contains('Korea')) { flagAsset = 'assets/images/skoreaflag.png'; countryCode = 'KR'; }
          else if (countryName.contains('Germany')) { flagAsset = 'assets/images/germanyflag.png'; countryCode = 'DE'; }
          else if (countryName.contains('United Kingdom')) { flagAsset = 'assets/images/ukflag.png'; countryCode = 'GB'; }
          else if (countryName.contains('France')) { flagAsset = 'assets/images/franceflag.png'; countryCode = 'FR'; }
          else if (countryName.contains('Japan')) { flagAsset = 'assets/images/japanflag.png'; countryCode = 'JP'; }
          else if (countryName.contains('China')) { flagAsset = 'assets/images/chinaflag.png'; countryCode = 'CN'; }

          return Theme(
            data: Theme.of(context).copyWith(
              dividerColor: Colors.transparent,
              visualDensity: const VisualDensity(vertical: -4),
            ),
            child: ExpansionTile(
              title: Row(
                children: [
                  Container(
                    width: 22,
                    height: 14,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.black12, width: 0.5),
                    ),
                    child: Image.asset(flagAsset, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      countryName.toUpperCase(), 
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87, letterSpacing: 0.5),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              tilePadding: const EdgeInsets.symmetric(horizontal: 4),
              childrenPadding: EdgeInsets.zero,
              dense: true,
              shape: const Border(bottom: BorderSide(color: Colors.black12, width: 0.5)),
              collapsedShape: const Border(bottom: BorderSide(color: Colors.black12, width: 0.5)),
              children: [
                CheckboxListTile(
                  tileColor: Colors.black.withOpacity(0.03),
                  title: const Text('ALL PUBLISHERS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  value: allInCountrySelected,
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  visualDensity: const VisualDensity(vertical: -4),
                  onChanged: (v) => setState(() {
                    if (v == true) _selectedSources.addAll(publisherIds);
                    else { for (var id in publisherIds) _selectedSources.remove(id); }
                  }),
                ),
                ...publishers.map((publisher) {
                  final id = publisher['id'] as String;
                  return CheckboxListTile(
                    title: Text(publisher['nameLocal'] ?? publisher['name'], style: const TextStyle(fontSize: 13)),
                    subtitle: Text(publisher['type']?.toString().toUpperCase() ?? '', style: const TextStyle(fontSize: 9)),
                    value: _selectedSources.contains(id),
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    visualDensity: const VisualDensity(vertical: -4),
                    onChanged: (v) => setState(() { if (v == true) _selectedSources.add(id); else _selectedSources.remove(id); }),
                  );
                }).toList(),
              ],
            ),
          );
        }).toList(),
      ],
    );

    final periodUI = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          value: _selectedPeriod,
          decoration: const InputDecoration(border: OutlineInputBorder(borderSide: BorderSide(color: Colors.black))),
          items: _periods.map((p) => DropdownMenuItem(value: p, child: Text(p.toUpperCase(), style: const TextStyle(fontSize: 13)))).toList(),
          onChanged: (val) => setState(() { _selectedPeriod = val!; if (_selectedPeriod != 'Dynamic') _selectedDateRange = null; }),
        ),
        if (_selectedPeriod == 'Dynamic') ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _showCustomDateRangePicker,
            icon: const Icon(Icons.calendar_today, size: 16, color: Colors.black),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.black, side: const BorderSide(color: Colors.black)),
            label: Text(_selectedDateRange == null ? 'SELECT RANGE' : '${_selectedDateRange!.start.toString().split(' ')[0]} ~ ${_selectedDateRange!.end.toString().split(' ')[0]}'),
          ),
        ],
      ],
    );

    return Container(
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: Colors.black, width: 0.5)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(
              'SEARCH QUERY',
              trailing: IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.info_outline, size: 18, color: Colors.black45),
                onPressed: _showSearchQueryGuide,
                tooltip: 'Search Query Guide',
              ),
            ),
            const SizedBox(height: 12),
            searchUI,
            const SizedBox(height: 24),
            _buildSectionHeader('NEWS SOURCES'),
            const SizedBox(height: 8),
            sourcesUI,
            const SizedBox(height: 24),
            _buildSectionHeader('TIME PERIOD'),
            const SizedBox(height: 12),
            periodUI,
            const SizedBox(height: 32),
            // Action Buttons
            Column(
              children: [
                const Text(
                  'Results will be shown after a brief advertisement.',
                  style: TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _buildActionButton(label: 'RUN SIMPLE SEARCH', icon: Icons.bolt, color: const Color(0xFF722F37), isOutline: false, onPressed: () => _runCrawler(periodic: false, isDetail: false))),
                    const SizedBox(width: 8),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.info_outline, size: 18, color: Colors.black45),
                      onPressed: () => _showSearchInfoDialog(false),
                      tooltip: 'Learn about Simple Search',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _buildActionButton(label: 'RUN DETAIL SEARCH', icon: Icons.travel_explore, iconColor: Colors.amber, color: const Color(0xFF1B3A4B), isOutline: false, onPressed: () => _runCrawler(periodic: false, isDetail: true))),
                    const SizedBox(width: 8),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.info_outline, size: 18, color: Colors.black45),
                      onPressed: () => _showSearchInfoDialog(true),
                      tooltip: 'Learn about Detail Search',
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, {Widget? trailing}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          height: 38, // Fixed height to align with headers containing icons
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            image: const DecorationImage(
              image: AssetImage('assets/images/header_texture2.png'),
              fit: BoxFit.cover,
              opacity: 0.3,
            ),
            border: const Border(left: BorderSide(color: Colors.black, width: 3)),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title, 
                style: const TextStyle(fontFamily: 'Serif', fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 1.5)
              ),
              if (trailing != null) ...[
                trailing,
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({required String label, required IconData icon, Color? iconColor, required Color color, required bool isOutline, required VoidCallback onPressed}) {
    return SizedBox(
      height: 38, // 버튼 높이를 줄여서 더 촘촘하게 배치
      width: double.infinity,
      child: isOutline 
        ? OutlinedButton.icon(
            onPressed: onPressed, 
            icon: Icon(icon, size: 16, color: iconColor), 
            label: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            style: OutlinedButton.styleFrom(
              foregroundColor: color, 
              side: BorderSide(color: color, width: 1), 
              padding: EdgeInsets.zero,
              shape: const RoundedRectangleBorder(), // 각진 모서리
            ),
          )
        : ElevatedButton.icon(
            onPressed: onPressed, 
            icon: Icon(icon, size: 16, color: iconColor ?? Colors.white),
            label: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: color, 
              padding: EdgeInsets.zero, 
              shape: const RoundedRectangleBorder(), // 각진 모서리
              elevation: 0,
            ),
          ),
    );
  }

  Widget _buildRightPanel({required bool isMobile}) {
    return Container(
      color: const Color(0xFFF1EEE4), // 배경색 변경
      child: Column(
        children: [
          // Results Header
          Padding(
            padding: EdgeInsets.all(isMobile ? 8.0 : 16.0),
            child: Row(
              children: [
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'LATEST REPORTS${_results.isNotEmpty ? ": ${_results.length}" : ""}', 
                        style: const TextStyle(fontFamily: 'Serif', fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: -0.5)
                      ),
                    ],
                  )
                ),
                if (!isMobile)
                  IconButton(onPressed: () => setState(() => _isResultVisible = false), icon: const Icon(Icons.close, color: Colors.black)),
              ],
            ),
          ),

          // --- Controls Bar (Sort, Language, Translate) ---
          if (_results.isNotEmpty || _isLoading)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.05),
                border: const Border(
                  top: BorderSide(color: Colors.black, width: 1),
                  bottom: BorderSide(color: Colors.black, width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  // Sort Dropdown
                  Expanded(
                    flex: 3,
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _sortBy,
                        isDense: true,
                        icon: const Icon(Icons.sort, size: 14, color: Colors.black),
                        style: GoogleFonts.libreBaskerville(fontSize: 10, color: Colors.black, fontWeight: FontWeight.bold),
                        items: _sortOptions.map((opt) => DropdownMenuItem(
                          value: opt, 
                          child: Text('SORT: ${opt.toUpperCase()}')
                        )).toList(),
                        onChanged: _isLoading ? null : (val) {
                          setState(() { _sortBy = val!; });
                          _sortResults();
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Language Dropdown
                  Expanded(
                    flex: 3,
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _targetLanguage,
                        isDense: true,
                        icon: const Icon(Icons.language, size: 14, color: Colors.black),
                        style: GoogleFonts.libreBaskerville(fontSize: 10, color: Colors.black, fontWeight: FontWeight.bold),
                        items: const [
                          DropdownMenuItem(value: 'original', child: Text('LANG: ORIGINAL')),
                          DropdownMenuItem(value: 'ko', child: Text('LANG: KOREAN')),
                          DropdownMenuItem(value: 'en', child: Text('LANG: ENGLISH')),
                          DropdownMenuItem(value: 'de', child: Text('LANG: GERMAN')),
                          DropdownMenuItem(value: 'fr', child: Text('LANG: FRENCH')),
                          DropdownMenuItem(value: 'ja', child: Text('LANG: JAPANESE')),
                          DropdownMenuItem(value: 'zh-cn', child: Text('LANG: CHINESE')),
                        ],
                        onChanged: _isLoading || _isTranslating ? null : (val) => setState(() => _targetLanguage = val!),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Translate Button
                  SizedBox(
                    height: 28,
                    child: ElevatedButton(
                      onPressed: _isLoading || _isTranslating || _results.isEmpty ? null : _runTranslation,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        shape: const RoundedRectangleBorder(),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        elevation: 0,
                      ),
                      child: Text(_isTranslating ? 'STOP' : 'TRANSLATE', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          
          if (!_results.isNotEmpty && !_isLoading)
            const Divider(color: Colors.black, thickness: 1),
          
          // Result List
          Expanded(
            child: _results.isEmpty && !_isLoading && !_isAIAnalyzing
                ? const Center(child: Text('NO REPORTS FILED.', style: TextStyle(fontFamily: 'Serif', fontStyle: FontStyle.italic)))
                : SelectionArea(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: _results.length + (_results.isNotEmpty ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (_results.isNotEmpty && index == 0) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 24),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.black, width: 2),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                InkWell(
                                  onTap: () => setState(() => _isAIExpanded = !_isAIExpanded),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    decoration: const BoxDecoration(
                                      image: DecorationImage(
                                        image: AssetImage('assets/images/header_texture2.png'),
                                        fit: BoxFit.cover,
                                        opacity: 0.3,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Row 1: AI Insight (Model Name) + Expand/Collapse Icon
                                        Row(
                                          children: [
                                            const Icon(Icons.auto_awesome, color: Colors.black, size: 14),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                'AI INSIGHT ($_selectedAIModel)', 
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black),
                                              ),
                                            ),
                                            Icon(_isAIExpanded ? Icons.expand_less : Icons.expand_more, color: Colors.black, size: 18),
                                          ],
                                        ),
                                        
                                        // Row 2: Action Buttons (Shown when expanded)
                                        if (_isAIExpanded) ...[
                                          const SizedBox(height: 10),
                                          _isAIAnalyzing
                                            ? InkWell(
                                                onTap: () {
                                                  setState(() => _isCancelled = true);
                                                  _showSnackBar('AI 분석 중단 중...');
                                                },
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    border: Border.all(color: Colors.black.withOpacity(0.2)),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: const Text('STOP', style: TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.bold)),
                                                ),
                                              )
                                            : FittedBox(
                                                fit: BoxFit.scaleDown,
                                                alignment: Alignment.centerLeft,
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    // 1. Re-Analysis / Start Analysis
                                                    PopupMenuButton<Map<String, String>>(
                                                      tooltip: '모델 변경 및 분석 시작',
                                                      onSelected: (val) {
                                                        _triggerAIAnalysis(newProvider: val['provider'], newModel: val['model']);
                                                      },
                                                      itemBuilder: (context) {
                                                        List<PopupMenuEntry<Map<String, String>>> items = [];
                                                        items.add(
                                                          PopupMenuItem(
                                                            value: {'provider': _selectedAIProvider, 'model': _selectedAIModel},
                                                            child: SizedBox(
                                                              width: 200,
                                                              child: Row(
                                                                children: [
                                                                  const Icon(Icons.play_arrow, size: 16, color: Colors.black54),
                                                                  const SizedBox(width: 8),
                                                                  Expanded(
                                                                    child: Text(
                                                                      '현재 모델: $_selectedAIModel', 
                                                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), 
                                                                      overflow: TextOverflow.ellipsis
                                                                    )
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          ),
                                                        );
                                                        items.add(const PopupMenuDivider());
                                                        
                                                        _aiModelOptions.forEach((provider, models) {
                                                          items.add(
                                                            PopupMenuItem(
                                                              enabled: false,
                                                              child: Text(provider, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                                                            )
                                                          );
                                                          for (var m in models) {
                                                            items.add(
                                                              PopupMenuItem(
                                                                value: {'provider': provider, 'model': m},
                                                                height: 32,
                                                                child: Container(
                                                                  width: 200,
                                                                  padding: const EdgeInsets.only(left: 8.0),
                                                                  child: Text(m, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                                                                ),
                                                              )
                                                            );
                                                          }
                                                        });
                                                        return items;
                                                      },
                                                      child: Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                        decoration: BoxDecoration(
                                                          color: const Color(0xFF1E3A8A),
                                                          border: Border.all(color: Colors.blue[300]!),
                                                          borderRadius: BorderRadius.circular(4),
                                                        ),
                                                        child: Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            Icon(_aiInsight == null ? Icons.play_arrow : Icons.refresh, size: 12, color: Colors.white),
                                                            const SizedBox(width: 4),
                                                            Text(
                                                              _aiInsight == null ? 'START ANALYSIS' : 'RE-ANALYSIS', 
                                                              style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    
                                                    // 2. Edit Prompt
                                                    if (_aiInsight != null) ...[
                                                      InkWell(
                                                        onTap: () => setState(() { _aiInsight = null; _isAIExpanded = true; }),
                                                        child: Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                          decoration: BoxDecoration(
                                                            border: Border.all(color: Colors.black.withOpacity(0.2)),
                                                            borderRadius: BorderRadius.circular(4),
                                                          ),
                                                          child: const Row(
                                                            mainAxisSize: MainAxisSize.min,
                                                            children: [
                                                              Icon(Icons.edit_note, size: 14, color: Colors.black),
                                                              SizedBox(width: 4),
                                                              Text('EDIT PROMPT', style: TextStyle(fontSize: 9, color: Colors.black, fontWeight: FontWeight.bold)),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                    ],
                                                    
                                                    // 3. AI Setting
                                                    InkWell(
                                                      onTap: _showAiSettingDialog,
                                                      child: Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                        decoration: BoxDecoration(
                                                          border: Border.all(color: Colors.black.withOpacity(0.2)),
                                                          borderRadius: BorderRadius.circular(4),
                                                        ),
                                                        child: const Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            Icon(Icons.settings, size: 12, color: Colors.black),
                                                            SizedBox(width: 4),
                                                            Text('AI SETTING', style: TextStyle(fontSize: 9, color: Colors.black, fontWeight: FontWeight.bold)),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                                if (_isAIExpanded)
                                  Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: _isAIAnalyzing
                                        ? Row(
                                            children: [
                                              const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black54)),
                                              const SizedBox(width: 12),
                                              Expanded(child: Text(_aiProgressMsg, style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.black54, fontSize: 13))),
                                            ],
                                          )
                                        : Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              if (_aiInsight == null) ...[
                                                Autocomplete<String>(
                                                  textEditingController: _aiPromptController,
                                                  focusNode: _aiPromptFocusNode,
                                                  optionsBuilder: (textValue) {
                                                    if (_suppressAiHistoryAuto) {
                                                      _suppressAiHistoryAuto = false;
                                                      return const Iterable<String>.empty();
                                                    }
                                                    return textValue.text == '' ? const Iterable<String>.empty() : _aiHistory.where((opt) => opt.toLowerCase().contains(textValue.text.toLowerCase()));
                                                  },
                                                  onSelected: (sel) => setState(() => _aiPromptController.text = sel),
                                                  fieldViewBuilder: (ctx, ctrl, focus, onSub) {
                                                    return TextField(
                                                      controller: ctrl,
                                                      focusNode: focus,
                                                      maxLines: 2,
                                                      style: const TextStyle(fontFamily: 'Serif', fontSize: 13),
                                                      decoration: InputDecoration(
                                                        hintText: 'Describe what you want the AI to analyze...',
                                                        border: const OutlineInputBorder(borderSide: BorderSide(color: Colors.black)),
                                                        suffixIcon: IconButton(icon: const Icon(Icons.history, color: Colors.black), onPressed: _showAiHistoryDialog),
                                                      ),
                                                    );
                                                  },
                                                ),
                                                const SizedBox(height: 8),
                                                const Text('Enter your prompt above and click START ANALYSIS in the header.', style: TextStyle(fontSize: 10, color: Colors.black38, fontStyle: FontStyle.italic)),
                                              ] else ...[
                                                Text(_aiInsight!, style: const TextStyle(fontFamily: 'Serif', fontSize: 15, height: 1.6)),
                                                if (_aiReferencedArticles.isNotEmpty) ...[
                                                  const Padding(
                                                    padding: EdgeInsets.symmetric(vertical: 12.0),
                                                    child: Divider(color: Colors.black26),
                                                  ),
                                                  const Text('PRIMARY SOURCES:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1, color: Colors.black54)),
                                                  const SizedBox(height: 8),
                                                  ..._aiReferencedArticles.map((article) => Padding(
                                                    padding: const EdgeInsets.only(bottom: 6.0),
                                                    child: InkWell(
                                                      mouseCursor: SystemMouseCursors.click,
                                                      onTap: () {
                                                        setState(() => _visitedUrls.add(article.url));
                                                        launchUrl(Uri.parse(article.url), mode: LaunchMode.externalApplication);
                                                      },
                                                      child: Row(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          const Text('• ', style: TextStyle(fontSize: 12)),
                                                          Expanded(
                                                            child: Text(
                                                              '${article.title} (${article.source})',
                                                              style: TextStyle(
                                                                fontSize: 12,
                                                                color: _visitedUrls.contains(article.url) ? const Color(0xFF551A8B) : const Color(0xFF0000EE),
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  )).toList(),
                                                ],
                                              ],
                                            ],
                                          ),
                                  ),
                              ],
                            ),
                          );
                        }
                        
                        final articleIndex = (_results.isNotEmpty) ? index - 1 : index;
                        final article = _results[articleIndex];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: const BoxDecoration(
                            border: Border(bottom: BorderSide(color: Colors.black26)),
                          ),
                          child: InkWell(
                            mouseCursor: SystemMouseCursors.click,
                            onTap: () {
                              setState(() {
                                _visitedUrls.add(article.url);
                              });
                              launchUrl(Uri.parse(article.url), mode: LaunchMode.externalApplication);
                            },
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    article.title, 
                                    style: TextStyle(
                                      fontFamily: 'Serif', 
                                      fontWeight: FontWeight.bold, 
                                      fontSize: 17, 
                                      height: 1.2, 
                                      color: _visitedUrls.contains(article.url) 
                                          ? const Color(0xFF551A8B) // Visited link color (Purple)
                                          : const Color(0xFF0000EE), // Clickable link color (Blue)
                                    )
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${article.countryName.toUpperCase()} | ${article.source.toUpperCase()}',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(article.pubDate ?? "", style: const TextStyle(fontSize: 10, color: Colors.black54)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),

          // Progress Bar
          if (_isLoading)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.black,
              child: Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: _progress, 
                      backgroundColor: Colors.white24, 
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.white)
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () { setState(() => _isCancelled = true); _showSnackBar('HALTING...'); },
                    child: const Text('STOP', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ],
              ),
            ),

          // Log Panel
          _buildLogPanel(isMobile: isMobile),
        ],
      ),
    );
  }

  Widget _buildLogPanel({required bool isMobile}) {
    final double displayHeight = _isLogVisible 
        ? (isMobile ? 150.0 : _logPanelHeight) 
        : 40.0;
        
    return Container(
      height: displayHeight,
      decoration: const BoxDecoration(
        color: Color(0xFF2D2D2A), // 부드러운 숯색 (신문 잉크색 느낌의 다크 그레이)
        border: Border(top: BorderSide(color: Colors.black, width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Draggable Top Border
          if (_isLogVisible && !isMobile)
            GestureDetector(
              onVerticalDragUpdate: (details) {
                setState(() {
                  _logPanelHeight -= details.delta.dy;
                  if (_logPanelHeight < 100) _logPanelHeight = 100;
                  if (_logPanelHeight > 600) _logPanelHeight = 600;
                });
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeUpDown,
                child: Container(
                  color: Colors.white10,
                  height: 3,
                  width: double.infinity,
                ),
              ),
            ),
          InkWell(
            onTap: () => setState(() => _isLogVisible = !_isLogVisible),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: Colors.black.withOpacity(0.2), // 헤더 영역 살짝 구분
              child: Row(
                children: [
                  const Icon(Icons.analytics_outlined, size: 14, color: Color(0xFFBCBCA9)),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'SYSTEM EXECUTION LOGS', 
                      style: TextStyle(
                        fontSize: 10, 
                        fontWeight: FontWeight.bold, 
                        color: Color(0xFFBCBCA9), // 종이색과 어울리는 저채도 색상
                        letterSpacing: 1.2
                      ),
                      overflow: TextOverflow.ellipsis,
                    )
                  ),
                  if (_isLogVisible)
                    IconButton(
                      constraints: const BoxConstraints(maxHeight: 24, maxWidth: 24),
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.copy_all, size: 14, color: Color(0xFFBCBCA9)),
                      tooltip: 'Copy all logs',
                      onPressed: () {
                        final allLogs = _logs.map((l) => l.message).join('\n');
                        Clipboard.setData(ClipboardData(text: allLogs));
                        _showSnackBar('LOGS COPIED.');
                      },
                    ),
                  Icon(
                    _isLogVisible ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up, 
                    size: 16, 
                    color: const Color(0xFFBCBCA9)
                  ),
                ],
              ),
            ),
          ),
          // Log Content
          if (_isLogVisible)
            Expanded(
              child: SelectionArea(
                child: Stack(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          if (notification is UserScrollNotification) {
                            if (notification.direction != ScrollDirection.idle) {
                              // User is manually scrolling
                              if (_isLogAutoScrollEnabled) {
                                setState(() => _isLogAutoScrollEnabled = false);
                              }
                            }
                          }
                          // If user manually scrolls to the very bottom, re-enable auto-scroll
                          if (notification.metrics.pixels >= notification.metrics.maxScrollExtent - 5) {
                            if (!_isLogAutoScrollEnabled) {
                              setState(() => _isLogAutoScrollEnabled = true);
                            }
                          }
                          return false;
                        },
                        child: ListView.builder(
                          controller: _logScrollController,
                          padding: const EdgeInsets.only(bottom: 60), // 하단에 60px 여백 추가
                          itemCount: _logs.length,
                          itemBuilder: (context, index) {
                            final log = _logs[index];
                            // 로그 색상이 너무 어두워지지 않도록 조정
                            Color displayColor = log.color ?? const Color(0xFFD1D1C7);
                            if (displayColor == Colors.blue[900]) displayColor = const Color(0xFF8BA4FF); 
                            
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(
                                log.message,
                                style: TextStyle(
                                  fontSize: log.isSummary ? 12 : 9,
                                  fontFamily: 'monospace',
                                  color: displayColor,
                                  height: 1.3,
                                  fontWeight: (log.isHeader || log.isSummary) ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    if (!_isLogAutoScrollEnabled)
                      Positioned(
                        bottom: 12,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Opacity(
                            opacity: 0.7,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                setState(() => _isLogAutoScrollEnabled = true);
                                _logScrollController.animateTo(
                                  _logScrollController.position.maxScrollExtent,
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeOut,
                                );
                              },
                              icon: const Icon(Icons.arrow_downward, size: 14),
                              label: const Text('SCROLL TO BOTTOM', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                elevation: 4,
                              ),
                            ),
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
