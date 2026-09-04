import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart'; // kIsWeb 확인용
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:dart_openai/dart_openai.dart';

class NewsArticle {
  String title;
  final String originalTitle;
  final String url;
  final String source;
  final String? pubDate;
  final String countryName;

  NewsArticle({
    required this.title,
    required this.originalTitle,
    required this.url,
    required this.source,
    this.pubDate,
    required this.countryName,
  });
}

class NewsCrawlerService {
  // Manual Google Translate implementation to avoid package issues
  Future<String> _translateManual(String text, {String from = 'auto', String to = 'ko'}) async {
    if (text.isEmpty) return "";
    try {
      final url = Uri.parse('https://translate.googleapis.com/translate_a/single?client=gtx&sl=$from&tl=$to&dt=t&q=${Uri.encodeComponent(text)}');
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        if (data.isNotEmpty && data[0] is List) {
          final StringBuffer sb = StringBuffer();
          for (var part in data[0]) {
            if (part is List && part.isNotEmpty) {
              sb.write(part[0]);
            }
          }
          return sb.toString();
        }
      }
      return text;
    } catch (e) {
      print('Manual Translation Error: $e');
      return text;
    }
  }

  Future<List<NewsArticle>> crawl({
    required String query,
    required List<String> sources,
    required String period,
    required String apiKey,
    required Function(String message, {bool? isMatch, bool? isError, bool? isHeader, bool? isSummary}) onLog,
    required Function(double progress) onProgress,
    bool Function()? isCancelled,
    String? aiPrompt,
  }) async {
    if (isCancelled?.call() ?? false) return [];

    // Get a reliable English translation
    String englishQuery = query;
    final translatedEn = await _translateManual(query, from: 'auto', to: 'en');
    if (translatedEn.isNotEmpty && translatedEn.toLowerCase() != query.toLowerCase()) {
      englishQuery = translatedEn;
      onLog('* [en] Global keyword confirmed (Google Translate): "$query" -> "$englishQuery"');
    }

    final String response = await rootBundle.loadString('assets/news_sources.json');
    final data = json.decode(response);
    
    List<Map<String, dynamic>> selectedPubs = [];
    for (var country in data['countries']) {
      final lang = country['language'];
      final countryName = country['countryName'];
      final publishers = (country['publishers'] as List).cast<Map<String, dynamic>>();
      for (var id in sources) {
        final pub = publishers.firstWhere((p) => p['id'] == id, orElse: () => {});
        if (pub.isNotEmpty) {
          final pubData = Map<String, dynamic>.from(pub);
          pubData['lang'] = lang;
          pubData['countryName'] = countryName;
          selectedPubs.add(pubData);
        }
      }
    }

    onLog('--- SEARCH INITIATED', isHeader: true);
    onLog('* Keywords: $query');
    if (englishQuery != query) onLog('* Global Keywords: $englishQuery');
    onLog('* Target Sources: ${selectedPubs.length}');
    if (aiPrompt != null && aiPrompt.isNotEmpty) onLog('* AI Request: $aiPrompt');

    List<NewsArticle> allArticles = [];
    int completedSources = 0;
    int totalMatches = 0;
    int totalScanned = 0;

    for (var pub in selectedPubs) {
      if (isCancelled?.call() ?? false) {
        onLog('\n--- Search cancelled by user.', isError: true);
        return allArticles;
      }

      final counts = await _crawlSingleSource(
        pub, query, englishQuery, period, allArticles, onLog
      );
      totalMatches += counts['matches'] ?? 0;
      totalScanned += counts['scanned'] ?? 0;
      completedSources++;
      onProgress(completedSources / selectedPubs.length);
    }

    // Sort by date descending (latest first)
    allArticles.sort((a, b) {
      if (a.pubDate == null) return 1;
      if (b.pubDate == null) return -1;
      return b.pubDate!.compareTo(a.pubDate!);
    });

    onLog('\nSEARCH COMPLETE', isHeader: true, isSummary: true);
    onLog('* Total Scanned: $totalScanned');
    onLog('* Total Matched: $totalMatches');
    onLog('* Keywords: $query');
    onLog('* Period: $period');
    onLog('* Sources: ${selectedPubs.length}');
    if (aiPrompt != null && aiPrompt.isNotEmpty) onLog('* AI Request: $aiPrompt');

    return allArticles;
  }

  Future<Map<String, int>> _crawlSingleSource(
    Map<String, dynamic> pub,
    String query,
    String englishQuery,
    String period,
    List<NewsArticle> results,
    Function(String message, {bool? isMatch, bool? isError, bool? isHeader, bool? isSummary}) onLog,
  ) async {
    final lang = pub['lang'].toString().split('-')[0];
    final sourceNameLocal = pub['nameLocal'] ?? pub['name'];
    onLog('\n[Searching $sourceNameLocal]', isHeader: true);

    String localQuery = (lang == 'ko') ? query : englishQuery;
    
    if (lang != 'ko' && lang != 'en') {
      final translated = await _translateManual(query, from: 'auto', to: lang);
      if (translated.isNotEmpty && translated.toLowerCase() != query.toLowerCase()) {
        localQuery = translated;
        onLog('* [$lang] Local translation success (Google): "$localQuery"');
      }
    }

    String domain = Uri.parse(pub['url']).host;
    if (domain.startsWith('www.')) domain = domain.substring(4);

    final timeParam = _getTimeParam(period);
    
    // Step 1: Try direct RSS if available
    int matchCount = 0;
    int scannedCount = 0;
    bool directSuccess = false;

    if (pub['rss'] != null) {
      final List<String> rssUrls = [];
      if (pub['rss']['url'] != null) rssUrls.add(pub['rss']['url']);
      if (pub['rss']['urls'] != null) rssUrls.addAll((pub['rss']['urls'] as List).cast<String>());

      if (rssUrls.isNotEmpty) {
        onLog('* [RSS] Direct connection attempt (${rssUrls.length} feeds)');
        
        for (var rssUrl in rssUrls) {
          final counts = await _fetchAndProcessRssWithCount(
            url: Uri.parse(rssUrl),
            sourceName: sourceNameLocal,
            countryName: pub['countryName'],
            query: query,
            englishQuery: englishQuery,
            localQuery: localQuery,
            period: period,
            results: results,
            onLog: onLog,
          );
          matchCount += counts['matches'] ?? 0;
          scannedCount += counts['scanned'] ?? 0;
        }
        
        if (matchCount > 0) {
          directSuccess = true;
          onLog('* [RSS] Successfully collected $matchCount articles via direct connection');
        } else {
          onLog('* [RSS] No matches found via direct connection, trying Google News fallback');
        }
      }
    }

    // Step 2: Fallback to Google News search
    if (!directSuccess) {
      final fullQuery = '$localQuery site:$domain $timeParam';
      onLog('* Query (Google): "$fullQuery"');

      final googleRssUrl = Uri.https('news.google.com', '/rss/search', {
        'q': fullQuery,
        'hl': lang,
        'gl': _getGl(pub['lang']),
        'ceid': _getCeid(pub['lang']),
      });

      final counts = await _fetchAndProcessRssWithCount(
        url: googleRssUrl,
        sourceName: sourceNameLocal,
        countryName: pub['countryName'],
        query: query,
        englishQuery: englishQuery,
        localQuery: localQuery,
        period: period,
        results: results,
        onLog: onLog,
      );
      matchCount = counts['matches'] ?? 0;
      scannedCount = counts['scanned'] ?? 0;
    }

    onLog('$sourceNameLocal Search Finished - $matchCount match(es)');
    return {'matches': matchCount, 'scanned': scannedCount};
  }

  Future<Map<String, int>> _fetchAndProcessRssWithCount({
    required Uri url,
    required String sourceName,
    required String countryName,
    required String query,
    required String englishQuery,
    required String localQuery,
    required String period,
    required List<NewsArticle> results,
    required Function(String message, {bool? isMatch, bool? isError, bool? isHeader, bool? isSummary}) onLog,
  }) async {
    try {
      String xmlBody;
      
      if (kIsWeb) {
        // 웹에서는 CORS 문제로 인해 Cloud Functions 프록시를 사용합니다.
        final result = await FirebaseFunctions.instance.httpsCallable('fetchRssData').call({'url': url.toString()});
        if (result.data['success'] == true) {
          xmlBody = result.data['data'];
        } else {
          onLog('* [Proxy] Data collection failed: ${result.data['error']}', isError: true);
          return {'matches': 0, 'scanned': 0};
        }
      } else {
        // PC/모바일에서는 직접 요청이 가능합니다.
        final res = await http.get(url).timeout(const Duration(seconds: 15));
        if (res.statusCode != 200) return {'matches': 0, 'scanned': 0};
        // 인코딩 감지 오류 방지를 위해 직접 UTF-8로 디코딩합니다.
        xmlBody = utf8.decode(res.bodyBytes, allowMalformed: true);
      }

      // Improved XML detection
      final trimmedBody = xmlBody.trim();
      if (!trimmedBody.startsWith('<') || (!trimmedBody.contains('<rss') && !trimmedBody.contains('<feed') && !trimmedBody.contains('<channel'))) {
        onLog('* [RSS] Response is not a valid XML format. (Snippet: ${trimmedBody.length > 100 ? trimmedBody.substring(0, 100) : trimmedBody})', isError: true);
        return {'matches': 0, 'scanned': 0};
      }

      final document = XmlDocument.parse(xmlBody);
      // Support both RSS (<item>) and Atom (<entry>) tags
      var items = document.findAllElements('item').toList();
      if (items.isEmpty) {
        items = document.findAllElements('entry').toList();
      }

      if (items.isEmpty) {
        onLog('* [RSS] No article entries (<item> or <entry>) found in XML.', isError: true);
        return {'matches': 0, 'scanned': 0};
      }
      
      Map<String, List<XmlElement>> itemsByDate = {};
      for (var item in items) { // 100개 제한 제거
        final dateStr = item.findElements('pubDate').isNotEmpty ? _formatRssDate(item.findElements('pubDate').first.text) ?? 'Unknown Date' : 'Unknown Date';
        itemsByDate.putIfAbsent(dateStr, () => []).add(item);
      }

      int matchCount = 0;
      int scannedCount = items.length;

      for (var date in itemsByDate.keys) {
        final dateItems = itemsByDate[date]!;
        onLog('- Date: $date Total: ${dateItems.length}');
        
        for (int i = 0; i < dateItems.length; i++) {
          final item = dateItems[i];
          String rawTitle = item.findElements('title').isNotEmpty ? item.findElements('title').first.text : 'No Title';
          final link = item.findElements('link').isNotEmpty ? item.findElements('link').first.text : '';
          
          bool isMatch = _checkMatch(rawTitle, query) || 
                        _checkMatch(rawTitle, localQuery) ||
                        _checkMatch(rawTitle, englishQuery);

          // 기간 필터링 강화: 실제 날짜를 파싱하여 비교
          final rawDateStr = item.findElements('pubDate').isNotEmpty ? item.findElements('pubDate').first.text : null;
          if (isMatch && !_isWithinPeriod(rawDateStr, period)) {
            isMatch = false;
          }

          final logIndex = i + 1;
          if (isMatch) {
            onLog('[$logIndex] $rawTitle - MATCH', isMatch: true);
            if (rawTitle.contains(' - $sourceName')) rawTitle = rawTitle.replaceAll(' - $sourceName', '').trim();
            results.add(NewsArticle(
              title: rawTitle,
              originalTitle: rawTitle,
              url: link,
              source: sourceName,
              pubDate: date,
              countryName: countryName,
            ));
            matchCount++;
          } else {
            onLog('[$logIndex] $rawTitle - MISMATCH', isMatch: false);
          }
        }
      }
      return {'matches': matchCount, 'scanned': scannedCount};
    } catch (e) {
      onLog('* [RSS] Exception occurred during processing ($sourceName): $e', isError: true);
      return {'matches': 0, 'scanned': 0};
    }
  }

  bool _checkMatch(String title, String query) {
    title = title.toLowerCase();
    query = query.toLowerCase();
    if (query.contains(' and ') || query.contains(' && ')) {
      final terms = query.split(RegExp(r' and | && '));
      return terms.every((t) => title.contains(t.trim()));
    }
    if (query.contains(' or ') || query.contains(' || ')) {
      final terms = query.split(RegExp(r' or | \|\| '));
      return terms.any((t) => title.contains(t.trim()));
    }
    return title.contains(query);
  }

  Future<void> translateArticles({
    required List<NewsArticle> articles,
    required String targetLang,
    required Function(String message, {bool? isMatch, bool? isError, bool? isHeader, bool? isSummary}) onLog,
    required Function(double progress) onProgress,
    required bool Function() isCancelled,
  }) async {
    if (targetLang == 'original') {
      for (var a in articles) {
        a.title = a.originalTitle;
      }
      return;
    }
    
    onLog('\n[TRANSLATION] Translating articles to $targetLang...', isHeader: true);
    int translatedCount = 0;
    
    for (var article in articles) {
      if (isCancelled()) {
        onLog('\n--- Translation cancelled.', isError: true);
        return;
      }

      try {
        final translated = await _translateManual(article.originalTitle, to: targetLang);
        article.title = translated;
      } catch (e) {
        onLog('Translation error: $e', isError: true);
      }
      
      translatedCount++;
      onProgress(translatedCount / articles.length);
    }
    onLog('Translation complete.');
  }

  String? _formatRssDate(String? dateStr) {
    if (dateStr == null) return null;
    try {
      final parts = dateStr.split(' ');
      if (parts.length >= 4) return '${parts[3]}.${_monthToNum(parts[2])}.${parts[1]}';
      return dateStr;
    } catch (_) { return dateStr; }
  }

  String _monthToNum(String month) {
    const months = {'Jan':'01','Feb':'02','Mar':'03','Apr':'04','May':'05','Jun':'06','Jul':'07','Aug':'08','Sep':'09','Oct':'10','Nov':'11','Dec':'12'};
    return months[month] ?? '01';
  }

  bool _isWithinPeriod(String? pubDateStr, String period) {
    if (pubDateStr == null || period == '' || period == 'Dynamic' || period == 'All Time') return true;
    try {
      final pubDate = _parseRssDate(pubDateStr);
      if (pubDate == null) return true; // 날짜 파싱 실패 시 일단 포함

      final now = DateTime.now();
      final diff = now.difference(pubDate).inDays;
      
      if (period == '1 Day') return diff <= 1;
      if (period == '3 Days') return diff <= 3;
      if (period == '1 Week') return diff <= 7;
      if (period == '1 Month') return diff <= 31;
      if (period == '1 Year') return diff <= 365;
    } catch (_) {}
    return true;
  }

  DateTime? _parseRssDate(String? dateStr) {
    if (dateStr == null) return null;
    
    // 1. 기본 파싱 시도 (ISO 8601 등)
    DateTime? parsed = DateTime.tryParse(dateStr);
    if (parsed != null) return parsed;

    // 2. RSS/RFC 822 형식 수동 파싱 (예: "Wed, 02 Oct 2024 13:00:00 GMT")
    try {
      final parts = dateStr.split(' ');
      // parts[1]: 일, parts[2]: 월(Jan...), parts[3]: 연
      if (parts.length >= 4) {
        final day = int.tryParse(parts[1]);
        final monthStr = parts[2];
        final year = int.tryParse(parts[3]);
        
        if (day != null && year != null) {
          final month = int.parse(_monthToNum(monthStr));
          return DateTime(year, month, day);
        }
      }
    } catch (_) {}
    
    return null;
  }

  String _getGl(String lang) {
    switch (lang) {
      case 'en': return 'US';
      case 'ja': return 'JP';
      case 'zh-CN': return 'CN';
      case 'de': return 'DE';
      default: return 'KR';
    }
  }

  String _getCeid(String lang) {
    switch (lang) {
      case 'en': return 'US:en';
      case 'ja': return 'JP:ja';
      case 'zh-CN': return 'CN:zh-Hans';
      case 'de': return 'DE:de';
      default: return 'KR:ko';
    }
  }

  String _getTimeParam(String period) {
    if (period.contains(' to ')) {
      final dates = period.split(' to ');
      return 'after:${dates[0]} before:${dates[1]}';
    }

    final now = DateTime.now();
    DateTime? targetDate;

    switch (period) {
      case '1 Day':
        targetDate = now.subtract(const Duration(days: 1));
        break;
      case '3 Days':
        targetDate = now.subtract(const Duration(days: 3));
        break;
      case '1 Week':
        targetDate = now.subtract(const Duration(days: 7));
        break;
      case '1 Month':
        targetDate = DateTime(now.year, now.month - 1, now.day);
        break;
      case '1 Year':
        targetDate = DateTime(now.year - 1, now.month, now.day);
        break;
      default:
        return '';
    }

    if (targetDate != null) {
      final formatted = "${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}";
      return 'after:$formatted';
    }
    return '';
  }

  Future<bool> sendEmail(String email, List<NewsArticle> articles) async {
    try {
      final String subject = 'News Crawler Report: ${articles.length}건의 기사';
      
      String htmlContent = '''
        <div style="font-family: sans-serif; max-width: 600px; margin: auto;">
          <h2 style="color: #1a73e8; border-bottom: 2px solid #1a73e8; padding-bottom: 10px;">최신 뉴스 리포트</h2>
          <ul style="list-style: none; padding: 0;">
      ''';

      for (var article in articles) {
        htmlContent += '''
          <li style="margin-bottom: 20px; padding: 15px; background: #f8f9fa; border-radius: 8px;">
            <a href="${article.url}" style="text-decoration: none; color: #1a73e8; font-weight: bold; font-size: 16px;">
              ${article.title}
            </a>
            <div style="font-size: 12px; color: #5f6368; margin-top: 5px;">
              (${article.countryName}) ${article.source} | ${article.pubDate ?? ""}
            </div>
          </li>
        ''';
      }
      htmlContent += '</ul></div>';

      // Cloud Functions 직접 호출
      final result = await FirebaseFunctions.instance.httpsCallable('sendNewsEmail').call({
        'email': email,
        'subject': subject,
        'htmlContent': htmlContent,
      });

      return result.data['success'] == true;
    } catch (e) {
      print('Cloud Functions Email Error: $e');
      return false;
    }
  }

  Future<String> getAIInsight({
    required String provider,
    required String model,
    required String apiKey,
    required String userPrompt,
    required List<NewsArticle> articles,
    Function(String progressMessage)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (apiKey.isEmpty || articles.isEmpty) return "API Credentials or Articles are missing.";
    
    int retryCount = 0;
    const int maxRetries = 2;
    
    while (retryCount <= maxRetries) {
      if (isCancelled?.call() ?? false) return "AI Analysis Cancelled.";

      try {
        final limitedArticles = articles.take(25).toList(); 
        final String articlesContext = limitedArticles.asMap().entries.map((e) {
          return "[Article ${e.key + 1}]\nTitle: ${e.value.title}\nSource: ${e.value.source}\n";
        }).join("\n");

        final prompt = """
You are a professional news analyst.
Based on the following news articles, please answer the user's request.

[Articles]
$articlesContext

[User Request]
$userPrompt

Please provide a clear and insightful response in the same language as the [User Request].
At the very end of your response, please list the article numbers you primarily referenced for this insight in the format: "Primary Sources: 1, 2, 3" (Only the numbers, separated by commas).
""";

        if (provider == 'ChatGPT') {
          onProgress?.call("Requesting analysis from ChatGPT ($model)...");
          OpenAI.apiKey = apiKey;
          final completion = await OpenAI.instance.chat.create(
            model: model, // 선택된 모델 사용
            messages: [
              OpenAIChatCompletionChoiceMessageModel(
                content: [OpenAIChatCompletionChoiceMessageContentItemModel.text(prompt)],
                role: OpenAIChatMessageRole.user,
              ),
            ],
          );
          return completion.choices.first.message.content?.first.text ?? "No response from ChatGPT.";
        } 
        
        else if (provider == 'Claude') {
          onProgress?.call("Requesting analysis from Claude ($model)...");
          final url = Uri.parse('https://api.anthropic.com/v1/messages');
          final response = await http.post(
            url,
            headers: {
              'x-api-key': apiKey,
              'anthropic-version': '2023-06-01',
              'content-type': 'application/json',
            },
            body: jsonEncode({
              'model': model, // 선택된 모델 사용
              'max_tokens': 2048,
              'messages': [{'role': 'user', 'content': prompt}]
            }),
          );
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            return data['content'][0]['text'] ?? "No response from Claude.";
          } else {
            return "Claude API Error: ${response.body}";
          }
        } 
        
        else {
          // Default to Gemini
          onProgress?.call("Requesting analysis from Gemini ($model)...");
          final genModel = GenerativeModel(model: model, apiKey: apiKey); // 선택된 모델 사용
          final content = [Content.text(prompt)];
          final response = await genModel.generateContent(content);
          return response.text ?? "AI failed to generate a response.";
        }
      } catch (e) {
        if (e.toString().contains("503") && retryCount < maxRetries) {
          retryCount++;
          onProgress?.call("Server load detected. Retrying analysis (${retryCount}/${maxRetries})...");
          await Future.delayed(Duration(milliseconds: 1500 * retryCount));
          continue;
        }
        return "AI Insight Error: $e";
      }
    }
    return "AI failed after retries.";
  }

  /// Fetches available Gemini models from Google AI API
  Future<List<String>> fetchGeminiModels(String apiKey) async {
    if (apiKey.isEmpty) return [];
    
    try {
      final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models?key=$apiKey');
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> models = data['models'] ?? [];
        
        // Filter for models that support generateContent and are Gemini models
        return models
            .where((m) => 
                (m['supportedGenerationMethods'] as List).contains('generateContent') &&
                (m['name'] as String).startsWith('models/gemini-'))
            .map((m) => (m['name'] as String).replaceFirst('models/', ''))
            .toList();
      }
    } catch (e) {
      debugPrint('Error fetching Gemini models: $e');
    }
    return [];
  }
}
