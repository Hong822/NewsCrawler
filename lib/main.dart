import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_fonts/google_fonts.dart';
import 'firebase_options.dart';
import 'news_crawler_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  ); // Firebase 초기화
  runApp(const NewsCrawlerApp());
}

class NewsCrawlerApp extends StatelessWidget {
  const NewsCrawlerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'News Crawler',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF202020),
          surface: const Color(0xFFF4F1EA), // 종이 질감 색상
        ),
        // 뉴욕 타임즈 느낌을 위한 폰트 설정
        textTheme: TextTheme(
          displayLarge: GoogleFonts.playfairDisplay(fontWeight: FontWeight.w900, color: Colors.black),
          titleLarge: GoogleFonts.playfairDisplay(fontWeight: FontWeight.bold, color: Colors.black),
          titleMedium: GoogleFonts.libreBaskerville(fontWeight: FontWeight.bold, color: Colors.black),
          bodyLarge: GoogleFonts.libreBaskerville(color: const Color(0xFF1A1A1A)),
          bodyMedium: GoogleFonts.libreBaskerville(color: const Color(0xFF2C2C2C), height: 1.3),
          labelSmall: GoogleFonts.libreBaskerville(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black54),
        ),
        dividerTheme: const DividerThemeData(
          color: Colors.black,
          thickness: 0.5,
          space: 1,
        ),
        checkboxTheme: CheckboxThemeData(
          fillColor: MaterialStateProperty.resolveWith((states) => states.contains(MaterialState.selected) ? Colors.black : null),
          side: const BorderSide(color: Colors.black, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(0)), // 신문처럼 각진 체크박스
        ),
        // 달력(DatePicker) 테마 추가
        datePickerTheme: DatePickerThemeData(
          backgroundColor: const Color(0xFFF4F1EA),
          headerBackgroundColor: Colors.black,
          headerForegroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          dayStyle: GoogleFonts.libreBaskerville(),
          yearStyle: GoogleFonts.libreBaskerville(),
          shape: const RoundedRectangleBorder(),
          dividerColor: Colors.black,
        ),
      ),
      home: const NewsCrawlerHomePage(),
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

class NewsCrawlerHomePage extends StatefulWidget {
  const NewsCrawlerHomePage({super.key});

  @override
  State<NewsCrawlerHomePage> createState() => _NewsCrawlerHomePageState();
}

class _NewsCrawlerHomePageState extends State<NewsCrawlerHomePage> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _aiPromptController = TextEditingController();
  final NewsCrawlerService _crawlerService = NewsCrawlerService();
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
  double _logPanelHeight = 250.0;
  List<LogEntry> _logs = [];
  double _progress = 0.0;
  bool _isCancelled = false;
  bool _isTranslating = false;
  bool _suppressSearchHistoryAuto = false;
  bool _suppressAiHistoryAuto = false;
  bool _suppressEmailHistoryAuto = false;
  String _targetLanguage = 'ko'; // Default to Korean
  bool _showMobileResults = false; // Mobile navigation state
  String? _aiInsight;
  bool _isAIAnalyzing = false;
  bool _isAIExpanded = true;
  String _aiProgressMsg = "";
  List<NewsArticle> _aiReferencedArticles = [];
  final Set<String> _visitedUrls = {};

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
        title: const Text('Search History'),
        content: SizedBox(
          width: double.maxFinite,
          child: _searchHistory.isEmpty
              ? const Text('No history yet.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: _searchHistory.length,
                  itemBuilder: (context, index) {
                    final item = _searchHistory[index];
                    return ListTile(
                      title: Text(item),
                      onTap: () {
                        setState(() {
                          _suppressSearchHistoryAuto = true;
                          _searchController.text = item;
                        });
                        Navigator.pop(context);
                      },
                      trailing: IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () { _deleteHistoryItem(item); Navigator.pop(context); _showHistoryDialog(); },
                      ),
                    );
                  },
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  void _showAiHistoryDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('AI Prompt History'),
        content: SizedBox(
          width: double.maxFinite,
          child: _aiHistory.isEmpty
              ? const Text('No history yet.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: _aiHistory.length,
                  itemBuilder: (context, index) {
                    final item = _aiHistory[index];
                    return ListTile(
                      title: Text(item, maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: () {
                        setState(() {
                          _suppressAiHistoryAuto = true;
                          _aiPromptController.text = item;
                        });
                        Navigator.pop(context);
                      },
                      trailing: IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () { _deleteAiHistoryItem(item); Navigator.pop(context); _showAiHistoryDialog(); },
                      ),
                    );
                  },
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  void _showEmailHistoryDialog(TextEditingController ctrl, Function(String) onSelected) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Email History'),
        content: SizedBox(
          width: double.maxFinite,
          child: _emailHistory.isEmpty
              ? const Text('No history yet.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: _emailHistory.length,
                  itemBuilder: (context, index) {
                    final item = _emailHistory[index];
                    return ListTile(
                      title: Text(item),
                      onTap: () {
                        setState(() {
                          _suppressEmailHistoryAuto = true;
                        });
                        ctrl.text = item;
                        Navigator.pop(context);
                        onSelected(item);
                      },
                      trailing: IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () { _deleteEmailHistoryItem(item); Navigator.pop(context); _showEmailHistoryDialog(ctrl, onSelected); },
                      ),
                    );
                  },
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  void _showEmailDialog() {
    if (_results.isEmpty) {
      _showSnackBar('검색 결과가 없습니다.');
      return;
    }

    final dialogEmailController = TextEditingController(text: _emailController.text);

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
                    if (ctrl.text != dialogEmailController.text) {
                      Future.microtask(() => ctrl.text = dialogEmailController.text);
                    }
                    ctrl.addListener(() {
                      if (dialogEmailController.text != ctrl.text) {
                        dialogEmailController.text = ctrl.text;
                      }
                    });
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
    );
  }

  @override
  void initState() {
    super.initState();
    _loadNewsSources();
    _loadAllAiKeys();
    _loadSearchHistory();
    _loadEmailHistory();
    _loadAiHistory();
  }

  Future<void> _loadAllAiKeys() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _aiApiKeys['ChatGPT'] = prefs.getString('key_chatgpt') ?? '';
      _aiApiKeys['Gemini'] = prefs.getString('key_gemini') ?? '';
      _aiApiKeys['Claude'] = prefs.getString('key_claude') ?? '';
    });
    
    // Fallback for Gemini if asset key exists and no saved key
    if (_aiApiKeys['Gemini']!.isEmpty) {
      await _loadGeminiKeyFromAsset();
    } else {
      // _updateGeminiModels(); // Dynamic model update disabled, using static list
    }
  }

  Future<void> _loadGeminiKeyFromAsset() async {
    try {
      final String key = await rootBundle.loadString('assets/api_key.txt');
      setState(() { 
        _aiApiKeys['Gemini'] = key.trim();
        _apiKeyController.text = key.trim();
      });
      // _updateGeminiModels(); // Dynamic model update disabled, using static list
    } catch (e) { debugPrint('No asset API key found.'); }
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
            title: const Text('AI SETTINGS', style: TextStyle(fontFamily: 'Serif', fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('AI PROVIDER', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black54)),
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
                  const Text('AI MODEL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black54)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    value: tempModel,
                    decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12)),
                    items: _aiModelOptions[tempProvider]!.map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontSize: 12)))).toList(),
                    onChanged: (val) => setDialogState(() => tempModel = val!),
                  ),
                  const SizedBox(height: 16),
                  const Text('API KEY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black54)),
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
                  _showSnackBar('$tempProvider SETTINGS UPDATED.');
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white),
                child: const Text('SAVE SETTINGS'),
              ),
            ],
          );
        }
      ),
    );
  }

  Future<void> _loadNewsSources() async {
    try {
      final String response = await rootBundle.loadString('assets/news_sources.json');
      final data = json.decode(response);
      final Map<String, List<Map<String, dynamic>>> tempMap = {};
      int totalCount = 0;
      final Set<String> categories = {};

      for (var country in data['countries']) {
        final countryName = country['countryName'] as String;
        final publishers = (country['publishers'] as List).map((e) => e as Map<String, dynamic>).toList();
        tempMap[countryName] = publishers;
        totalCount += publishers.length;
        for (var pub in publishers) {
          if (pub['type'] != null) categories.add(pub['type'] as String);
        }
      }

      // Sort categories: General, Business, Technology, Automotive, Wire
      const typeOrder = ['general', 'business', 'technology', 'automotive', 'wire'];
      final sortedCategories = typeOrder.where((type) => categories.contains(type)).toList();
      sortedCategories.addAll(categories.where((cat) => !typeOrder.contains(cat)).toList()..sort());

      setState(() {
        _newsSourcesMap = tempMap;
        _totalPublishersCount = totalCount;
        _availableCategories = sortedCategories;
        _isSourceLoading = false;
      });
    } catch (e) {
      setState(() => _isSourceLoading = false);
      _showSnackBar('Failed to load news sources: $e');
    }
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
    
    // Auto scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _runCrawler({required bool periodic}) async {
    final query = _searchController.text;
    final sources = _selectedSources.toList();
    final period = _selectedPeriod;

    if (query.isEmpty) { _showSnackBar('Please enter a search query'); return; }
    if (sources.isEmpty) { _showSnackBar('Please select at least one news source'); return; }
    if (period == 'Dynamic' && _selectedDateRange == null) { _showSnackBar('Please select a date range'); return; }

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
        sources: sources,
        period: period == 'Dynamic' 
            ? '${_selectedDateRange!.start.toString().split(' ')[0]} to ${_selectedDateRange!.end.toString().split(' ')[0]}' 
            : period,
        apiKey: _apiKeyController.text,
        onLog: (msg, {isMatch, isError, isHeader, isSummary}) => 
            _addLog(msg, isMatch: isMatch, isError: isError, isHeader: isHeader, isSummary: isSummary),
        onProgress: (p) => setState(() => _progress = p),
        isCancelled: () => _isCancelled,
      );

      setState(() {
        _results = articles;
        _isLoading = false;
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
        final bool isMobile = constraints.maxWidth < 600;

        // 신문 제호 스타일의 AppBar
        final appBar = AppBar(
          centerTitle: true,
          toolbarHeight: 110, // 높이를 조절하여 여유 공간 확보
          title: Column(
            children: [
              const SizedBox(height: 10),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'The News Crawler',
                  style: GoogleFonts.unifrakturMaguntia(
                    fontSize: isMobile ? 32 : 42,
                    color: Colors.black,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              Container(
                height: 1.2,
                width: isMobile ? 220 : 320,
                color: Colors.black,
                margin: const EdgeInsets.only(top: 4, bottom: 6),
              ),
              Text(
                DateTime.now().toString().split(' ')[0].toUpperCase(),
                style: GoogleFonts.libreBaskerville(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
          backgroundColor: const Color(0xFFF4F1EA),
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
            backgroundColor: const Color(0xFFF4F1EA),
            body: SafeArea(
              child: _showMobileResults ? _buildRightPanel(isMobile: true) : _buildLeftPanel(isMobile: true),
            ),
          );
        }

        return Scaffold(
          appBar: appBar,
          backgroundColor: const Color(0xFFF4F1EA),
          body: SafeArea(
            child: Row(
              children: [
                SizedBox(
                  width: _isResultVisible ? constraints.maxWidth * _splitRatio : constraints.maxWidth - 40,
                  height: constraints.maxHeight,
                  child: _buildLeftPanel(isMobile: false),
                ),
                if (_isResultVisible)
                  GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragUpdate: (details) {
                      setState(() {
                        _splitRatio += details.delta.dx / constraints.maxWidth;
                        if (_splitRatio < 0.2) _splitRatio = 0.2;
                        if (_splitRatio > 0.8) _splitRatio = 0.8;
                      });
                    },
                    child: Container(
                      width: 4,
                      color: Colors.black,
                      child: const Center(child: Icon(Icons.more_vert, size: 16, color: Colors.white)),
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
        );
      },
    );
  }

  Widget _buildLeftPanel({required bool isMobile}) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: Colors.black, width: 0.5)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('SEARCH QUERY', style: TextStyle(fontFamily: 'Serif', fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
            const Divider(height: 20, thickness: 1),
            Autocomplete<String>(
              optionsBuilder: (textValue) {
                if (_suppressSearchHistoryAuto) {
                  _suppressSearchHistoryAuto = false;
                  return const Iterable<String>.empty();
                }
                return textValue.text == '' ? const Iterable<String>.empty() : _searchHistory.where((opt) => opt.toLowerCase().contains(textValue.text.toLowerCase()));
              },
              onSelected: (sel) => setState(() => _searchController.text = sel),
              fieldViewBuilder: (ctx, ctrl, focus, onSub) {
                if (ctrl.text != _searchController.text) {
                  Future.microtask(() => ctrl.text = _searchController.text);
                }
                ctrl.addListener(() {
                  if (_searchController.text != ctrl.text) {
                    _searchController.text = ctrl.text;
                  }
                });
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
            const SizedBox(height: 24),
            const Text('NEWS SOURCES', style: TextStyle(fontFamily: 'Serif', fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
            const Divider(height: 10),
            Text('SELECTED: ${_selectedSources.length} / $_totalPublishersCount', 
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => _selectAll(true),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.black, side: const BorderSide(color: Colors.black)),
                  child: const Text('SELECT ALL', style: TextStyle(fontSize: 10)),
                ),
                OutlinedButton(
                  onPressed: () => _selectAll(false),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.black, side: const BorderSide(color: Colors.black)),
                  child: const Text('CLEAR ALL', style: TextStyle(fontSize: 10)),
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

              return Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  title: Text(countryName.toUpperCase(), style: Theme.of(context).textTheme.titleSmall?.copyWith(letterSpacing: 1, fontWeight: FontWeight.bold)),
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  shape: const Border(bottom: BorderSide(color: Colors.black26, width: 0.5)),
                  collapsedShape: const Border(bottom: BorderSide(color: Colors.black26, width: 0.5)),
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
                        visualDensity: const VisualDensity(vertical: -4), // 간격을 좁힘
                        onChanged: (v) => setState(() { if (v == true) _selectedSources.add(id); else _selectedSources.remove(id); }),
                      );
                    }).toList(),
                  ],
                ),
              );
            }).toList(),
            const SizedBox(height: 24),
            const Text('TIME PERIOD', style: TextStyle(fontFamily: 'Serif', fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
            const Divider(height: 20),
            DropdownButtonFormField<String>(
              value: _selectedPeriod,
              decoration: const InputDecoration(border: OutlineInputBorder(borderSide: BorderSide(color: Colors.black))),
              items: _periods.map((p) => DropdownMenuItem(value: p, child: Text(p.toUpperCase(), style: const TextStyle(fontSize: 13)))).toList(),
              onChanged: (val) => setState(() { _selectedPeriod = val!; if (_selectedPeriod != 'Dynamic') _selectedDateRange = null; }),
            ),
            if (_selectedPeriod == 'Dynamic') ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                final picked = await showDateRangePicker(
                  context: context, 
                  firstDate: DateTime(2000), 
                  lastDate: DateTime.now(), 
                  initialDateRange: _selectedDateRange,
                  builder: (context, child) {
                    return Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: const ColorScheme.light(
                          primary: Colors.black, // 선택된 날짜 색상
                          onPrimary: Colors.white,
                          onSurface: Colors.black,
                          surface: Color(0xFFF4F1EA),
                        ),
                        textTheme: Theme.of(context).textTheme.copyWith(
                          labelLarge: GoogleFonts.libreBaskerville(fontSize: 14),
                        ),
                      ),
                      child: child!,
                    );
                  },
                );
                if (picked != null) setState(() => _selectedDateRange = picked);
              },
                icon: const Icon(Icons.calendar_today, size: 16, color: Colors.black),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.black, side: const BorderSide(color: Colors.black)),
                label: Text(_selectedDateRange == null ? 'SELECT RANGE' : '${_selectedDateRange!.start.toString().split(' ')[0]} ~ ${_selectedDateRange!.end.toString().split(' ')[0]}'),
              ),
            ],
            const SizedBox(height: 32),
            // Action Buttons
            Column(
              children: [
                _buildActionButton(label: 'RUN SEARCH', icon: Icons.play_arrow, color: const Color(0xFF722F37), isOutline: false, onPressed: () => _runCrawler(periodic: false)),
                const SizedBox(height: 8),
                _buildActionButton(label: 'SCHEDULE SEARCH', icon: Icons.timer, color: const Color(0xFF722F37), isOutline: true, onPressed: () => _runCrawler(periodic: true)),
              ],
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({required String label, required IconData icon, required Color color, required bool isOutline, required VoidCallback onPressed}) {
    return SizedBox(
      height: 38, // 버튼 높이를 줄여서 더 촘촘하게 배치
      width: double.infinity,
      child: isOutline 
        ? OutlinedButton.icon(
            onPressed: onPressed, 
            icon: Icon(icon, size: 16), 
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
            icon: Icon(icon, size: 16, color: Colors.white), 
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
      color: const Color(0xFFF4F1EA),
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
                      /* // Email feature hidden temporarily
                      if (_results.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.email, size: 24, color: Colors.black),
                          onPressed: _showEmailDialog,
                          tooltip: 'SEND BY EMAIL',
                        ),
                      ],
                      */
                    ],
                  )
                ),
                
                // Translation Controls
                if (_results.isNotEmpty || _isLoading) ...[
                  DropdownButton<String>(
                    value: _targetLanguage,
                    isDense: true,
                    style: const TextStyle(fontSize: 11, color: Colors.black, fontWeight: FontWeight.bold),
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 'original', child: Text('ORIGINAL')),
                      DropdownMenuItem(value: 'ko', child: Text('KOREAN')),
                      DropdownMenuItem(value: 'en', child: Text('ENGLISH')),
                      DropdownMenuItem(value: 'de', child: Text('GERMAN')),
                      DropdownMenuItem(value: 'fr', child: Text('FRENCH')),
                      DropdownMenuItem(value: 'ja', child: Text('JAPANESE')),
                      DropdownMenuItem(value: 'zh-cn', child: Text('CHINESE')),
                    ],
                    onChanged: _isLoading ? null : (val) {
                      setState(() => _targetLanguage = val!);
                      if (val == 'original') _runTranslation();
                    },
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 30,
                    child: OutlinedButton(
                      onPressed: _isLoading 
                          ? (_isTranslating ? () => setState(() => _isCancelled = true) : null)
                          : _runTranslation,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.black,
                        side: const BorderSide(color: Colors.black),
                        shape: const RoundedRectangleBorder(),
                      ),
                      child: Text(_isTranslating ? 'STOP' : 'TRANSLATE', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],

                if (!isMobile)
                  IconButton(onPressed: () => setState(() => _isResultVisible = false), icon: const Icon(Icons.close, color: Colors.black)),
              ],
            ),
          ),
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
                                    padding: const EdgeInsets.all(8.0),
                                    color: Colors.black,
                                    child: Row(
                                      children: [
                                        const Icon(Icons.auto_awesome, color: Colors.white, size: 16),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            'EDITORIAL: AI INSIGHT ${_aiInsight != null ? "($_selectedAIModel)" : ""}', 
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white, letterSpacing: 0.5),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (!_isAIAnalyzing)
                                          Padding(
                                            padding: const EdgeInsets.only(left: 4.0),
                                            child: PopupMenuButton<Map<String, String>>(
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
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  border: Border.all(color: Colors.white24),
                                                  borderRadius: BorderRadius.circular(2),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(_aiInsight == null ? Icons.play_arrow : Icons.refresh, size: 12, color: Colors.white),
                                                    const SizedBox(width: 4),
                                                    Flexible(
                                                      child: Text(
                                                        _aiInsight == null ? 'AI ANALYSIS' : 'RE-ANALYSIS (${_selectedAIModel})',
                                                        style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold),
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        if (!_isAIAnalyzing && _aiInsight != null)
                                          Padding(
                                            padding: const EdgeInsets.only(left: 4.0),
                                            child: TextButton.icon(
                                              onPressed: () => setState(() { _aiInsight = null; _isAIExpanded = true; }),
                                              icon: const Icon(Icons.edit_note, size: 14, color: Colors.white),
                                              label: const Text('EDIT PROMPT', style: TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold)),
                                              style: TextButton.styleFrom(
                                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                                minimumSize: Size.zero,
                                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(2),
                                                  side: const BorderSide(color: Colors.white24),
                                                ),
                                              ),
                                            ),
                                          ),
                                        if (!_isAIAnalyzing)
                                          Padding(
                                            padding: const EdgeInsets.only(left: 4.0),
                                            child: TextButton.icon(
                                              onPressed: _showAiSettingDialog,
                                              icon: const Icon(Icons.settings, size: 12, color: Colors.white),
                                              label: const Text('AI SETTINGS', style: TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold)),
                                              style: TextButton.styleFrom(
                                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                                minimumSize: Size.zero,
                                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(2),
                                                  side: const BorderSide(color: Colors.white24),
                                                ),
                                              ),
                                            ),
                                          ),
                                        const SizedBox(width: 4),
                                        if (_isAIAnalyzing)
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                                              const SizedBox(width: 8),
                                              GestureDetector(
                                                onTap: () {
                                                  setState(() => _isCancelled = true);
                                                  _showSnackBar('AI 분석 중단 중...');
                                                },
                                                child: const Text('STOP', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                                              ),
                                            ],
                                          )
                                        else
                                          Icon(_isAIExpanded ? Icons.expand_less : Icons.expand_more, color: Colors.white, size: 20),
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
                                                const Text('AI ANALYSIS REQUEST', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1, color: Colors.black54)),
                                                const SizedBox(height: 8),
                                                Autocomplete<String>(
                                                  optionsBuilder: (textValue) {
                                                    if (_suppressAiHistoryAuto) {
                                                      _suppressAiHistoryAuto = false;
                                                      return const Iterable<String>.empty();
                                                    }
                                                    return textValue.text == '' ? const Iterable<String>.empty() : _aiHistory.where((opt) => opt.toLowerCase().contains(textValue.text.toLowerCase()));
                                                  },
                                                  onSelected: (sel) => setState(() => _aiPromptController.text = sel),
                                                  fieldViewBuilder: (ctx, ctrl, focus, onSub) {
                                                    if (ctrl.text != _aiPromptController.text) Future.microtask(() => ctrl.text = _aiPromptController.text);
                                                    ctrl.addListener(() { if (_aiPromptController.text != ctrl.text) _aiPromptController.text = ctrl.text; });
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
                                                      onTap: () {
                                                        setState(() => _visitedUrls.add(article.url));
                                                        launchUrl(Uri.parse(article.url), mode: LaunchMode.externalApplication);
                                                      },
                                                      child: Text(
                                                        '• ${article.title} (${article.source})',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: _visitedUrls.contains(article.url) ? const Color(0xFF551A8B) : const Color(0xFF0000EE),
                                                          decoration: TextDecoration.underline,
                                                        ),
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
                                      decoration: TextDecoration.underline,
                                      decorationColor: _visitedUrls.contains(article.url) 
                                          ? const Color(0xFF551A8B).withOpacity(0.3)
                                          : const Color(0xFF0000EE).withOpacity(0.3),
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
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: ListView.builder(
                    controller: _logScrollController,
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
            ),
        ],
      ),
    );
  }
}
