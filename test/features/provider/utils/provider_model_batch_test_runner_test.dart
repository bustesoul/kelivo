import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/features/provider/utils/provider_model_batch_test_runner.dart';

void main() {
  group('ProviderModelBatchTestRunner', () {
    test('开启并发时不会超过最大并发数', () async {
      final modelIds = List<String>.generate(12, (index) => 'model-$index');
      int active = 0;
      int maxActive = 0;
      final succeeded = <String>[];

      await ProviderModelBatchTestRunner.run(
        modelIds: modelIds,
        useConcurrent: true,
        maxConcurrency: 5,
        tester: (modelId) async {
          active++;
          if (active > maxActive) maxActive = active;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          active--;
        },
        onModelStarted: (_) {},
        onModelSucceeded: succeeded.add,
        onModelFailed: (_, __) {},
      );

      expect(maxActive, 5);
      expect(succeeded, hasLength(modelIds.length));
      expect(succeeded.toSet(), modelIds.toSet());
    });

    test('关闭并发时按顺序逐个检测', () async {
      final modelIds = ['a', 'b', 'c'];
      int active = 0;
      int maxActive = 0;
      final started = <String>[];
      final succeeded = <String>[];

      await ProviderModelBatchTestRunner.run(
        modelIds: modelIds,
        useConcurrent: false,
        sequentialDelay: Duration.zero,
        tester: (modelId) async {
          started.add(modelId);
          active++;
          if (active > maxActive) maxActive = active;
          await Future<void>.delayed(const Duration(milliseconds: 1));
          active--;
        },
        onModelStarted: (_) {},
        onModelSucceeded: succeeded.add,
        onModelFailed: (_, __) {},
      );

      expect(maxActive, 1);
      expect(started, modelIds);
      expect(succeeded, modelIds);
    });

    test('单个模型失败时不会中断其余模型检测', () async {
      final succeeded = <String>[];
      final failed = <String>[];

      await ProviderModelBatchTestRunner.run(
        modelIds: const ['a', 'b', 'c'],
        useConcurrent: true,
        maxConcurrency: 2,
        tester: (modelId) async {
          await Future<void>.delayed(const Duration(milliseconds: 1));
          if (modelId == 'b') {
            throw StateError('boom');
          }
        },
        onModelStarted: (_) {},
        onModelSucceeded: succeeded.add,
        onModelFailed: (modelId, _) => failed.add(modelId),
      );

      expect(succeeded, containsAll(<String>['a', 'c']));
      expect(failed, ['b']);
    });
  });
}
