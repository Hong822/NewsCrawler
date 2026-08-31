import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml.dart';
import 'package:flutter/services.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:url_launcher/url_launcher.dart';

class NewsArticle {
  String title;
  final String originalTitle;
  final String url;
  final String source;
  final String? pubDate;

  NewsArticle({
    required this.title,
    required this.originalTitle,
    required this.url,
    required this.source,
    this.pubDate,
  });
}

class NewsCrawlerService {
  GenerativeModel? _model;

  void _initAI(String apiKey) {
    if (apiKey.isEmpty) return;
    _model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: apiKey);
  }

  Future<List<NewsArticle>> crawl({
    required String query,
    required List<String> sources,
    required String period,
    required String apiKey,
  }) async {
    _initAI(apiKey);
    
    final String response = await rootBundle.loadString('assets/news_sources.json');
    final data = json.decode(response);
    
    Map<String, List<Map<String, dynamic>>> countryGroups = {};
    for (var country in data['countries']) {
      final lang = country['language'];
      final publishers = (country['publishers'] as List).cast<Map<String, dynamic>>();
      for (var id in sources) {
        final pub = publishers.firstWhere((p) => p['id'] == id, orElse: () => {});
        if (pub.isNotEmpty) {
          countryGroups.putIfAbsent(lang, () => []).add(pub);
        }
      }
    }

    List<NewsArticle> allArticles = [];
    List<Future<void>> crawlTasks = [];

    for (var lang in countryGroups.keys) {
      String localQuery = query;
      if (lang != 'ko' && _model != null) {
        localQuery = await _translateQuery(query, lang);
      }

      for (var pub in countryGroups[lang]!) {
        crawlTasks.add(() async {
          final domain = Uri.parse(pub['url']).host;
          final timeParam = _getTimeParam(period);
          final fullQuery = '$localQuery site:$domain $timeParam';
          
          final rssUrl = Uri.https('news.google.com', '/rss/search', {
            'q': fullQuery,
            'hl': lang,
            'ceid': _getCeid(lang),
          });

          try {
            final res = await http.get(rssUrl);
            if (res.statusCode == 200) {
              final document = XmlDocument.parse(res.body);
              final items = document.findAllElements('item').take(100);
              
              for (var item in items) {
                String rawTitle = item.findElements('title').first.text;
                final sourceName = item.findElements('source').first.text;
                final pubDateStr = item.findElements('pubDate').isNotEmpty 
                    ? item.findElements('pubDate').first.text 
                    : null;
                
                // Match check: with original query or translated local query
                bool isMatch = rawTitle.toLowerCase().contains(query.toLowerCase()) ||
                              rawTitle.toLowerCase().contains(localQuery.toLowerCase());

                if (isMatch) {
                  print('($sourceName) $rawTitle - [일치] 검색어 $query가 일치');
                  
                  // Remove " - Source Name" from the title
                  if (rawTitle.contains(' - $sourceName')) {
                    rawTitle = rawTitle.replaceAll(' - $sourceName', '').trim();
                  } else if (rawTitle.contains(' | $sourceName')) {
                    rawTitle = rawTitle.replaceAll(' | $sourceName', '').trim();
                  }

                  allArticles.add(NewsArticle(
                    title: rawTitle,
                    originalTitle: rawTitle,
                    url: item.findElements('link').first.text,
                    source: sourceName,
                    pubDate: _formatRssDate(pubDateStr),
                  ));
                } else {
                  print('($sourceName) $rawTitle - [불일치]');
                }
              }
            }
          } catch (e) {
            print('Error crawling ${pub['name']}: $e');
          }
        }());
      }
    }

    await Future.wait(crawlTasks);

    // AI: Translate all foreign titles to Korean in one batch
    if (_model != null && allArticles.isNotEmpty) {
      allArticles = await _batchTranslateTitles(allArticles);
    }

    return allArticles;
  }

  Future<String> _translateQuery(String query, String targetLang) async {
    try {
      final prompt = 'Translate this search keyword to "$targetLang". Output only the translation: "$query"';
      final response = await _model!.generateContent([Content.text(prompt)]);
      return response.text?.trim() ?? query;
    } catch (e) {
      return query;
    }
  }

  Future<List<NewsArticle>> _batchTranslateTitles(List<NewsArticle> articles) async {
    try {
      final titles = articles.map((a) => a.originalTitle).toList();
      final prompt = '''
      Translate the following news titles into Korean. 
      Provide the result as a JSON array of strings in the same order.
      
      Titles: ${json.encode(titles)}
      
      Output format: ["한국어 제목 1", "한국어 제목 2", ...]
      ''';

      final response = await _model!.generateContent([Content.text(prompt)]);
      final cleanJson = response.text?.replaceAll('```json', '').replaceAll('```', '').trim() ?? '[]';
      final List<dynamic> translatedTitles = json.decode(cleanJson);

      for (int i = 0; i < articles.length && i < translatedTitles.length; i++) {
        articles[i].title = translatedTitles[i].toString();
      }
    } catch (e) {
      print('Batch translation failed: $e');
    }
    return articles;
  }

  String? _formatRssDate(String? dateStr) {
    if (dateStr == null) return null;
    try {
      // Input example: "Mon, 31 Aug 2026 13:46:40 GMT"
      // Simple parsing to YYYY-MM-DD
      final parts = dateStr.split(' ');
      if (parts.length >= 4) {
        final day = parts[1];
        final month = parts[2];
        final year = parts[3];
        return '$year-$month-$day';
      }
      return dateStr;
    } catch (e) {
      return dateStr;
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
      final String subject = 'News Crawler: 최신 뉴스 요약 리포트';
      String body = '수집된 최신 뉴스 헤드라인입니다:\n\n';
      
      for (var article in articles) {
        body += '■ ${article.title}\n';
        body += '   원문 보기: ${article.url}\n';
        body += '   출처: ${article.source}\n\n';
      }

      final Uri emailLaunchUri = Uri(
        scheme: 'mailto',
        path: email,
        query: _encodeQueryParameters({
          'subject': subject,
          'body': body,
        }),
      );

      // We use internal URI launching, url_launcher should be imported
      return await launchUrl(emailLaunchUri);
    } catch (e) {
      print('Email Error: $e');
      rethrow;
    }
  }

  String? _encodeQueryParameters(Map<String, String> params) {
    return params.entries
        .map((MapEntry<String, String> e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
  }
}
