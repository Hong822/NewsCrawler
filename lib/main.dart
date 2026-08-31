import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'news_crawler_service.dart';

void main() {
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

class NewsCrawlerHomePage extends StatefulWidget {
  const NewsCrawlerHomePage({super.key});

  @override
  State<NewsCrawlerHomePage> createState() => _NewsCrawlerHomePageState();
}

class _NewsCrawlerHomePageState extends State<NewsCrawlerHomePage> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final NewsCrawlerService _crawlerService = NewsCrawlerService();
  
  Map<String, List<Map<String, dynamic>>> _newsSourcesMap = {};
  bool _isSourceLoading = true;

  final Set<String> _selectedSources = {};
  String _selectedPeriod = '1 Day';
  final List<String> _periods = ['1 Day', '3 Days', '1 Week', '1 Month', '1 Year', 'Dynamic'];
  DateTimeRange? _selectedDateRange;

  bool _sendEmail = false;
  bool _isLoading = false;
  List<NewsArticle> _results = [];
  Timer? _periodicTimer;
  List<String> _searchHistory = [];

  @override
  void initState() {
    super.initState();
    _loadNewsSources();
    _loadApiKey();
    _loadSearchHistory();
  }

  Future<void> _loadSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _searchHistory = prefs.getStringList('search_history') ?? [];
    });
  }

  Future<void> _saveSearchQuery(String query) async {
    if (query.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    List<String> history = prefs.getStringList('search_history') ?? [];
    
    // Remove if already exists to move to top
    history.remove(query);
    history.insert(0, query);
    
    // Limit history to 20 items
    if (history.length > 20) history = history.sublist(0, 20);
    
    await prefs.setStringList('search_history', history);
    setState(() {
      _searchHistory = history;
    });
  }

  Future<void> _loadApiKey() async {
    try {
      final String key = await rootBundle.loadString('assets/api_key.txt');
      setState(() {
        _apiKeyController.text = key.trim();
      });
    } catch (e) {
      print('Failed to load API key from assets: $e');
    }
  }

  Future<void> _loadNewsSources() async {
    try {
      final String response = await rootBundle.loadString('assets/news_sources.json');
      final data = json.decode(response);
      final Map<String, List<Map<String, dynamic>>> tempMap = {};
      
      for (var country in data['countries']) {
        final countryName = country['countryName'] as String;
        final publishers = (country['publishers'] as List).map((e) => e as Map<String, dynamic>).toList();
        tempMap[countryName] = publishers;
      }

      setState(() {
        _newsSourcesMap = tempMap;
        _isSourceLoading = false;
      });
    } catch (e) {
      setState(() => _isSourceLoading = false);
      _showSnackBar('Failed to load news sources: $e');
    }
  }

  void _runCrawler({required bool periodic}) async {
    final query = _searchController.text;
    final sources = _selectedSources.toList();
    final period = _selectedPeriod;

    if (query.isEmpty) {
      _showSnackBar('Please enter a search query');
      return;
    }

    if (sources.isEmpty) {
      _showSnackBar('Please select at least one news source');
      return;
    }

    if (period == 'Dynamic' && _selectedDateRange == null) {
      _showSnackBar('Please select a date range');
      return;
    }

    if (periodic) {
      _startPeriodicTask();
      _saveSearchQuery(query);
      return;
    }

    setState(() {
      _isLoading = true;
      _results = [];
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
      );

      setState(() {
        _results = articles;
        _isLoading = false;
      });

      if (_sendEmail && _emailController.text.isNotEmpty) {
        await _crawlerService.sendEmail(_emailController.text, articles);
        _showSnackBar('Summary sent to ${_emailController.text}');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar('Error: $e');
    }
  }

  void _startPeriodicTask() {
    _periodicTimer?.cancel();
    _showSnackBar('Periodic task started (Every 5 mins)');
    
    // Execute immediately once
    _runCrawler(periodic: false);

    _periodicTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      print('Executing periodic crawl...');
      _runCrawler(periodic: false);
    });
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _periodicTimer?.cancel();
    _searchController.dispose();
    _emailController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('News Crawler'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Search Query', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Autocomplete<String>(
                optionsBuilder: (TextEditingValue textEditingValue) {
                  if (textEditingValue.text == '') {
                    return const Iterable<String>.empty();
                  }
                  return _searchHistory.where((String option) {
                    return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
                  });
                },
                onSelected: (String selection) {
                  _searchController.text = selection;
                },
                fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                  // Sync with our existing controller
                  controller.text = _searchController.text;
                  controller.addListener(() {
                    _searchController.text = controller.text;
                  });

                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: const InputDecoration(
                      hintText: 'Enter keywords (e.g., Apple AND Google)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.search),
                    ),
                    onSubmitted: (value) {
                      onFieldSubmitted();
                    },
                  );
                },
              ),
              const SizedBox(height: 20),

            const Text('Select News Sources', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_isSourceLoading)
              const Center(child: CircularProgressIndicator())
            else
              ..._newsSourcesMap.entries.map((entry) {
                return ExpansionTile(
                  title: Text(entry.key),
                  children: entry.value.map((publisher) {
                    final sourceId = publisher['id'] as String;
                    final sourceName = publisher['nameLocal'] ?? publisher['name'];
                    return CheckboxListTile(
                      title: Text(sourceName),
                      subtitle: Text(publisher['type'] ?? ''),
                      value: _selectedSources.contains(sourceId),
                      onChanged: (bool? value) {
                        setState(() {
                          if (value == true) {
                            _selectedSources.add(sourceId);
                          } else {
                            _selectedSources.remove(sourceId);
                          }
                        });
                      },
                    );
                  }).toList(),
                );
              }).toList(),
            const SizedBox(height: 20),

            const Text('Search Period', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedPeriod,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: _periods.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
              onChanged: (val) => setState(() {
                _selectedPeriod = val!;
                if (_selectedPeriod != 'Dynamic') _selectedDateRange = null;
              }),
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
                  );
                  if (picked != null) {
                    setState(() => _selectedDateRange = picked);
                  }
                },
                icon: const Icon(Icons.calendar_today),
                label: Text(_selectedDateRange == null
                    ? 'Select Date Range'
                    : '${_selectedDateRange!.start.toString().split(' ')[0]} ~ ${_selectedDateRange!.end.toString().split(' ')[0]}'),
              ),
            ],
            const SizedBox(height: 20),

            Row(
              children: [
                Checkbox(
                  value: _sendEmail,
                  onChanged: (v) => setState(() => _sendEmail = v ?? false),
                ),
                const Text('Send summary to email'),
              ],
            ),
            if (_sendEmail)
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(
                  hintText: 'Email address',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email),
                ),
              ),
            
            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _runCrawler(periodic: true),
                    icon: const Icon(Icons.timer),
                    label: const Text('Periodic Run'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[100]),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _runCrawler(periodic: false),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Run Once'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green[100]),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),
            
            const Divider(),
            const Text('Crawl Results (Click to open)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_results.isEmpty)
              const Text('No results yet. Run the crawler to see news.')
            else
              ..._results.map((article) => Card(
                margin: const EdgeInsets.only(bottom: 12),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () async {
                    try {
                      final url = Uri.parse(article.url);
                      await launchUrl(url, mode: LaunchMode.externalApplication);
                    } catch (e) {
                      _showSnackBar('Could not launch the article: $e');
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          article.title,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.source, size: 14, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text(article.source, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                            if (article.pubDate != null) ...[
                              const SizedBox(width: 12),
                              const Icon(Icons.calendar_today, size: 12, color: Colors.grey),
                              const SizedBox(width: 4),
                              Text(article.pubDate!, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              )).toList(),
          ],
        ),
      ),
    ),
  );
}
}

