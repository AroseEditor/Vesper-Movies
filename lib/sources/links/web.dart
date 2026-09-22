import 'package:dio/dio.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../../core/errors.dart';

const String webUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';

class WebPage {
  const WebPage(this.url, this.body);

  final String url;
  final String body;

  Document get document => html.parse(body);

  String get origin => originOf(url);
}

class Web {
  Web({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 25),
              responseType: ResponseType.plain,
              followRedirects: true,
              maxRedirects: 8,
              validateStatus: (status) => status != null && status < 500,
              headers: const {
                'User-Agent': webUserAgent,
                'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                'Accept-Language': 'en-US,en;q=0.9',
              },
            ),
          );

  final Dio _dio;

  static String cookieHeader(Map<String, String> cookies) =>
      cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

  static Map<String, String> _headers(
    Map<String, String> headers,
    String? referer,
    Map<String, String> cookies,
  ) {
    return {
      ...headers,
      'Referer': ?referer,
      if (cookies.isNotEmpty) 'Cookie': cookieHeader(cookies),
    };
  }

  Future<WebPage> get(
    String url, {
    String? referer,
    Map<String, String> headers = const {},
    Map<String, String> cookies = const {},
    CancelToken? cancel,
  }) async {
    try {
      final response = await _dio.get<String>(
        url,
        cancelToken: cancel,
        options: Options(headers: _headers(headers, referer, cookies)),
      );
      final status = response.statusCode ?? 0;
      if (status == 404) throw const NotFound();
      if (status >= 400) throw Unavailable(status);
      return WebPage(response.realUri.toString(), response.data ?? '');
    } on DioException catch (error) {
      throw _mapped(error);
    }
  }

  Future<WebPage> post(
    String url,
    Map<String, String> form, {
    String? referer,
    Map<String, String> headers = const {},
    Map<String, String> cookies = const {},
    CancelToken? cancel,
  }) async {
    try {
      final response = await _dio.post<String>(
        url,
        data: form,
        cancelToken: cancel,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          followRedirects: false,
          validateStatus: (status) => status != null && status < 500,
          headers: _headers(headers, referer, cookies),
        ),
      );
      final location = response.headers.value('location');
      if (location != null && (response.statusCode ?? 0) >= 300) {
        return await get(Uri.parse(url).resolve(location).toString(), referer: url, cancel: cancel);
      }
      return WebPage(url, response.data ?? '');
    } on DioException catch (error) {
      throw _mapped(error);
    }
  }

  Future<Response<String>> raw(
    String url, {
    String method = 'GET',
    Map<String, String>? form,
    Map<String, String> headers = const {},
    bool follow = true,
    CancelToken? cancel,
  }) async {
    try {
      return await _dio.request<String>(
        url,
        data: form,
        cancelToken: cancel,
        options: Options(
          method: method,
          followRedirects: follow,
          contentType: form == null ? null : Headers.formUrlEncodedContentType,
          validateStatus: (status) => status != null && status < 600,
          headers: headers,
        ),
      );
    } on DioException catch (error) {
      throw _mapped(error);
    }
  }

  Future<String?> location(String url, {String? referer, CancelToken? cancel}) async {
    final response = await raw(url, follow: false, headers: {'Referer': ?referer}, cancel: cancel);
    final location = response.headers.value('location');
    return location == null ? null : Uri.parse(url).resolve(location).toString();
  }

  Future<Object?> json(
    String url, {
    String? referer,
    Map<String, String> headers = const {},
    Map<String, String> cookies = const {},
    CancelToken? cancel,
  }) async {
    try {
      final response = await _dio.get<dynamic>(
        url,
        cancelToken: cancel,
        options: Options(
          responseType: ResponseType.json,
          headers: _headers(headers, referer, cookies),
        ),
      );
      return response.data;
    } on DioException catch (error) {
      throw _mapped(error);
    }
  }

  static SourceError _mapped(DioException error) {
    if (CancelToken.isCancel(error)) return const Cancelled();
    return NetworkError(
      error.type.name,
      timedOut:
          error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout,
    );
  }
}

String absoluteUrl(String href, String base) {
  final trimmed = href.trim();
  if (trimmed.startsWith('http')) return trimmed;
  if (trimmed.startsWith('//')) return 'https:$trimmed';
  return Uri.parse(base).resolve(trimmed).toString();
}

String originOf(String url) {
  final uri = Uri.tryParse(url);
  return uri == null ? '' : '${uri.scheme}://${uri.host}';
}

String cleanText(String raw) => raw.replaceAll(RegExp(r'\s+'), ' ').trim();
