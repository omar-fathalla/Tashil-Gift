// TAG-84: which barcode prefixes a company's catalog really uses.
//
// A line the AI classed as the sponsor's product but whose barcode starts
// with a prefix the sponsor's catalog never (or almost never) uses is a sign
// that the AI paired the product name with the wrong numbers line (for
// example receipt 36/13/418/271126: "كنور تتبيلة البطاطس" was paired with the
// 18 EGP line of 6223000470015, an Isis tea, instead of 130 EGP /
// 6221155141507). The profile is learned from the company catalog, so it works
// for any company and never hard-codes one prefix.
//
// It is advisory only: it never accepts or rejects a receipt. It is used to
// stop such a pairing from being auto-added to the company catalog.

class BarcodePrefixProfile {
  /// Length of the prefix compared (GS1 country + company part).
  static const int prefixLength = 7;

  /// A prefix is "known" once this many catalog barcodes use it, so one bad
  /// catalog entry cannot whitelist a foreign prefix by itself.
  static const int minPrefixCount = 3;

  /// Below this many catalog barcodes the profile is too thin to judge.
  static const int minCatalogBarcodes = 20;

  final Map<String, int> _prefixCounts;
  final Set<String> _barcodes;
  final int _total;

  BarcodePrefixProfile._(this._prefixCounts, this._barcodes, this._total);

  static const BarcodePrefixProfile empty = BarcodePrefixProfile._const();
  const BarcodePrefixProfile._const()
      : _prefixCounts = const {},
        _barcodes = const {},
        _total = 0;

  factory BarcodePrefixProfile.fromBarcodes(Iterable<String> catalogBarcodes) {
    final counts = <String, int>{};
    final all = <String>{};
    for (final raw in catalogBarcodes) {
      final b = clean(raw);
      if (!isRetailBarcode(b)) continue;
      if (!all.add(b)) continue;
      final p = b.substring(0, prefixLength);
      counts[p] = (counts[p] ?? 0) + 1;
    }
    return BarcodePrefixProfile._(counts, all, all.length);
  }

  static String clean(String raw) {
    const ar = '٠١٢٣٤٥٦٧٨٩';
    final sb = StringBuffer();
    for (final ch in raw.trim().split('')) {
      final i = ar.indexOf(ch);
      sb.write(i >= 0 ? '$i' : ch);
    }
    return sb.toString();
  }

  /// 8-14 digits, and not an in-store weighed/random-weight code (GS1
  /// prefix 2x), which any store prints for its own scale items.
  static bool isRetailBarcode(String b) =>
      RegExp(r'^\d{8,14}$').hasMatch(b) && !b.startsWith('2');

  bool get isActive => _total >= minCatalogBarcodes;

  bool isKnownPrefix(String barcode) {
    final b = clean(barcode);
    if (b.length < prefixLength) return false;
    return (_prefixCounts[b.substring(0, prefixLength)] ?? 0) >= minPrefixCount;
  }

  /// True when [barcode] is a real retail barcode that is not in the catalog
  /// and whose prefix the catalog does not use. False when unsure (thin
  /// catalog, empty/invalid/weighed barcode, exact catalog hit).
  bool conflicts(String barcode) {
    if (!isActive) return false;
    final b = clean(barcode);
    if (!isRetailBarcode(b)) return false;
    if (_barcodes.contains(b)) return false;
    return !isKnownPrefix(b);
  }
}
