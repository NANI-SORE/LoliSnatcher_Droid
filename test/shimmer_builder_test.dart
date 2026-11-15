import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/widgets/preview/shimmer_builder.dart';

const _gradient = LinearGradient(colors: [Colors.black, Colors.white]);

Widget _buildShimmer({required bool enabled, required bool isLoading}) {
  return MaterialApp(
    home: Shimmer(
      enabled: enabled,
      linearGradient: _gradient,
      child: ShimmerLoading(
        isLoading: isLoading,
        child: const SizedBox(width: 20, height: 20),
      ),
    ),
  );
}

void main() {
  testWidgets('shimmer stays idle without a loading child', (tester) async {
    await tester.pumpWidget(_buildShimmer(enabled: true, isLoading: false));
    await tester.pump();

    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('disabled shimmer stays idle with a loading child', (tester) async {
    await tester.pumpWidget(_buildShimmer(enabled: false, isLoading: true));
    await tester.pump();

    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
