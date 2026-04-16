import 'dart:math' as math;

typedef ProviderModelTestCallback = Future<void> Function(String modelId);
typedef ProviderModelProgressCallback = void Function(String modelId);
typedef ProviderModelFailureCallback =
    void Function(String modelId, Object error);

class ProviderModelBatchTestRunner {
  static const int defaultMaxConcurrency = 5;

  static Future<void> run({
    required Iterable<String> modelIds,
    required ProviderModelTestCallback tester,
    required ProviderModelProgressCallback onModelStarted,
    required ProviderModelProgressCallback onModelSucceeded,
    required ProviderModelFailureCallback onModelFailed,
    bool useConcurrent = true,
    int maxConcurrency = defaultMaxConcurrency,
    Duration sequentialDelay = const Duration(milliseconds: 500),
  }) async {
    final queue = List<String>.from(modelIds);
    if (queue.isEmpty) return;

    final workerCount = math.max(1, maxConcurrency);
    if (!useConcurrent || workerCount == 1 || queue.length == 1) {
      for (int i = 0; i < queue.length; i++) {
        final modelId = queue[i];
        onModelStarted(modelId);
        try {
          await tester(modelId);
          onModelSucceeded(modelId);
        } catch (error) {
          onModelFailed(modelId, error);
        }
        if (i < queue.length - 1 && sequentialDelay > Duration.zero) {
          await Future.delayed(sequentialDelay);
        }
      }
      return;
    }

    int nextIndex = 0;

    Future<void> worker() async {
      while (true) {
        if (nextIndex >= queue.length) return;
        final modelId = queue[nextIndex++];
        onModelStarted(modelId);
        try {
          await tester(modelId);
          onModelSucceeded(modelId);
        } catch (error) {
          onModelFailed(modelId, error);
        }
      }
    }

    await Future.wait<void>(
      List.generate(math.min(workerCount, queue.length), (_) => worker()),
    );
  }
}
