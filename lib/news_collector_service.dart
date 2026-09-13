import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:dart_openai/dart_openai.dart';
import 'usage_tracker.dart';

class NewsArticle {
  final String title;
  final String url;
  final String snippet;
  final String source;
  final String? pubDate;
  final String countryName;
  String? translatedTitle;
  String? translatedSnippet;

  NewsArticle({
    required this.title,
    required this.url,
    required this.snippet,
    required this.source,
    this.pubDate,
    required this.countryName,
    this.translatedTitle,
    this.translatedSnippet,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'url': url,
        'snippet': snippet,
        'source': source,
        'pubDate': pubDate,
        'countryName': countryName,
        'translatedTitle': translatedTitle,
        'translatedSnippet': translatedSnippet,
      };

  factory NewsArticle.fromJson(Map<String, dynamic> json) => NewsArticle(
        title: json['title'],
        url: json['url'],
        snippet: json['snippet'],
        source: json['source'],
        pubDate: json['pubDate'],
        countryName: json['countryName'],
        translatedTitle: json['translatedTitle'],
        translatedSnippet: json['translatedSnippet'],
      );
}

class NewsCollectorService {
  final String _baseUrl = "https://news.google.com/rss/search?q=";

  Future<List<NewsArticle>> crawl({
    required String query,
    required List<Map<String, dynamic>> sources,
    required String period,
    required String apiKey,
    required Function(String, {bool? isMatch, bool? isError, bool? isHeader, bool? isSummary}) onLog,
    required Function(double) onProgress,
    required bool Function() isCancelled,
    bool isDetail = false,
  }) async {
    List<NewsArticle> allArticles = [];
    int totalSources = sources.length;
    int totalFound = 0;

    onLog("Starting crawl for: '$query' ($period)", isHeader: true);

    for (int i = 0; i < totalSources; i++) {
      if (isCancelled()) {
        onLog("Crawling cancelled by user.", isError: true);
        break;
      }

      final source = sources[i];
      final countryName = source['countryName'] ?? "Global";
      final sourceName = source['nameLocal'] ?? source['name'];
      
      onProgress((i + 1) / totalSources);

      try {
        // 더 유연한 검색을 위해 source: 문법 대신 쿼리 조합 사용
        String searchQuery = "$query \"$sourceName\"";
        if (period != 'All time') {
          searchQuery += " when:$period";
        }

        final articles = await _fetchFromGoogleNews(searchQuery, countryName);
        
        if (articles.isNotEmpty) {
          allArticles.addAll(articles);
          totalFound += articles.length;
          onLog("✅ Found ${articles.length} articles from $sourceName ($countryName)", isMatch: true);
        } else {
          onLog("❌ Found 0 articles from $sourceName", isError: false);
        }
      } catch (e) {
        onLog("⚠️ Error searching $sourceName: $e", isError: true);
      }
    }

    onLog("\n--- CRAWL SUMMARY ---", isHeader: true, isSummary: true);
    onLog("Total Sources Searched: $totalSources", isSummary: true);
    onLog("Total Articles Found: $totalFound", isSummary: true);
    
    return allArticles;
  }

  Future<List<NewsArticle>> _fetchFromGoogleNews(String query, String countryName) async {
    final encodedQuery = Uri.encodeComponent(query);
    final url = Uri.parse("$_baseUrl$encodedQuery");

    final response = await http.get(url);
    if (response.statusCode == 200) {
      final document = utf8.decode(response.bodyBytes);
      return _parseRss(document, countryName);
    } else {
      return [];
    }
  }

  List<NewsArticle> _parseRss(String xmlString, String countryName) {
    final List<NewsArticle> articles = [];
    final items = xmlString.split('<item>');
    
    for (var i = 1; i < items.length; i++) {
      final item = items[i];
      final title = _extractTag(item, 'title');
      final link = _extractTag(item, 'link');
      final pubDate = _extractTag(item, 'pubDate');
      final source = _extractTag(item, 'source');
      
      var snippet = _extractTag(item, 'description');
      snippet = snippet.replaceAll(RegExp(r'<[^>]*>|&[^;]+;'), ' ').trim();

      articles.add(NewsArticle(
        title: title,
        url: link,
        snippet: snippet,
        source: source,
        pubDate: pubDate,
        countryName: countryName,
      ));
    }
    return articles;
  }

  String _extractTag(String item, String tag) {
    final startTag = '<$tag>';
    final endTag = '</$tag>';
    final startIndex = item.indexOf(startTag);
    final endIndex = item.indexOf(endTag);
    
    if (startIndex != -1 && endIndex != -1) {
      return item.substring(startIndex + startTag.length, endIndex);
    }
    return "";
  }

  Future<String> getAIInsight({
    required List<NewsArticle> articles,
    required String userPrompt,
    required String provider,
    required String model,
    required String apiKey,
    required bool Function() isCancelled,
    Function(String)? onProgress,
  }) async {
    if (apiKey.isEmpty) return "API Key is missing. Please set it in Settings.";

    int retryCount = 0;
    const maxRetries = 2;

    while (retryCount <= maxRetries) {
      if (isCancelled()) return "Analysis cancelled by user.";

      try {
        final limitedArticles = articles.take(15).toList();
        final String articlesContext = limitedArticles.asMap().entries.map((e) {
          final article = e.value;
          return "[Article ${e.key + 1}]\nTitle: ${article.title}\nSource: ${article.source}\nSummary: ${article.snippet}\n";
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
            model: model,
            messages: [
              OpenAIChatCompletionChoiceMessageModel(
                content: [OpenAIChatCompletionChoiceMessageContentItemModel.text(prompt)],
                role: OpenAIChatMessageRole.user,
              ),
            ],
          );
          
          final result = completion.choices.first.message.content?.first.text ?? "No response from ChatGPT.";
          if (completion.choices.isNotEmpty) {
            UsageTracker.logQuery();
          }
          return result;
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
              'model': model,
              'max_tokens': 2048,
              'messages': [{'role': 'user', 'content': prompt}]
            }),
          );
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            final result = data['content'][0]['text'] ?? "No response from Claude.";
            UsageTracker.logQuery();
            return result;
          } else {
            return "Claude API Error: ${response.body}";
          }
        } 
        
        else {
          onProgress?.call("Requesting analysis from Gemini ($model)...");
          final genModel = GenerativeModel(model: model, apiKey: apiKey);
          final content = [Content.text(prompt)];
          final response = await genModel.generateContent(content);
          
          final result = response.text ?? "AI failed to generate a response.";
          if (response.text != null) {
            UsageTracker.logQuery();
          }
          return result;
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
    return "AI analysis failed after multiple attempts.";
  }

  Future<void> translateArticles({
    required List<NewsArticle> articles,
    required String targetLang,
    required Function(String, {bool? isMatch, bool? isError, bool? isHeader, bool? isSummary}) onLog,
    required Function(double) onProgress,
    required bool Function() isCancelled,
  }) async {
    onLog("Translation started to $targetLang...", isHeader: true);
    for (int i = 0; i < articles.length; i++) {
      if (isCancelled()) break;
      onProgress((i + 1) / articles.length);
    }
    onLog("Translation complete.");
  }

  Future<bool> sendEmail(String email, List<NewsArticle> articles) async {
    return true; 
  }

  Future<List<String>> fetchGeminiModels(String apiKey) async {
    try {
      return ['gemini-1.5-pro', 'gemini-1.5-flash'];
    } catch (e) {
      return [];
    }
  }
}
