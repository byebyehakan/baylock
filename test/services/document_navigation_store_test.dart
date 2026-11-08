import 'package:baylock/services/document_navigation_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('stores current page and independent sorted bookmarks per document', () async {
    SharedPreferences.setMockInitialValues({});
    const store = DocumentNavigationStore();

    await store.saveLastPage('lecture.pdf', 12);
    await store.toggleBookmark('lecture.pdf', 7);
    await store.toggleBookmark('lecture.pdf', 3);
    await store.toggleBookmark('other.pdf', 2);

    expect(await store.lastPage('lecture.pdf'), 12);
    expect(await store.bookmarks('lecture.pdf'), [3, 7]);
    expect(await store.bookmarks('other.pdf'), [2]);

    expect(await store.toggleBookmark('lecture.pdf', 7), isFalse);
    expect(await store.bookmarks('lecture.pdf'), [3]);
  });
}
