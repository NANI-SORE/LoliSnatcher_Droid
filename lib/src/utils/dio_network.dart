// ignore_for_file: invalid_use_of_internal_member

import 'dart:async';

import 'package:dio/dio.dart';

import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/services/local_network_permission.dart';
import 'package:lolisnatcher/src/services/cloudflare_refresh.dart';
import 'package:lolisnatcher/src/utils/content_policy.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

class _HeadlessRecovery {
  RequestOptions? lastRequest;
  bool replaying = false;
}

class DioNetwork {
  DioNetwork._();

  static final Object _cancelTokenZoneKey = Object();
  static final Object _headlessRecoveryZoneKey = Object();
  static const _headlessRetried = 'headlessCookieRetry';

  static Future<T> runWithHeadlessRecovery<T>(
    Future<T> Function() action, {
    CancelToken? cancelToken,
    bool Function(T)? failed,
  }) {
    final recovery = _HeadlessRecovery();
    return runZoned(
      () async {
        Future<bool> recoverParsingFailure() async {
          final request = recovery.lastRequest;
          if (request == null || request.extra[_headlessRetried] == true || recovery.replaying) return false;
          request.extra[_headlessRetried] = true;
          final refreshed = await _refreshRequestCookies(request);
          recovery.replaying = refreshed;
          return refreshed;
        }

        final T result;
        try {
          result = await action();
        } catch (_) {
          if (await recoverParsingFailure()) return action();
          rethrow;
        }
        if (failed?.call(result) == true && await recoverParsingFailure()) return action();
        return result;
      },
      zoneValues: {
        _headlessRecoveryZoneKey: recovery,
        _cancelTokenZoneKey: ?cancelToken,
      },
    );
  }

  static String _requestUserAgent(RequestOptions request, [String? fallback]) =>
      request.headers.entries
          .where((entry) => entry.key.toLowerCase() == 'user-agent')
          .firstOrNull
          ?.value
          ?.toString() ??
      fallback ??
      Tools.browserUserAgent;

  static Future<bool> _refreshRequestCookies(RequestOptions request) async {
    if (request.cancelToken?.isCancelled == true ||
        !PlatformExt.hasWebviewSupport ||
        !ContentPolicy.canOpenWebview ||
        Tools.isTestMode) {
      return false;
    }
    final refreshed = await CloudflareRefresh.refresh(
      request.method == 'GET' || request.method == 'HEAD' ? request.uri : Uri.parse(request.uri.origin),
      _requestUserAgent(request),
      cancelToken: request.cancelToken,
      requireNewClearance: false,
      useCooldown: false,
    );
    return refreshed && request.cancelToken?.isCancelled != true;
  }

  /// Shares cancellation with nested requests, including handler setup and parsing.
  /// The zone keeps concurrent operations outside this scope independent.
  static Future<T> runWithCancellation<T>(CancelToken cancelToken, Future<T> Function() action) {
    return runZoned(action, zoneValues: {_cancelTokenZoneKey: cancelToken});
  }

  /// Prevent side effects after asynchronous work in a cancelled request scope.
  static void throwIfCancelled() {
    _requestCancelToken(null);
  }

  static CancelToken? _requestCancelToken(CancelToken? cancelToken) {
    final scopedToken = Zone.current[_cancelTokenZoneKey] as CancelToken?;
    if (scopedToken?.isCancelled == true) throw scopedToken!.cancelError!;
    final token = cancelToken ?? scopedToken;
    if (token?.isCancelled == true) throw token!.cancelError!;
    return token;
  }

  static Dio getClient({
    String? baseUrl,
    bool skipLogging = false,
  }) {
    final dio = Dio();

    final settingsHandler = SettingsHandler.instance;
    // final proxyType = ProxyType.fromName(settingsHandler.proxyType);
    // if (settingsHandler.useHttp2 &&
    //     (proxyType.isDirect || (proxyType.isSystem && systemProxyAddress.isEmpty) || getProxyConfigAddress().isEmpty)) {
    //   // dio.httpClientAdapter = NativeAdapter();
    //   dio.httpClientAdapter = Http2Adapter(
    //     ConnectionManager(
    //       idleTimeout: const Duration(seconds: 30),
    //     ),
    //   );
    // }

    dio.options.baseUrl = baseUrl ?? '';
    // dio.options.connectTimeout = Duration(seconds: 10);
    // dio.options.receiveTimeout = Duration(seconds: 30);
    // dio.options.sendTimeout = Duration(seconds: 10);

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (!await LocalNetworkPermission.ensureForUrl(options.uri.toString())) {
            handler.reject(
              DioException(
                requestOptions: options,
                error: 'Local network permission denied',
              ),
            );
            return;
          }
          handler.next(options);
        },
      ),
    );

    if (!skipLogging) {
      dio.interceptors.add(Logger.dioInterceptor!);
      dio.interceptors.add(settingsHandler.alice.getDioInterceptor());
    }
    cookieInterceptor(dio);
    if (Zone.current[_headlessRecoveryZoneKey] != null) captchaInterceptor(dio, headlessOnly: true);

    return dio;
  }

  static Options mergeOptions(Options? options, Map<String, dynamic>? headers) {
    final usedOptions = options ?? defaultOptions;
    return usedOptions.copyWith(
      headers: {
        ...?headers ?? usedOptions.headers ?? defaultOptions.headers,
      },
    );
  }

  /// used to force alice to intercept query params, because if they are not separate from the url - dio doesn't give them to alice
  static Map<String, dynamic> separateUrlAndQueryParams(String url, Map<String, dynamic>? givenQueryParams) {
    final temp = Uri.tryParse(url);
    if (temp == null) {
      throw Exception('Url parsing failed: $url');
    }

    final String cleanUrl = temp.replace(queryParameters: {}).toString();
    final Map<String, dynamic> queryParams = {
      ...temp.queryParameters,
      ...?givenQueryParams,
    };

    // TODO create a separate class for this?
    return {
      'url': Uri.encodeFull(cleanUrl).replaceAll('%25', '%'),
      'query': queryParams.isEmpty ? null : queryParams,
    };
  }

  static Dio captchaInterceptor(
    Dio client, {
    String? customUserAgent,
    bool headlessOnly = false,
  }) {
    final recovery = Zone.current[_headlessRecoveryZoneKey] as _HeadlessRecovery?;
    // Scoped reads already have recovery installed by getClient. Keep legacy
    // custom interceptors from opening a screen or duplicating the retry.
    if (recovery != null && !headlessOnly) return client;
    Future<Response?> recover(Response? response, RequestOptions request, {bool requestFailed = false}) async {
      final cancelToken = request.cancelToken;
      if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
      if (request.headers[Tools.captchaCheckHeader] == 'done') return null;
      final userAgent = _requestUserAgent(request, customUserAgent);
      bool silent = false;
      final bool recovered;
      if (headlessOnly) {
        if (recovery?.replaying == true || request.extra[_headlessRetried] == true) return null;
        final status = response?.statusCode;
        if (!requestFailed &&
            response != null &&
            status != null &&
            status >= 200 &&
            status < 300 &&
            !CloudflareRefresh.isChallenge(response) &&
            !Tools.hasCaptchaStrings(request.uri.host, response.data.toString())) {
          return null;
        }
        request.extra[_headlessRetried] = true;
        recovered = await _refreshRequestCookies(request);
      } else {
        recovered = await Tools.checkForCaptcha(
          response,
          response?.realUri ?? request.uri,
          customUserAgent: userAgent,
          cancelToken: cancelToken,
          onSilentRefresh: () => silent = true,
        );
      }
      if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
      if (!recovered) return null;
      final oldCookie = request.headers['Cookie'] as String? ?? '';
      final newCookie = await Tools.getCookies(request.uri.toString());
      final headers = {
        for (final entry in request.headers.entries)
          if (entry.key.toLowerCase() != 'user-agent' && entry.key.toLowerCase() != 'cookie') entry.key: entry.value,
        'Cookie': mergeCookies(oldCookie, newCookie, discardClearance: true),
        'User-Agent': userAgent,
        Tools.captchaCheckHeader: silent ? 'silent' : 'done',
      };
      // Preserve response type, timeouts, progress callbacks, and cancellation.
      return client.fetch(
        request.copyWith(
          headers: headers,
          extra: {...request.extra, if (headlessOnly) _headlessRetried: true},
          connectTimeout: headlessOnly ? request.connectTimeout ?? const Duration(seconds: 15) : request.connectTimeout,
          receiveTimeout: headlessOnly ? request.receiveTimeout ?? const Duration(seconds: 15) : request.receiveTimeout,
          sendTimeout: headlessOnly ? request.sendTimeout ?? const Duration(seconds: 15) : request.sendTimeout,
        ),
      );
    }

    client.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          if (recovery != null) {
            recovery.lastRequest = request;
            request.connectTimeout ??= const Duration(seconds: 15);
            request.receiveTimeout ??= const Duration(seconds: 15);
            request.sendTimeout ??= const Duration(seconds: 15);
          }
          handler.next(request);
        },
        onResponse: (response, handler) async {
          try {
            final recovered = await recover(response, response.requestOptions);
            if (recovered != null) return handler.resolve(recovered);
            if (headlessOnly &&
                ((response.statusCode ?? 0) < 200 ||
                    (response.statusCode ?? 0) >= 300 ||
                    CloudflareRefresh.isChallenge(response) ||
                    Tools.hasCaptchaStrings(response.requestOptions.uri.host, response.data.toString()))) {
              return handler.reject(
                DioException(
                  requestOptions: response.requestOptions,
                  response: response,
                  type: DioExceptionType.badResponse,
                  error: 'Request failed after headless cookie recovery',
                ),
              );
            }
          } on DioException catch (error) {
            return handler.reject(error);
          } catch (e, s) {
            Logger.Inst().log(e.toString(), 'DioNetwork', 'captchaInterceptor', LogTypes.exception, s: s);
          }
          handler.next(response);
        },
        onError: (error, handler) async {
          if (error.error == 'Local network permission denied') {
            error.requestOptions.extra[_headlessRetried] = true;
            return handler.next(error);
          }
          try {
            final recovered = await recover(error.response, error.requestOptions, requestFailed: true);
            if (recovered != null) return handler.resolve(recovered);
          } on DioException catch (retryError) {
            return handler.next(retryError);
          } catch (e, s) {
            Logger.Inst().log(e.toString(), 'DioNetwork', 'captchaInterceptor', LogTypes.exception, s: s);
          }
          handler.next(error);
        },
      ),
    );
    return client;
  }

  static String mergeCookies(
    String previous,
    String current, {
    bool discardClearance = false,
  }) {
    List<String> parts(String header) =>
        header.split(';').map((part) => part.trim()).where((part) => part.indexOf('=') > 0).toList();
    String name(String part) => part.substring(0, part.indexOf('=')).trim();
    final fresh = parts(current);
    final freshNames = fresh.map(name).toSet();
    final retained = parts(previous).where((part) {
      final cookieName = name(part);
      return !freshNames.contains(cookieName) &&
          !(discardClearance && (cookieName == 'cf_clearance' || cookieName == 'cf_clearance_old'));
    });
    // Keep same-name cookies with different paths in native specificity order.
    return [...fresh, ...retained].join('; ');
  }

  static Dio cookieInterceptor(Dio client) {
    client.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) async {
          final String oldCookie = options.headers['Cookie'] as String? ?? '';
          final String newCookie = await Tools.getCookies(options.uri.toString());
          final headers = {
            ...options.headers,
            'Cookie': mergeCookies(oldCookie, newCookie),
          };
          options.headers = headers;
          return handler.next(options);
        },
        onResponse: (Response response, ResponseInterceptorHandler handler) async {
          final setCookies = response.headers['set-cookie'] ?? [];
          await Tools.saveCookies(
            response.requestOptions.uri.toString(),
            setCookies,
          );
          return handler.next(response);
        },
        onError: (DioException error, ErrorInterceptorHandler handler) async {
          final setCookies = error.response?.headers['set-cookie'] ?? [];
          await Tools.saveCookies(
            error.requestOptions.uri.toString(),
            setCookies,
          );
          return handler.next(error);
        },
      ),
    );

    return client;
  }

  static Options get defaultOptions {
    final options = Options(
      responseType: ResponseType.json,
      contentType: 'application/json',
      followRedirects: true,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'User-Agent': Tools.browserUserAgent,
      },
    );
    return options;
  }

  static Future<Response> get(
    String url, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    Map<String, dynamic>? headers = const {},
    CancelToken? cancelToken,
    void Function(int, int)? onReceiveProgress,
    Dio Function(Dio)? customInterceptor,
  }) async {
    cancelToken = _requestCancelToken(cancelToken);
    final client = customInterceptor != null ? customInterceptor(getClient()) : getClient();
    final urlAndQuery = separateUrlAndQueryParams(url, queryParameters);

    try {
      return await client.get(
        urlAndQuery['url'],
        queryParameters: urlAndQuery['query'],
        options: mergeOptions(options, headers),
        cancelToken: cancelToken,
        onReceiveProgress: onReceiveProgress,
      );
    } finally {
      client.close();
    }
  }

  static Future<Response> post(
    String url, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    Map<String, dynamic>? headers = const {},
    CancelToken? cancelToken,
    void Function(int, int)? onReceiveProgress,
    void Function(int, int)? onSendProgress,
    Dio Function(Dio)? customInterceptor,
  }) async {
    cancelToken = _requestCancelToken(cancelToken);
    final client = customInterceptor != null ? customInterceptor(getClient()) : getClient();
    final urlAndQuery = separateUrlAndQueryParams(url, queryParameters);

    try {
      return await client.post(
        urlAndQuery['url'],
        data: data,
        queryParameters: urlAndQuery['query'],
        options: mergeOptions(options, headers),
        cancelToken: cancelToken,
        onReceiveProgress: onReceiveProgress,
        onSendProgress: onSendProgress,
      );
    } finally {
      client.close();
    }
  }

  static Future<Response> head(
    String url, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    Map<String, dynamic>? headers = const {},
    CancelToken? cancelToken,
    void Function(int, int)? onReceiveProgress,
    void Function(int, int)? onSendProgress,
    Dio Function(Dio)? customInterceptor,
  }) async {
    cancelToken = _requestCancelToken(cancelToken);
    final client = customInterceptor != null ? customInterceptor(getClient()) : getClient();
    final urlAndQuery = separateUrlAndQueryParams(url, queryParameters);

    try {
      return await client.head(
        urlAndQuery['url'],
        data: data,
        queryParameters: urlAndQuery['query'],
        options: mergeOptions(options, headers),
        cancelToken: cancelToken,
      );
    } finally {
      client.close();
    }
  }

  static Future<Response> download(
    String url,
    String savePath, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    Map<String, dynamic>? headers = const {},
    CancelToken? cancelToken,
    void Function(int, int)? onReceiveProgress,
    bool deleteOnError = true,
    Dio Function(Dio)? customInterceptor,
  }) async {
    cancelToken = _requestCancelToken(cancelToken);
    final client = customInterceptor != null ? customInterceptor(getClient()) : getClient();
    final urlAndQuery = separateUrlAndQueryParams(url, queryParameters);

    final res = await client.download(
      urlAndQuery['url'],
      savePath,
      data: data,
      queryParameters: urlAndQuery['query'],
      options: mergeOptions(options, headers),
      cancelToken: cancelToken,
      onReceiveProgress: onReceiveProgress,
      deleteOnError: deleteOnError,
    );
    client.close();
    return res;
  }

  static Future<Response> downloadCustom(
    String url,
    String savePath,
    String fileNameWoutExt,
    String fileExt,
    String mediaType, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    Map<String, dynamic>? headers = const {},
    CancelToken? cancelToken,
    void Function(int, int)? onReceiveProgress,
    String lengthHeader = Headers.contentLengthHeader,
    bool deleteOnError = true,
    Dio Function(Dio)? customInterceptor,
  }) async {
    cancelToken = _requestCancelToken(cancelToken);
    final client = customInterceptor != null ? customInterceptor(getClient()) : getClient();
    final urlAndQuery = separateUrlAndQueryParams(url, queryParameters);

    options = DioMixin.checkOptions('GET', mergeOptions(options, headers));
    options.responseType = ResponseType.stream;
    Response<ResponseBody> response;
    try {
      response = await client.request<ResponseBody>(
        urlAndQuery['url'],
        data: data,
        options: options,
        queryParameters: urlAndQuery['query'],
        cancelToken: cancelToken ?? CancelToken(),
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.badResponse) {
        e.response!.data = null;
      }
      rethrow;
    } finally {
      client.close();
    }

    response.headers = Headers.fromMap(response.data!.headers);

    final completer = Completer<Response>();
    Future<Response> future = completer.future;
    int received = 0;

    final stream = response.data!.stream;
    bool compressed = false;
    int total = 0;
    final contentEncoding = response.headers.value(
      Headers.contentEncodingHeader,
    );
    if (contentEncoding != null) {
      compressed = ['gzip', 'deflate', 'compress'].contains(contentEncoding);
    }
    if (lengthHeader == Headers.contentLengthHeader && compressed) {
      total = -1;
    } else {
      total = int.parse(response.headers.value(lengthHeader) ?? '-1');
    }

    final String? fileUri = await ServiceHandler.createFileStreamFromSAFDirectory(
      fileNameWoutExt,
      mediaType,
      fileExt,
      savePath,
    );

    Future<void>? asyncWrite;
    bool closed = false;
    Future<void> closeAndDelete() async {
      if (!closed) {
        closed = true;
        await asyncWrite;
        if (deleteOnError && await ServiceHandler.existsFileStreamFromSAFDirectory(fileUri!)) {
          await ServiceHandler.deleteStreamToFileFromSAFDirectory(fileUri);
        }
      }
    }

    if (fileUri == null) {
      completer.completeError(
        DioMixin.assureDioException(Exception('Error creating saf file'), response.requestOptions),
      );
    }

    late StreamSubscription subscription;
    subscription = stream.listen(
      (data) {
        subscription.pause();

        // Write file asynchronously
        asyncWrite = ServiceHandler.writeStreamToFileFromSAFDirectory(fileUri!, data)
            .then((result) {
              if (!result) {
                throw Exception('Did not write file bytes');
              }

              // Notify progress
              received += data.length;

              onReceiveProgress?.call(received, total);

              if (cancelToken == null || !cancelToken.isCancelled) {
                subscription.resume();
              }
            })
            .catchError((dynamic e, StackTrace s) async {
              try {
                await subscription.cancel();
              } finally {
                completer.completeError(
                  DioMixin.assureDioException(e, response.requestOptions),
                );
              }
            });
      },
      onDone: () async {
        try {
          await asyncWrite;
          closed = true;
          await ServiceHandler.closeStreamToFileFromSAFDirectory(fileUri!);
          completer.complete(response);
        } catch (e) {
          completer.completeError(
            DioMixin.assureDioException(e, response.requestOptions),
          );
        }
      },
      onError: (e, s) async {
        try {
          await closeAndDelete();
        } finally {
          completer.completeError(
            DioMixin.assureDioException(e, response.requestOptions),
          );
        }
      },
      cancelOnError: true,
    );
    unawaited(
      cancelToken?.whenCancel.then((_) async {
        await subscription.cancel();
        await closeAndDelete();
      }),
    );

    final timeout = response.requestOptions.receiveTimeout;
    if (timeout != null) {
      future = future.timeout(timeout).catchError((dynamic e, StackTrace s) async {
        await subscription.cancel();
        await closeAndDelete();
        if (e is TimeoutException) {
          throw DioException.receiveTimeout(
            timeout: timeout,
            requestOptions: response.requestOptions,
          );
        } else {
          throw e;
        }
      });
    }

    return DioMixin.listenCancelForAsyncTask(cancelToken, future);
  }

  static String badResponseExceptionMessage(int? statusCode) {
    if (statusCode == null) {
      return '';
    }

    String message = '';

    switch (statusCode) {
      case 100:
        message = 'Continue';
        break;
      case 101:
        message = 'Switching Protocols';
        break;
      case 102:
        message = 'Processing';
        break;
      case 103:
        message = 'Early Hints';
        break;
      case 200:
        message = 'OK';
        break;
      case 201:
        message = 'Created';
        break;
      case 202:
        message = 'Accepted';
        break;
      case 203:
        message = 'Non-Authoritative Information';
        break;
      case 204:
        message = 'No Content';
        break;
      case 205:
        message = 'Reset Content';
        break;
      case 206:
        message = 'Partial Content';
        break;
      case 207:
        message = 'Multi-Status';
        break;
      case 208:
        message = 'Already Reported';
        break;
      case 226:
        message = 'IM Used';
        break;
      case 300:
        message = 'Multiple Choices';
        break;
      case 301:
        message = 'Moved Permanently';
        break;
      case 302:
        message = 'Found';
        break;
      case 303:
        message = 'See Other';
        break;
      case 304:
        message = 'Not Modified';
        break;
      case 305:
        message = 'Use Proxy';
        break;
      case 307:
        message = 'Temporary Redirect';
        break;
      case 308:
        message = 'Permanent Redirect';
        break;
      case 400:
        message = 'Bad Request';
        break;
      case 401:
        message = 'Unauthorized';
        break;
      case 402:
        message = 'Payment Required';
        break;
      case 403:
        message = 'Forbidden';
        break;
      case 404:
        message = 'Not Found';
        break;
      case 405:
        message = 'Method Not Allowed';
        break;
      case 406:
        message = 'Not Acceptable';
        break;
      case 407:
        message = 'Proxy Authentication Required';
        break;
      case 408:
        message = 'Request Timeout';
        break;
      case 409:
        message = 'Conflict';
        break;
      case 410:
        message = 'Gone';
        break;
      case 411:
        message = 'Length Required';
        break;
      case 412:
        message = 'Precondition Failed';
        break;
      case 413:
        message = 'Payload Too Large';
        break;
      case 414:
        message = 'URI Too Long';
        break;
      case 415:
        message = 'Unsupported Media Type';
        break;
      case 416:
        message = 'Range Not Satisfiable';
        break;
      case 417:
        message = 'Expectation Failed';
        break;
      case 418:
        message = "I'm a teapot";
        break;
      case 421:
        message = 'Misdirected Request';
        break;
      case 422:
        message = 'Unprocessable Entity';
        break;
      case 423:
        message = 'Locked';
        break;
      case 424:
        message = 'Failed Dependency';
        break;
      case 425:
        message = 'Too Early';
        break;
      case 426:
        message = 'Upgrade Required';
        break;
      case 428:
        message = 'Precondition Required';
        break;
      case 429:
        message = 'Too Many Requests';
        break;
      case 431:
        message = 'Request Header Fields Too Large';
        break;
      case 444:
        message = 'No Response';
        break;
      case 451:
        message = 'Unavailable For Legal Reasons';
        break;
      case 499:
        message = 'Client Closed Request';
        break;
      case 500:
        message = 'Internal Server Error';
        break;
      case 501:
        message = 'Not Implemented';
        break;
      case 502:
        message = 'Bad Gateway';
        break;
      case 503:
        message = 'Service Unavailable';
        break;
      case 504:
        message = 'Gateway Timeout';
        break;
      case 505:
        message = 'HTTP Version Not Supported';
        break;
      case 506:
        message = 'Variant Also Negotiates';
        break;
      case 507:
        message = 'Insufficient Storage';
        break;
      case 508:
        message = 'Loop Detected';
        break;
      case 510:
        message = 'Not Extended';
        break;
      case 511:
        message = 'Network Authentication Required';
        break;
      case 599:
        message = 'Network Connect Timeout';
        break;
      default:
        message = '';
        break;
    }

    message += '\n';

    if (statusCode >= 100 && statusCode < 200) {
      message += 'This is an informational response - the request was received, continuing processing';
    } else if (statusCode >= 200 && statusCode < 300) {
      message += 'The request was successful';
    } else if (statusCode >= 300 && statusCode < 400) {
      message += 'Redirection: further action needs to be taken in order to complete the request';
    } else if (statusCode >= 400 && statusCode < 500) {
      message += 'Error - the request contains bad syntax or cannot be fulfilled';
    } else if (statusCode >= 500 && statusCode < 600) {
      message += 'Server error - the server failed to fulfill a request';
    } else {
      message += 'Unknown error';
    }

    return message;
  }
}
