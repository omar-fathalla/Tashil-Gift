import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/utils/slug_utils.dart';
import 'package:al_mraay/core/utils/url_builder.dart';

void main() {
  group('SlugUtils Tests', () {
    test('Translates known Arabic brand names to standard English slugs', () {
      expect(SlugUtils.generateEnglishSlug('المراعي'), equals('almarai'));
      expect(SlugUtils.generateEnglishSlug('جهينة'), equals('juhayna'));
      expect(SlugUtils.generateEnglishSlug('كارفور'), equals('carrefour'));
      expect(SlugUtils.generateEnglishSlug('بيبسي'), equals('pepsi'));
      expect(SlugUtils.generateEnglishSlug('كوكاكولا'), equals('coca-cola'));
      expect(SlugUtils.generateEnglishSlug('فتح الله'), equals('fathalla'));
      expect(SlugUtils.generateEnglishSlug('لولو'), equals('lulu'));
      expect(SlugUtils.generateEnglishSlug('باندا'), equals('panda'));
      expect(SlugUtils.generateEnglishSlug('نستله'), equals('nestle'));
      expect(SlugUtils.generateEnglishSlug('صافولا'), equals('savola'));
    });

    test('Transliterates custom Arabic campaign names to Latin slug', () {
      final slug = SlugUtils.generateEnglishSlug('عروض الصيف الكبرى');
      expect(slug, isNotEmpty);
      expect(RegExp(r'^[a-z0-9\-]+$').hasMatch(slug), isTrue);
    });

    test('Cleans mixed English and Arabic strings and handles whitespace and special chars', () {
      expect(SlugUtils.generateEnglishSlug('Pepsi Max 2026!'), equals('pepsi-max-2026'));
      expect(SlugUtils.generateEnglishSlug('Almarai & Co.'), equals('almarai-co'));
    });

    test('Handles empty and whitespace-only strings safely', () {
      expect(SlugUtils.generateEnglishSlug(''), equals('campaign'));
      expect(SlugUtils.generateEnglishSlug('   '), equals('campaign'));
    });
  });

  group('AppUrlBuilder Tests', () {
    test('Builds promoter URL correctly with slug and eventId', () {
      final url = AppUrlBuilder.buildPromoterUrl('almarai', eventId: 'evt123');
      expect(url, contains('/#/c/almarai?event=evt123'));
    });

    test('Builds promoter URL correctly without eventId', () {
      final url = AppUrlBuilder.buildPromoterUrl('almarai');
      expect(url, contains('/#/c/almarai'));
      expect(url.contains('?event='), isFalse);
    });

    test('Builds manager portal URL correctly with slug and eventId', () {
      final url = AppUrlBuilder.buildManagerPortalUrl('almarai', eventId: 'evt123');
      expect(url, contains('/#/portal/almarai?event=evt123'));
    });

    test('Builds manager portal URL correctly without eventId', () {
      final url = AppUrlBuilder.buildManagerPortalUrl('almarai');
      expect(url, contains('/#/portal/almarai'));
      expect(url.contains('?event='), isFalse);
    });
  });
}
