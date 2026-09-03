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
  }) async {
    if (isCancelled?.call() ?? false) return [];

    // Get a reliable English translation
    String englishQuery = query;
    final translatedEn = await _translateManual(query, from: 'auto', to: 'en');
    if (translatedEn.isNotEmpty && translatedEn.toLowerCase() != query.toLowerCase()) {
      englishQuery = translatedEn;
      onLog('* [en] 글로벌 키워드 확정 (Google번역): "$query" -> "$englishQuery"');
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

    onLog('--- 검색시작', isHeader: true);
    onLog('* 검색어: $query');
    if (englishQuery != query) onLog('* 글로벌 통합 키워드: $englishQuery');
    onLog('* 대상 언론사: ${selectedPubs.length}개');

    List<NewsArticle> allArticles = [];
    int completedSources = 0;
    int totalMatches = 0;

    for (var pub in selectedPubs) {
      if (isCancelled?.call() ?? false) {
        onLog('\n--- 사용자에 의해 검색이 중단되었습니다.', isError: true);
        return allArticles;
      }

      final matches = await _crawlSingleSource(
        pub, query, englishQuery, period, allArticles, onLog
      );
      totalMatches += matches;
      completedSources++;
      onProgress(completedSources / selectedPubs.length);
    }

    onLog('\n검색 완료 - 일치 $totalMatches 건', isHeader: true, isSummary: true);
    return allArticles;
  }

  Future<int> _crawlSingleSource(
    Map<String, dynamic> pub,
    String query,
    String englishQuery,
    String period,
    List<NewsArticle> results,
    Function(String message, {bool? isMatch, bool? isError, bool? isHeader, bool? isSummary}) onLog,
  ) async {
    final lang = pub['lang'].toString().split('-')[0];
    final sourceNameLocal = pub['nameLocal'] ?? pub['name'];
    onLog('\n[$sourceNameLocal 검색 시작]', isHeader: true);

    String localQuery = (lang == 'ko') ? query : englishQuery;
    
    if (lang != 'ko' && lang != 'en') {
      final translated = await _translateManual(query, from: 'auto', to: lang);
      if (translated.isNotEmpty && translated.toLowerCase() != query.toLowerCase()) {
        localQuery = translated;
        onLog('* [$lang] 현지어 번역 성공 (Google): "$localQuery"');
      }
    }

    String domain = Uri.parse(pub['url']).host;
    if (domain.startsWith('www.')) domain = domain.substring(4);

    final timeParam = _getTimeParam(period);
    
    // Step 1: Try direct RSS if available
    int matchCount = 0;
    bool directSuccess = false;

    if (pub['rss'] != null) {
      final List<String> rssUrls = [];
      if (pub['rss']['url'] != null) rssUrls.add(pub['rss']['url']);
      if (pub['rss']['urls'] != null) rssUrls.addAll((pub['rss']['urls'] as List).cast<String>());

      if (rssUrls.isNotEmpty) {
        onLog('* [RSS] 직접 연결 시도 (${rssUrls.length}개 피드)');
        
        for (var rssUrl in rssUrls) {
          final count = await _fetchAndProcessRssWithCount(
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
          matchCount += count;
        }
        
        if (matchCount > 0) {
          directSuccess = true;
          onLog('* [RSS] 직접 연결 성공하여 기사 수집 완료 (총 $matchCount건)');
        } else {
          onLog('* [RSS] 직접 연결 결과가 없어 Google Fallback 시도');
        }
      }
    }

    // Step 2: Fallback to Google News search
    if (!directSuccess) {
      final fullQuery = '$localQuery site:$domain $timeParam';
      onLog('* 전송 쿼리 (Google): "$fullQuery"');

      final googleRssUrl = Uri.https('news.google.com', '/rss/search', {
        'q': fullQuery,
        'hl': lang,
        'gl': _getGl(pub['lang']),
        'ceid': _getCeid(pub['lang']),
      });

      matchCount = await _fetchAndProcessRssWithCount(
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
    }

    onLog('$sourceNameLocal 검색 완료 - 일치 $matchCount건');
    return matchCount;
  }

  Future<int> _fetchAndProcessRssWithCount({
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
          onLog('* [CORS 우회] 데이터 수집 실패: ${result.data['error']}', isError: true);
          return 0;
        }
      } else {
        // PC/모바일에서는 직접 요청이 가능합니다.
        final res = await http.get(url).timeout(const Duration(seconds: 15));
        if (res.statusCode != 200) return 0;
        // 인코딩 감지 오류 방지를 위해 직접 UTF-8로 디코딩합니다.
        xmlBody = utf8.decode(res.bodyBytes, allowMalformed: true);
      }

      // Improved XML detection
      final trimmedBody = xmlBody.trim();
      if (!trimmedBody.startsWith('<') || (!trimmedBody.contains('<rss') && !trimmedBody.contains('<feed') && !trimmedBody.contains('<channel'))) {
        onLog('* [RSS] 응답이 유효한 XML 형식이 아닙니다. (내용 일부: ${trimmedBody.length > 100 ? trimmedBody.substring(0, 100) : trimmedBody})', isError: true);
        return 0;
      }

      final document = XmlDocument.parse(xmlBody);
      // Support both RSS (<item>) and Atom (<entry>) tags
      var items = document.findAllElements('item').toList();
      if (items.isEmpty) {
        items = document.findAllElements('entry').toList();
      }

      if (items.isEmpty) {
        onLog('* [RSS] XML 내에서 기사 항목(<item> 또는 <entry>)을 찾을 수 없습니다.', isError: true);
        return 0;
      }
      
      Map<String, List<XmlElement>> itemsByDate = {};
      for (var item in items) { // 100개 제한 제거
        final dateStr = item.findElements('pubDate').isNotEmpty ? _formatRssDate(item.findElements('pubDate').first.text) ?? 'Unknown Date' : 'Unknown Date';
        itemsByDate.putIfAbsent(dateStr, () => []).add(item);
      }

      int matchCount = 0;
      for (var date in itemsByDate.keys) {
        final dateItems = itemsByDate[date]!;
        onLog('- 기사 날짜: $date 총 ${dateItems.length}건');
        
        for (int i = 0; i < dateItems.length; i++) {
          final item = dateItems[i];
          String rawTitle = item.findElements('title').isNotEmpty ? item.findElements('title').first.text : 'No Title';
          final link = item.findElements('link').isNotEmpty ? item.findElements('link').first.text : '';
          
          bool isMatch = _checkMatch(rawTitle, query) || 
                        _checkMatch(rawTitle, localQuery) ||
                        _checkMatch(rawTitle, englishQuery);

          if (isMatch && !_isWithinPeriod(item.findElements('pubDate').first.text, period)) {
            isMatch = false;
          }

          final logIndex = i + 1;
          if (isMatch) {
            onLog('[$logIndex] $rawTitle - 일치', isMatch: true);
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
            onLog('[$logIndex] $rawTitle - 불일치', isMatch: false);
          }
        }
      }
      return matchCount;
    } catch (e) {
      onLog('* [RSS] 처리 중 예외 발생 ($sourceName): $e', isError: true);
      return 0;
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
    
    onLog('\n[번역 작업] 수집된 기사 번역 중 ($targetLang)...', isHeader: true);
    int translatedCount = 0;
    
    for (var article in articles) {
      if (isCancelled()) {
        onLog('\n--- 번역이 중단되었습니다.', isError: true);
        return;
      }

      try {
        final translated = await _translateManual(article.originalTitle, to: targetLang);
        article.title = translated;
      } catch (e) {
        onLog('번역 중 오류 발생: $e', isError: true);
      }
      
      translatedCount++;
      onProgress(translatedCount / articles.length);
    }
    onLog('번역 완료');
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
    if (pubDateStr == null || period == '' || period == 'Dynamic') return true;
    try {
      final pubDate = DateTime.tryParse(pubDateStr) ?? DateTime.now();
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
    switch (period) {
      case '1 Day': return 'when:1d';
      case '3 Days': return 'when:3d';
      case '1 Week': return 'when:7d';
      case '1 Month': return 'when:1m';
      case '1 Year': return 'when:1y';
      default: return '';
    }
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
    required String apiKey,
    required String userPrompt,
    required List<NewsArticle> articles,
  }) async {
    if (apiKey.isEmpty || articles.isEmpty) return "API Key or Articles are missing.";
    
    try {
      // Updated to Gemini 3.6 Flash as recommended by Google API error message
      final model = GenerativeModel(model: 'gemini-3.6-flash', apiKey: apiKey);
      
      // Limit to top 30 articles for the more capable 3.6 model
      final limitedArticles = articles.take(30).toList();
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

Please provide a clear and insightful response in Korean.
""";

      final content = [Content.text(prompt)];
      final response = await model.generateContent(content);
      return response.text ?? "AI failed to generate a response.";
    } catch (e) {
      return "AI Insight Error: $e";
    }
  }
}
