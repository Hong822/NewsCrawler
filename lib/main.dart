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
  String _targetLanguage = 'ko'; // Default to Korean
  bool _showMobileResults = false; // Mobile navigation state
  String? _aiInsight;
  bool _isAIAnalyzing = false;
  bool _isAIExpanded = true;
  final Set<String> _visitedUrls = {};

  @override
  void initState() {
    super.initState();
    _loadNewsSources();
    _loadApiKey();
    _loadSearchHistory();
    _loadEmailHistory();
    _loadAiHistory();
  }

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
                  optionsBuilder: (textValue) => textValue.text == '' 
                      ? const Iterable<String>.empty() 
                      : _emailHistory.where((opt) => opt.toLowerCase().contains(textValue.text.toLowerCase())),
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

  Future<void> _loadApiKey() async {
    try {
      final String key = await rootBundle.loadString('assets/api_key.txt');
      setState(() { _apiKeyController.text = key.trim(); });
    } catch (e) { print('Failed to load API key from assets: $e'); }
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

  void _runCrawler({required bool periodic, bool withAI = false}) async {
    final query = _searchController.text;
    final sources = _selectedSources.toList();
    final period = _selectedPeriod;
    final aiPrompt = _aiPromptController.text;

    if (query.isEmpty) { _showSnackBar('Please enter a search query'); return; }
    if (sources.isEmpty) { _showSnackBar('Please select at least one news source'); return; }
    if (period == 'Dynamic' && _selectedDateRange == null) { _showSnackBar('Please select a date range'); return; }
    if (withAI && aiPrompt.isEmpty) { _showSnackBar('Please enter AI Insight request'); return; }

    if (periodic) { _startPeriodicTask(withAI: withAI); _saveSearchQuery(query); return; }

    setState(() {
      _isLoading = true;
      _isTranslating = false;
      _results = [];
      _logs = [];
      _progress = 0.0;
      _isCancelled = false;
      _isResultVisible = true;
      _isLogVisible = true;
      _showMobileResults = true; // Switch to results view on mobile
      _aiInsight = null;
    });

    _saveSearchQuery(query);
    if (withAI) _saveAiQuery(aiPrompt);

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
      });

      if (withAI && articles.isNotEmpty && !_isCancelled) {
        setState(() {
          _isAIAnalyzing = true;
          _aiInsight = null;
        });
        _addLog('\n[AI Insight] Generating analysis...', isHeader: true);
        final insight = await _crawlerService.getAIInsight(
          apiKey: _apiKeyController.text,
          userPrompt: aiPrompt,
          articles: articles,
        );

        String displayInsight = insight;
        if (insight.startsWith("AI Insight Error:")) {
          if (insight.contains("503")) {
            displayInsight = "현재 AI 서비스 사용량이 많아 응답이 지연되고 있습니다. 잠시 후 다시 시도해 주세요.";
          } else if (insight.contains("429")) {
            displayInsight = "너무 짧은 시간에 많은 요청이 전달되었습니다. 잠시만 기다려 주세요.";
          } else if (insight.contains("400") || insight.contains("401") || insight.contains("403")) {
            displayInsight = "API 키가 올바르지 않거나 권한이 없습니다. 설정을 확인해 주세요.";
          } else {
            displayInsight = "AI 분석 중 오류가 발생했습니다. 다시 시도해 주세요.";
          }
        }

        setState(() {
          _aiInsight = displayInsight;
          _isAIAnalyzing = false;
          _isAIExpanded = true;
        });
        _addLog('\n--- AI Insight Result ---\n$insight', isHeader: true, isSummary: true);
      } else {
        setState(() {
          _isAIAnalyzing = false;
        });
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _addLog('Error: $e', isError: true);
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
      _showSnackBar('번역 완료');
    } catch (e) {
      setState(() {
        _isLoading = false;
        _isTranslating = false;
      });
      _addLog('번역 오류: $e', isError: true);
    }
  }

  void _startPeriodicTask({bool withAI = false}) {
    _periodicTimer?.cancel();
    _showSnackBar('Periodic task started (Every 5 mins)');
    _runCrawler(periodic: false, withAI: withAI);
    _periodicTimer = Timer.periodic(const Duration(minutes: 5), (timer) { _runCrawler(periodic: false, withAI: withAI); });
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
              Text(
                'The News Crawler',
                style: GoogleFonts.unifrakturMaguntia(
                  fontSize: 42,
                  color: Colors.black,
                  letterSpacing: -0.5,
                ),
              ),
              Container(
                height: 1.2,
                width: 320,
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
              optionsBuilder: (textValue) => textValue.text == '' ? const Iterable<String>.empty() : _searchHistory.where((opt) => opt.toLowerCase().contains(textValue.text.toLowerCase())),
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
                  final picked = await showDateRangePicker(context: context, firstDate: DateTime(2000), lastDate: DateTime.now(), initialDateRange: _selectedDateRange);
                  if (picked != null) setState(() => _selectedDateRange = picked);
                },
                icon: const Icon(Icons.calendar_today, size: 16, color: Colors.black),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.black, side: const BorderSide(color: Colors.black)),
                label: Text(_selectedDateRange == null ? 'SELECT RANGE' : '${_selectedDateRange!.start.toString().split(' ')[0]} ~ ${_selectedDateRange!.end.toString().split(' ')[0]}'),
              ),
            ],
            const SizedBox(height: 24),
            const Text('AI ANALYSIS REQUEST', style: TextStyle(fontFamily: 'Serif', fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
            const Divider(height: 20),
            Autocomplete<String>(
              optionsBuilder: (textValue) => textValue.text == '' ? const Iterable<String>.empty() : _aiHistory.where((opt) => opt.toLowerCase().contains(textValue.text.toLowerCase())),
              onSelected: (sel) => setState(() => _aiPromptController.text = sel),
              fieldViewBuilder: (ctx, ctrl, focus, onSub) {
                if (ctrl.text != _aiPromptController.text) Future.microtask(() => ctrl.text = _aiPromptController.text);
                ctrl.addListener(() { if (_aiPromptController.text != ctrl.text) _aiPromptController.text = ctrl.text; });
                return TextField(
                  controller: ctrl,
                  focusNode: focus,
                  maxLines: 3,
                  style: const TextStyle(fontFamily: 'Serif', fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Describe what you want the AI to analyze...',
                    border: const OutlineInputBorder(borderSide: BorderSide(color: Colors.black)),
                    suffixIcon: IconButton(icon: const Icon(Icons.history, color: Colors.black), onPressed: _showAiHistoryDialog),
                  ),
                );
              },
            ),
            const SizedBox(height: 32),
            // Action Buttons
            Column(
              children: [
                _buildActionButton(label: 'RUN SEARCH', icon: Icons.play_arrow, color: const Color(0xFF722F37), isOutline: false, onPressed: () => _runCrawler(periodic: false)),
                const SizedBox(height: 8),
                _buildActionButton(label: 'SCHEDULE SEARCH', icon: Icons.timer, color: const Color(0xFF722F37), isOutline: true, onPressed: () => _runCrawler(periodic: true)),
                const SizedBox(height: 16),
                _buildActionButton(label: 'RUN + AI INSIGHT', icon: Icons.auto_awesome, color: const Color(0xFF1B3A4B), isOutline: false, onPressed: () => _runCrawler(periodic: false, withAI: true)),
                const SizedBox(height: 8),
                _buildActionButton(label: 'SCHEDULE + AI INSIGHT', icon: Icons.auto_awesome_motion, color: const Color(0xFF1B3A4B), isOutline: true, onPressed: () => _runCrawler(periodic: true, withAI: true)),
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
                      itemCount: _results.length + (_aiInsight != null || _isAIAnalyzing ? 1 : 0),
                      itemBuilder: (context, index) {
                        if ((_aiInsight != null || _isAIAnalyzing) && index == 0) {
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
                                        const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                                        const SizedBox(width: 8),
                                        const Text('EDITORIAL: AI INSIGHT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white, letterSpacing: 1)),
                                        const Spacer(),
                                        if (_isAIAnalyzing)
                                          const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                        else
                                          Icon(_isAIExpanded ? Icons.expand_less : Icons.expand_more, color: Colors.white),
                                      ],
                                    ),
                                  ),
                                ),
                                if (_isAIExpanded)
                                  Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: _isAIAnalyzing
                                        ? const Text('ANALYZING CURRENT EVENTS...', style: TextStyle(fontFamily: 'Serif', fontStyle: FontStyle.italic))
                                        : Text(_aiInsight!, style: const TextStyle(fontFamily: 'Serif', fontSize: 15, height: 1.6)),
                                  ),
                              ],
                            ),
                          );
                        }
                        
                        final articleIndex = (_aiInsight != null || _isAIAnalyzing) ? index - 1 : index;
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
                                      Text(article.countryName.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
                                      const Text(' | ', style: TextStyle(fontSize: 10)),
                                      Text(article.source.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
                                      const Spacer(),
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
