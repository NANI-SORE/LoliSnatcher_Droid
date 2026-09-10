import 'dart:async';

import 'package:dio/dio.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/hydrus_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';

typedef BooruConnectionTestResult = ({BooruType? booruType, String? errorString});

class BooruConnectionTester {
  const BooruConnectionTester({this.timeout = const Duration(seconds: 60)});

  final Duration timeout;

  Future<BooruConnectionTestResult> test(
    Booru booru,
    BooruType requestedType, {
    required String hydrusFailureMessage,
    bool withCaptchaCheck = true,
    CancelToken? cancelToken,
  }) async {
    final token = cancelToken ?? CancelToken();
    try {
      return await Future.any<BooruConnectionTestResult>([
        DioNetwork.runWithCancellation(
          token,
          () => _test(
            booru,
            requestedType,
            hydrusFailureMessage: hydrusFailureMessage,
            withCaptchaCheck: withCaptchaCheck,
            cancelToken: token,
          ),
        ),
        token.whenCancel.then((error) => throw error),
      ]).timeout(
        timeout,
        onTimeout: () {
          token.cancel('Booru connection test timed out');
          throw TimeoutException('Booru connection test timed out', timeout);
        },
      );
    } finally {
      token.cancel('Booru connection test finished');
    }
  }

  Future<BooruConnectionTestResult> _test(
    Booru booru,
    BooruType requestedType, {
    required String hydrusFailureMessage,
    required bool withCaptchaCheck,
    required CancelToken cancelToken,
  }) async {
    if (cancelToken.isCancelled) throw cancelToken.cancelError!;
    booru.type = requestedType;

    if (requestedType == BooruType.Hydrus) {
      final hydrusHandler = HydrusHandler(booru, 20);
      final verified = await hydrusHandler.verifyApiAccess();
      if (cancelToken.isCancelled) throw cancelToken.cancelError!;
      if (verified) {
        return (booruType: requestedType, errorString: null);
      }
      return (booruType: null, errorString: hydrusFailureMessage);
    }

    if (requestedType == BooruType.Autodetect) {
      for (final type in BooruType.detectable.skip(1)) {
        final result = await _test(
          booru,
          type,
          hydrusFailureMessage: hydrusFailureMessage,
          withCaptchaCheck: false,
          cancelToken: cancelToken,
        );
        if (cancelToken.isCancelled) throw cancelToken.cancelError!;
        if (result.booruType != null) return result;
      }
      return (booruType: null, errorString: null);
    }

    final handlerResult = BooruHandlerFactory().getBooruHandler([booru], 5);
    final handler = handlerResult.booruHandler;
    handler.pageNum = handlerResult.startingPage + 1;
    final fetched =
        (await handler.search(
          '',
          null,
          withCaptchaCheck: withCaptchaCheck,
        )) ??
        [];
    if (cancelToken.isCancelled) throw cancelToken.cancelError!;

    final errorString = handler.errorString.isEmpty ? null : handler.errorString;
    if (errorString != null) {
      Logger.Inst().log(
        errorString,
        'BooruConnectionTester',
        'test',
        LogTypes.exception,
      );
    }
    if (fetched.isNotEmpty) {
      Logger.Inst().log(
        'Found Results as $requestedType',
        'BooruConnectionTester',
        'test',
        LogTypes.booruHandlerInfo,
      );
      return (booruType: requestedType, errorString: errorString);
    }
    return (booruType: null, errorString: errorString);
  }
}
