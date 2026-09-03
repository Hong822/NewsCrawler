import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
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

        if (isMobile) {
          return Scaffold(
            appBar: AppBar(
              title: Text(_showMobileResults ? 'Crawl Results' : 'News Crawler'),
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              leading: _showMobileResults
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => setState(() => _showMobileResults = false),
                    )
                  : null,
            ),
            body: SafeArea(
              child: _showMobileResults ? _buildRightPanel(isMobile: true) : _buildLeftPanel(isMobile: true),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('News Crawler'),
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          ),
          body: SafeArea(
            child: Row(
              children: [
                SizedBox(
                  width: _isResultVisible ? constraints.maxWidth * _splitRatio : constraints.maxWidth - 40,
                  height: constraints.maxHeight,
                  child: _buildLeftPanel(isMobile: false),
                ),
                if (_isResultVisible)
                  MouseRegion(
                    cursor: SystemMouseCursors.resizeLeftRight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragUpdate: (details) {
                        setState(() {
                          _splitRatio += details.delta.dx / constraints.maxWidth;
                          if (_splitRatio < 0.2) _splitRatio = 0.2;
                          if (_splitRatio > 0.8) _splitRatio = 0.8;
                        });
                      },
                      child: Container(
                        width: 8,
                        color: Colors.grey[300],
                        child: const Center(child: Icon(Icons.drag_indicator, size: 16, color: Colors.grey)),
                      ),
                    ),
                  ),
                if (_isResultVisible)
                  Expanded(child: _buildRightPanel(isMobile: false))
                else
                  Material(
                    color: Colors.blue.withOpacity(0.05),
                    child: InkWell(
                      onTap: () => setState(() => _isResultVisible = true),
                      child: Container(
                        width: 40,
                        decoration: BoxDecoration(border: Border(left: BorderSide(color: Colors.grey[300]!))),
                        child: const Center(child: Icon(Icons.keyboard_arrow_left, color: Colors.blue)),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Search Query', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
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
                decoration: InputDecoration(
                  hintText: 'Enter keywords',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(icon: const Icon(Icons.history), onPressed: _showHistoryDialog),
                ),
                onSubmitted: (v) => onSub(),
              );
            },
          ),
          const SizedBox(height: 20),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              const Text('Select News Sources', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text('(${_selectedSources.length} / $_totalPublishersCount)', 
                  style: TextStyle(fontSize: 14, color: Colors.blue[700], fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ActionChip(label: const Text('Select All'), onPressed: () => _selectAll(true), avatar: const Icon(Icons.done_all, size: 16)),
              ActionChip(label: const Text('Deselect All'), onPressed: () => _selectAll(false), avatar: const Icon(Icons.clear_all, size: 16)),
            ],
          ),
          const SizedBox(height: 8),
          const Text('Select by Type:', style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 0,
            children: _availableCategories.map<Widget>((cat) {
              final isSelected = _isTypeSelected(cat);
              return FilterChip(
                selected: isSelected,
                label: Text(cat.toUpperCase(), style: TextStyle(fontSize: 10, color: isSelected ? Colors.white : Colors.black87)),
                selectedColor: Colors.blue,
                checkmarkColor: Colors.white,
                onSelected: (_) => _selectByCategory(cat),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          if (_isSourceLoading) const Center(child: CircularProgressIndicator())
          else ..._newsSourcesMap.entries.map((entry) {
            final countryName = entry.key;
            final publishers = entry.value;
            final publisherIds = publishers.map((p) => p['id'] as String).toList();
            final allInCountrySelected = publisherIds.every((id) => _selectedSources.contains(id));

            return ExpansionTile(
              title: Text(countryName),
              children: [
                CheckboxListTile(
                  title: const Text('Select All', style: TextStyle(fontWeight: FontWeight.bold, fontStyle: FontStyle.italic, fontSize: 13)),
                  value: allInCountrySelected,
                  activeColor: Colors.blue[800],
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _selectedSources.addAll(publisherIds);
                    } else {
                      for (var id in publisherIds) {
                        _selectedSources.remove(id);
                      }
                    }
                  }),
                ),
                const Divider(height: 1),
                ...publishers.map((publisher) {
                  final id = publisher['id'] as String;
                  return CheckboxListTile(
                    title: Text(publisher['nameLocal'] ?? publisher['name']),
                    subtitle: Text(publisher['type'] ?? ''),
                    value: _selectedSources.contains(id),
                    onChanged: (v) => setState(() { if (v == true) _selectedSources.add(id); else _selectedSources.remove(id); }),
                  );
                }).toList(),
              ],
            );
          }).toList(),
          const SizedBox(height: 20),
          const Text('Search Period', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _selectedPeriod,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: _periods.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
            onChanged: (val) => setState(() { _selectedPeriod = val!; if (_selectedPeriod != 'Dynamic') _selectedDateRange = null; }),
          ),
          if (_selectedPeriod == 'Dynamic') ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDateRangePicker(context: context, firstDate: DateTime(2000), lastDate: DateTime.now(), initialDateRange: _selectedDateRange);
                if (picked != null) setState(() => _selectedDateRange = picked);
              },
              icon: const Icon(Icons.calendar_today),
              label: Text(_selectedDateRange == null ? 'Select Date Range' : '${_selectedDateRange!.start.toString().split(' ')[0]} ~ ${_selectedDateRange!.end.toString().split(' ')[0]}'),
            ),
          ],
          const SizedBox(height: 20),
          const Text('AI Insight Summary', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Autocomplete<String>(
            optionsBuilder: (textValue) => textValue.text == '' 
                ? const Iterable<String>.empty() 
                : _aiHistory.where((opt) => opt.toLowerCase().contains(textValue.text.toLowerCase())),
            onSelected: (sel) => setState(() => _aiPromptController.text = sel),
            fieldViewBuilder: (ctx, ctrl, focus, onSub) {
              if (ctrl.text != _aiPromptController.text) {
                Future.microtask(() => ctrl.text = _aiPromptController.text);
              }
              ctrl.addListener(() {
                if (_aiPromptController.text != ctrl.text) {
                  _aiPromptController.text = ctrl.text;
                }
              });
              return TextField(
                controller: ctrl,
                focusNode: focus,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'e.g., Summarize these news and list key business implications for the automotive industry.',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(icon: const Icon(Icons.history), onPressed: _showAiHistoryDialog),
                ),
                onSubmitted: (v) => onSub(),
              );
            },
          ),
          const SizedBox(height: 24),
          // Search Buttons
          Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _runCrawler(periodic: false), 
                      icon: const Icon(Icons.play_arrow, size: 18), 
                      label: const Text('Run News Search', style: TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green[50], foregroundColor: Colors.green[900]),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _runCrawler(periodic: true), 
                      icon: const Icon(Icons.timer, size: 18), 
                      label: const Text('Periodic News Search', style: TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[50], foregroundColor: Colors.orange[900]),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _runCrawler(periodic: false, withAI: true), 
                      icon: const Icon(Icons.auto_awesome, size: 18), 
                      label: const Text('News Search + AI Insight', style: TextStyle(fontSize: 11)),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[50], foregroundColor: Colors.blue[900]),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _runCrawler(periodic: true, withAI: true), 
                      icon: const Icon(Icons.auto_awesome_motion, size: 18), 
                      label: const Text('Periodic News Search + AI Insight', style: TextStyle(fontSize: 11)),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.purple[50], foregroundColor: Colors.purple[900]),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRightPanel({required bool isMobile}) {
    return Container(
      color: Colors.grey[50],
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
                        'Results${_results.isNotEmpty ? ": ${_results.length}" : ""}', 
                        style: TextStyle(fontSize: isMobile ? 15 : 18, fontWeight: FontWeight.bold)
                      ),
                      if (_results.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        IconButton(
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.email, size: 20, color: Colors.blue),
                          onPressed: _showEmailDialog,
                          tooltip: '이메일 발송',
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
                    style: const TextStyle(fontSize: 12, color: Colors.black),
                    items: const [
                      DropdownMenuItem(value: 'original', child: Text('원문')),
                      DropdownMenuItem(value: 'ko', child: Text('한글')),
                      DropdownMenuItem(value: 'en', child: Text('영어')),
                    ],
                    onChanged: _isLoading ? null : (val) {
                      setState(() => _targetLanguage = val!);
                      if (val == 'original') _runTranslation();
                    },
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    height: 28,
                    child: ElevatedButton(
                      onPressed: _isLoading 
                          ? (_isTranslating ? () => setState(() => _isCancelled = true) : null)
                          : _runTranslation,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isTranslating ? Colors.red[100] : Colors.blue[100],
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: Text(_isTranslating ? '중지' : '번역', style: const TextStyle(fontSize: 11)),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],

                if (!isMobile)
                  IconButton(onPressed: () => setState(() => _isResultVisible = false), icon: const Icon(Icons.keyboard_arrow_right)),
              ],
            ),
          ),
          
          // Result List
          Expanded(
            child: _results.isEmpty && !_isLoading && !_isAIAnalyzing
                ? const Center(child: Text('No results yet.'))
                : SelectionArea(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: _results.length + (_aiInsight != null || _isAIAnalyzing ? 1 : 0),
                      itemBuilder: (context, index) {
                        if ((_aiInsight != null || _isAIAnalyzing) && index == 0) {
                          return Card(
                            color: Colors.blue[50],
                            margin: const EdgeInsets.only(bottom: 16, top: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                InkWell(
                                  onTap: () => setState(() => _isAIExpanded = !_isAIExpanded),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.auto_awesome, color: Colors.blue, size: 20),
                                        const SizedBox(width: 8),
                                        const Text('AI Insight', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue)),
                                        const Spacer(),
                                        if (_isAIAnalyzing)
                                          const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        else
                                          Icon(_isAIExpanded ? Icons.expand_less : Icons.expand_more, color: Colors.blue),
                                      ],
                                    ),
                                  ),
                                ),
                                if (_isAIExpanded) ...[
                                  const Divider(height: 1),
                                  Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: _isAIAnalyzing
                                        ? const Row(
                                            children: [
                                              Text('AI가 분석 중입니다...', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.blueGrey)),
                                            ],
                                          )
                                        : Text(_aiInsight!, style: const TextStyle(fontSize: 13, height: 1.5)),
                                  ),
                                ],
                              ],
                            ),
                          );
                        }
                        
                        final articleIndex = (_aiInsight != null || _isAIAnalyzing) ? index - 1 : index;
                        final article = _results[articleIndex];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: InkWell(
                            onTap: () => launchUrl(Uri.parse(article.url), mode: LaunchMode.externalApplication),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(article.title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 13)),
                                  const SizedBox(height: 4),
                                  Text('(${article.countryName}) ${article.source} * ${article.pubDate ?? ""}', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),

          // Progress Bar & Stop Button
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 4,
                      child: LinearProgressIndicator(
                        value: _progress, 
                        backgroundColor: Colors.grey[200], 
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue)
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.stop_circle, color: Colors.red, size: 24),
                    onPressed: () {
                      setState(() => _isCancelled = true);
                      _showSnackBar('중단 요청됨...');
                    },
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
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.05),
        border: const Border(top: BorderSide(color: Colors.grey)),
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
                  color: Colors.grey[300],
                  height: 4,
                  width: double.infinity,
                ),
              ),
            ),
          InkWell(
            onTap: () => setState(() => _isLogVisible = !_isLogVisible),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.list_alt, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Logs', 
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                      overflow: TextOverflow.ellipsis,
                    )
                  ),
                  if (_isLogVisible)
                    IconButton(
                      constraints: const BoxConstraints(maxHeight: 24, maxWidth: 24),
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.copy, size: 16, color: Colors.grey),
                      tooltip: 'Copy all logs',
                      onPressed: () {
                        final allLogs = _logs.map((l) => l.message).join('\n');
                        Clipboard.setData(ClipboardData(text: allLogs));
                        _showSnackBar('All logs copied to clipboard');
                      },
                    ),
                  Icon(_isLogVisible ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up, size: 16, color: Colors.grey),
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
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  color: Colors.black.withOpacity(0.02),
                  child: ListView.builder(
                    controller: _logScrollController,
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      final log = _logs[index];
                      return Text(
                        log.message,
                        style: TextStyle(
                          fontSize: log.isSummary ? 14 : 10,
                          fontFamily: 'monospace',
                          color: log.color,
                          fontWeight: (log.isHeader || log.isSummary) ? FontWeight.bold : FontWeight.normal,
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
