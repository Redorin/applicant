import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:applicants_app/core/api/api_client.dart';
import 'package:applicants_app/features/auth/auth_provider.dart';
import 'package:applicants_app/features/master_data/master_data_provider.dart';

/// Records every path requested and returns a canned response keyed by a
/// path-prefix match, so tests can both assert on call counts (e.g. "the
/// API was never hit for a too-short name") and control what comes back.
class _FakeApiClient extends ApiClient {
  _FakeApiClient(this.responses);

  final dynamic Function(String path) responses;
  final List<String> requestedPaths = [];

  @override
  Future<dynamic> get(String path, {Duration? timeout}) async {
    requestedPaths.add(path);
    return responses(path);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('checkDuplicate does not call the API when either name is under 3 characters',
      () async {
    final fakeApi = _FakeApiClient((_) => {'count': 1});
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(fakeApi)],
    );
    addTearDown(container.dispose);

    final controller = container.read(masterDataProvider.notifier);
    controller.newApplicant();
    container.read(masterDataProvider).draft!
      ..surname = 'De' // 2 chars
      ..firstname = 'Juan'; // 4 chars

    await controller.checkDuplicate();

    expect(fakeApi.requestedPaths, isEmpty,
        reason: 'surname is under the 3-char threshold — no probe should fire');
    expect(container.read(masterDataProvider).duplicateWarning, DuplicateWarning.none);
  });

  test('checkDuplicate flags a match and populates duplicateMatches from the search endpoint',
      () async {
    final fakeApi = _FakeApiClient((path) {
      if (path.startsWith('/api/masterdata/duplicate-check')) {
        return {'count': 1};
      }
      if (path.startsWith('/api/masterdata/?search=')) {
        return [
          {
            'id': 42,
            'surname': 'Delacruz',
            'firstname': 'Juan',
            'midname': 'Reyes',
            'municipality': 'Lingayen',
            'dbirth': null,
            'latestStatus': 'On Process',
          },
        ];
      }
      throw StateError('unexpected path: $path');
    });
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(fakeApi)],
    );
    addTearDown(container.dispose);

    final controller = container.read(masterDataProvider.notifier);
    controller.newApplicant();
    container.read(masterDataProvider).draft!
      ..surname = 'Delacruz'
      ..firstname = 'Juan';

    await controller.checkDuplicate();

    final state = container.read(masterDataProvider);
    expect(state.duplicateWarning, DuplicateWarning.nameOnly); // no dbirth entered
    expect(state.duplicateMatches, hasLength(1));
    expect(state.duplicateMatches.single.displayName, 'Delacruz, Juan Reyes');
    expect(state.duplicateMatches.single.municipality, 'Lingayen');
  });

  test('dismissDuplicateWarning clears both the warning and matches client-side', () async {
    final fakeApi = _FakeApiClient((path) {
      if (path.startsWith('/api/masterdata/duplicate-check')) return {'count': 1};
      return [
        {'id': 7, 'surname': 'Santos', 'firstname': 'Maria'},
      ];
    });
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(fakeApi)],
    );
    addTearDown(container.dispose);

    final controller = container.read(masterDataProvider.notifier);
    controller.newApplicant();
    container.read(masterDataProvider).draft!
      ..surname = 'Santos'
      ..firstname = 'Maria';
    await controller.checkDuplicate();
    expect(container.read(masterDataProvider).duplicateWarning, isNot(DuplicateWarning.none));

    controller.dismissDuplicateWarning();

    final state = container.read(masterDataProvider);
    expect(state.duplicateWarning, DuplicateWarning.none);
    expect(state.duplicateMatches, isEmpty);
  });
}
