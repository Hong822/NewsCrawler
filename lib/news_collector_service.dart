import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:dart_openai/dart_openai.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'usage_tracker.dart';

class NewsArticle {
  String title;
  final String originalTitle;
  final String url;
  final String source;
  final String? pubDate;
  final String countryName;
  String snippet;
  String? translatedTitle;
  String? translatedSnippet;

  NewsArticle({
    required this.title,
    required this.originalTitle,
    required this.url,
    required this.source,
    this.pubDate,
    required this.countryName,
    this.snippet = "",
    this.translatedTitle,
    this.translatedSnippet,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'originalTitle': originalTitle,
        'url': url,
        'source': source,
        'pubDate': pubDate,
        'countryName': countryName,
        'snippet': snippet,
        'translatedTitle': translatedTitle,
        'translatedSnippet': translatedSnippet,
      };

  factory NewsArticle.fromJson(Map<String, dynamic> json) => NewsArticle(
        title: json['title'],
        originalTitle: json['originalTitle'] ?? json['title'],
        url: json['url'],
        source: json['source'],
        pubDate: json['pubDate'],
        countryName: json['countryName'],
        snippet: json['snippet'] ?? "",
        translatedTitle: json['translatedTitle'],
        translatedSnippet: json['translatedSnippet'],
      );
}

class NewsCollectorService {
  // Manual Google Translate implementation
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
      debugPrint('Manual Translation Error: $e');
      return text;
    }
  }

  Future<List<NewsArticle>> crawl({
    required String query,
    required List<Map<String, dynamic>> sources,
    required String period,
    required String apiKey,
    required Function(String, {bool? isMatch, bool? isError, bool? isHeader, bool? isSummary}) onLog,
    required Function(double) onProgress,
    required bool Function() isCancelled,
    bool isDetail = true,
  }) async {
    if (isCancelled()) return [];

    // 검색이 실행되자마자 사용량 기록 (Firestore) - 검색 속도를 위해 대기(await)하지 않음
    UsageTracker.logUsage(UsageType.search);

    final queryBatches = isDetail ? _getQueryBatches(query) : [query];

    // Get a reliable English translation for each batch
    List<String> englishQueryBatches = [];
    for (var batch in queryBatches) {
      final translatedEn = await _translateManual(batch, from: 'auto', to: 'en');
      englishQueryBatches.add(translatedEn.isNotEmpty ? translatedEn : batch);
    }

    onLog('--- SEARCH INITIATED', isHeader: true);
    onLog('* Keywords: $query');
    if (queryBatches.length > 1) {
      onLog('* Deep Search: Split into ${queryBatches.length} keyword batches');
    }
    onLog('* Target Sources: ${sources.length}');

    List<NewsArticle> allArticles = [];
    int completedSources = 0;
    int totalMatches = 0;
    int totalScanned = 0;

    for (var pub in sources) {
      if (isCancelled()) {
        onLog('\n--- Search cancelled by user.', isError: true);
        return allArticles;
      }

      final counts = await _crawlSingleSource(
        pub, query, queryBatches, englishQueryBatches, period, allArticles, onLog, isCancelled, isDetail
      );
      totalMatches += counts['matches'] ?? 0;
      totalScanned += counts['scanned'] ?? 0;
      completedSources++;
      onProgress(completedSources / sources.length);
    }

    // Sort by date descending
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
    onLog('* Sources: ${sources.length}');

    return allArticles;
  }

  Future<Map<String, int>> _crawlSingleSource(
    Map<String, dynamic> pub,
    String originalQuery,
    List<String> queryBatches,
    List<String> englishQueryBatches,
    String period,
    List<NewsArticle> results,
    Function(String message, {bool? isMatch, bool? isError, bool? isHeader, bool? isSummary}) onLog,
    bool Function() isCancelled,
    bool isDetail,
  ) async {
    final langInfo = pub['lang'] ?? pub['language'] ?? 'en';
    final lang = langInfo.toString().split('-')[0];
    final sourceNameLocal = pub['nameLocal'] ?? pub['name'];
    onLog('\n[Searching $sourceNameLocal]', isHeader: true);

    String domain = Uri.parse(pub['url']).host;
    if (domain.startsWith('www.')) domain = domain.substring(4);

    int matchCount = 0;
    int scannedCount = 0;
    
    // Step 1: Google News search with Query and Date Splitting
    final dateSegments = isDetail ? _getDateSegments(period) : [_getTimeParam(period)];
    
    for (var dateSegment in dateSegments) {
      if (isCancelled()) break;

      for (int i = 0; i < queryBatches.length; i++) {
        if (isCancelled()) break;

        final queryBatch = queryBatches[i];
        final englishQueryBatch = englishQueryBatches[i];
        
        String localQueryBatch = (lang == 'ko') ? queryBatch : englishQueryBatch;
        if (lang != 'ko' && lang != 'en') {
          final translated = await _translateManual(queryBatch, from: 'auto', to: lang);
          if (translated.isNotEmpty) localQueryBatch = translated;
        }

        final fullQuery = '$localQueryBatch site:$domain $dateSegment';
        onLog('* Search [${dateSegments.indexOf(dateSegment) + 1}/${dateSegments.length}] Language [${lang.toUpperCase()}]: "$localQueryBatch"');

        final googleRssUrl = Uri.https('news.google.com', '/rss/search', {
          'q': fullQuery,
          'hl': lang,
          'gl': _getGl(langInfo),
          'ceid': _getCeid(langInfo),
        });

        final counts = await _fetchAndProcessRssWithCount(
          url: googleRssUrl,
          sourceName: sourceNameLocal,
          countryName: pub['countryName'] ?? "Unknown",
          query: queryBatch,
          englishQuery: englishQueryBatch,
          localQuery: localQueryBatch,
          period: period,
          results: results,
          onLog: onLog,
        );
        matchCount += counts['matches'] ?? 0;
        scannedCount += counts['scanned'] ?? 0;
        
        await Future.delayed(const Duration(milliseconds: 600));
      }
    }

    onLog('$sourceNameLocal Search Finished - $matchCount match(es)');
    return {'matches': matchCount, 'scanned': scannedCount};
  }

  List<String> _getQueryBatches(String query, {int batchSize = 3}) {
    if (!(query.toLowerCase().contains(' or ') || query.toLowerCase().contains(' || '))) {
      return [query];
    }
    
    final terms = query.split(RegExp(r' or | \|\| ', caseSensitive: false))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    
    if (terms.length <= batchSize) return [query];

    List<String> batches = [];
    for (var i = 0; i < terms.length; i += batchSize) {
      final end = (i + batchSize < terms.length) ? i + batchSize : terms.length;
      batches.add(terms.sublist(i, end).join(' OR '));
    }
    return batches;
  }

  List<String> _getDateSegments(String period) {
    DateTime now = DateTime.now();
    DateTime startDate;
    int segments = 1;

    if (period.contains(' to ')) {
      final dates = period.split(' to ');
      startDate = DateTime.parse(dates[0]);
      DateTime endDate = DateTime.parse(dates[1]);
      final diffDays = endDate.difference(startDate).inDays;
      if (diffDays <= 7) segments = 1;
      else if (diffDays <= 31) segments = 3;
      else segments = (diffDays / 30).ceil().clamp(1, 10);
    } else {
      switch (period) {
        case '1 Day': startDate = now.subtract(const Duration(days: 1)); segments = 1; break;
        case '3 Days': startDate = now.subtract(const Duration(days: 3)); segments = 1; break;
        case '1 Week': startDate = now.subtract(const Duration(days: 7)); segments = 2; break;
        case '1 Month': startDate = DateTime(now.year, now.month - 1, now.day); segments = 4; break;
        case '1 Year': startDate = DateTime(now.year - 1, now.month, now.day); segments = 12; break;
        default: return [_getTimeParam(period)];
      }
    }

    if (segments <= 1) return [_getTimeParam(period)];

    List<String> dateQueries = [];
    DateTime endDate = period.contains(' to ') ? DateTime.parse(period.split(' to ')[1]) : now;
    final totalDuration = endDate.difference(startDate).inMilliseconds;
    final segmentDuration = totalDuration ~/ segments;

    for (int i = 0; i < segments; i++) {
      DateTime s = startDate.add(Duration(milliseconds: segmentDuration * i));
      DateTime e = startDate.add(Duration(milliseconds: segmentDuration * (i + 1)));
      if (i == segments - 1) e = endDate;

      final sStr = "${s.year}-${s.month.toString().padLeft(2, '0')}-${s.day.toString().padLeft(2, '0')}";
      final eStr = "${e.year}-${e.month.toString().padLeft(2, '0')}-${e.day.toString().padLeft(2, '0')}";
      dateQueries.add("after:$sStr before:$eStr");
    }

    return dateQueries;
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
        final result = await FirebaseFunctions.instance.httpsCallable('fetchRssData').call({'url': url.toString()});
        if (result.data['success'] == true) {
          xmlBody = result.data['data'];
        } else {
          return {'matches': 0, 'scanned': 0};
        }
      } else {
        final res = await http.get(url).timeout(const Duration(seconds: 15));
        if (res.statusCode != 200) return {'matches': 0, 'scanned': 0};
        xmlBody = utf8.decode(res.bodyBytes, allowMalformed: true);
      }

      final document = XmlDocument.parse(xmlBody);
      var items = document.findAllElements('item').toList();
      if (items.isEmpty) {
        items = document.findAllElements('entry').toList();
      }

      if (items.isEmpty) return {'matches': 0, 'scanned': 0};
      
      int matchCount = 0;
      int scannedCount = items.length;

      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        String rawTitle = item.findElements('title').isNotEmpty ? item.findElements('title').first.text : 'No Title';
        final link = item.findElements('link').isNotEmpty ? item.findElements('link').first.text : '';
        final rawDateStr = item.findElements('pubDate').isNotEmpty ? item.findElements('pubDate').first.text : null;
        final date = _formatRssDate(rawDateStr) ?? 'Unknown Date';

        String rawDescription = "";
        if (item.findElements('description').isNotEmpty) {
          rawDescription = item.findElements('description').first.text;
        } else if (item.findElements('summary').isNotEmpty) {
          rawDescription = item.findElements('summary').first.text;
        }
        final cleanSnippet = _stripHtml(rawDescription);

        bool isMatch = _checkMatch(rawTitle, query) || 
                      _checkMatch(rawTitle, localQuery) ||
                      _checkMatch(rawTitle, englishQuery) ||
                      _checkMatch(cleanSnippet, query) ||
                      _checkMatch(cleanSnippet, localQuery) ||
                      _checkMatch(cleanSnippet, englishQuery);

        if (isMatch && !_isWithinPeriod(rawDateStr, period)) {
          isMatch = false;
        }

        final logIndex = i + 1;
        if (isMatch) {
          if (results.any((a) => a.url == link)) {
            continue;
          }

          onLog('[$logIndex] $rawTitle - MATCH', isMatch: true);
          if (rawTitle.contains(' - $sourceName')) rawTitle = rawTitle.replaceAll(' - $sourceName', '').trim();
          results.add(NewsArticle(
            title: rawTitle,
            originalTitle: rawTitle,
            url: link,
            source: sourceName,
            pubDate: date,
            countryName: countryName,
            snippet: cleanSnippet,
          ));
          matchCount++;
        } else {
          onLog('[$logIndex] $rawTitle - MISMATCH', isMatch: false);
        }
      }
      return {'matches': matchCount, 'scanned': scannedCount};
    } catch (e) {
      return {'matches': 0, 'scanned': 0};
    }
  }

  String _stripHtml(String html) {
    if (html.isEmpty) return "";
    return html_parser.parse(html).body?.text ?? "";
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
    required Function(String, {bool? isMatch, bool? isError, bool? isHeader, bool? isSummary}) onLog,
    required Function(double) onProgress,
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
    if (pubDateStr == null || period == '' || period == 'All time') return true;
    try {
      final pubDate = _parseRssDate(pubDateStr);
      if (pubDate == null) return true;

      if (period.contains(' to ')) {
        final dates = period.split(' to ');
        final start = DateTime.parse(dates[0]);
        final end = DateTime.parse(dates[1]).add(const Duration(days: 1));
        return pubDate.isAfter(start.subtract(const Duration(seconds: 1))) && pubDate.isBefore(end);
      }

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
    DateTime? parsed = DateTime.tryParse(dateStr);
    if (parsed != null) return parsed;
    try {
      final parts = dateStr.split(' ');
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
      case '1 Day': targetDate = now.subtract(const Duration(days: 1)); break;
      case '3 Days': targetDate = now.subtract(const Duration(days: 3)); break;
      case '1 Week': targetDate = now.subtract(const Duration(days: 7)); break;
      case '1 Month': targetDate = DateTime(now.year, now.month - 1, now.day); break;
      case '1 Year': targetDate = DateTime(now.year - 1, now.month, now.day); break;
      default: return '';
    }
    if (targetDate != null) {
      return 'after:${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}';
    }
    return '';
  }

  Future<bool> sendEmail(String email, List<NewsArticle> articles) async {
    try {
      final String subject = 'News Crawler Report: ${articles.length} articles';
      String htmlContent = '<div style="font-family: sans-serif;"><h2>Latest News Report</h2><ul>';
      for (var article in articles) {
        htmlContent += '<li style="margin-bottom: 15px;"><a href="${article.url}"><b>${article.title}</b></a><br>(${article.countryName}) ${article.source} | ${article.pubDate ?? ""}</li>';
      }
      htmlContent += '</ul></div>';
      final result = await FirebaseFunctions.instance.httpsCallable('sendNewsEmail').call({
        'email': email,
        'subject': subject,
        'htmlContent': htmlContent,
      });
      return result.data['success'] == true;
    } catch (e) {
      debugPrint('Email Error: $e');
      return false;
    }
  }

  Future<String> getAIInsight({
    required String provider,
    required String model,
    required String apiKey,
    required String userPrompt,
    required List<NewsArticle> articles,
    required bool Function() isCancelled,
    Function(String)? onProgress,
  }) async {
    if (apiKey.isEmpty || articles.isEmpty) return "API Credentials or Articles are missing.";

    // AI 분석 시도 즉시 사용량 기록 (Firestore)
    UsageTracker.logUsage(UsageType.ai);

    int retryCount = 0;
    const int maxRetries = 2;
    while (retryCount <= maxRetries) {
      if (isCancelled()) return "AI Analysis Cancelled.";
      try {
        final limitedArticles = articles.take(25).toList(); 
        final String articlesContext = limitedArticles.asMap().entries.map((e) {
          final article = e.value;
          return "[Article ${e.key + 1}]\nTitle: ${article.title}\nSource: ${article.source}\nSummary: ${article.snippet}\n";
        }).join("\n");
        final prompt = "You are a professional news analyst.\nBased on the following news articles, please answer the user's request.\n\n[Articles]\n$articlesContext\n\n[User Request]\n$userPrompt\n\nPlease provide a clear and insightful response in the same language as the [User Request].\nAt the very end of your response, please list the article numbers you primarily referenced for this insight in the format: \"Primary Sources: 1, 2, 3\"";

        if (provider == 'ChatGPT') {
          onProgress?.call("Requesting analysis from ChatGPT ($model)...");
          OpenAI.apiKey = apiKey;
          final completion = await OpenAI.instance.chat.create(
            model: model,
            messages: [OpenAIChatCompletionChoiceMessageModel(content: [OpenAIChatCompletionChoiceMessageContentItemModel.text(prompt)], role: OpenAIChatMessageRole.user)],
          );
          return completion.choices.first.message.content?.first.text ?? "No response from ChatGPT.";
        } else if (provider == 'Claude') {
          onProgress?.call("Requesting analysis from Claude ($model)...");
          final url = Uri.parse('https://api.anthropic.com/v1/messages');
          final response = await http.post(url, headers: {'x-api-key': apiKey, 'anthropic-version': '2023-06-01', 'content-type': 'application/json'}, body: jsonEncode({'model': model, 'max_tokens': 2048, 'messages': [{'role': 'user', 'content': prompt}]}));
          if (response.statusCode == 200) {
            return jsonDecode(response.body)['content'][0]['text'] ?? "No response from Claude.";
          } else { return "Claude API Error: ${response.body}"; }
        } else {
          onProgress?.call("Requesting analysis from Gemini ($model)...");
          final genModel = GenerativeModel(model: model, apiKey: apiKey);
          final response = await genModel.generateContent([Content.text(prompt)]);
          return response.text ?? "AI failed to generate a response.";
        }
      } catch (e) {
        if (e.toString().contains("503") && retryCount < maxRetries) {
          retryCount++;
          onProgress?.call("Server load detected. Retrying ($retryCount/$maxRetries)...");
          await Future.delayed(Duration(milliseconds: 1500 * retryCount));
          continue;
        }
        return "AI Insight Error: $e";
      }
    }
    return "AI failed after retries.";
  }

  Future<List<String>> fetchGeminiModels(String apiKey) async {
    if (apiKey.isEmpty) return [];
    try {
      final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models?key=$apiKey');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List<dynamic> models = jsonDecode(response.body)['models'] ?? [];
        return models.where((m) => (m['supportedGenerationMethods'] as List).contains('generateContent') && (m['name'] as String).startsWith('models/gemini-')).map((m) => (m['name'] as String).replaceFirst('models/', '')).toList();
      }
    } catch (e) { debugPrint('Error fetching models: $e'); }
    return [];
  }
}
