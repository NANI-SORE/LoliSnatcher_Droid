import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/hydrus_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

typedef BooruConnectionTestResult = ({BooruType? booruType, String? errorString});

class BooruConnectionTester {
  const BooruConnectionTester();

  Future<BooruConnectionTestResult> test(
    Booru booru,
    BooruType requestedType, {
    required String hydrusFailureMessage,
    bool withCaptchaCheck = true,
  }) async {
    booru.type = requestedType;

    if (requestedType == BooruType.Hydrus) {
      final hydrusHandler = HydrusHandler(booru, 20);
      if (await hydrusHandler.verifyApiAccess()) {
        return (booruType: requestedType, errorString: null);
      }
      return (booruType: null, errorString: hydrusFailureMessage);
    }

    if (requestedType == BooruType.Autodetect) {
      for (final type in BooruType.detectable.skip(1)) {
        final result = await test(
          booru,
          type,
          hydrusFailureMessage: hydrusFailureMessage,
          withCaptchaCheck: false,
        );
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
