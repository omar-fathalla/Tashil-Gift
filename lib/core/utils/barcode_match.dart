/// TAG-86: when a receipt barcode counts as a catalog barcode.
///
/// Exact match always counts. A prefix match only covers the real POS
/// variation (a 12-digit UPC printed as a 13-digit EAN, or the other way
/// round): both codes must have at least 12 digits and differ in length by
/// one. A truncated catalog code such as `622115510` (9 digits) must never
/// swallow every Unilever barcode that starts with it.
library;

/// The shortest code a prefix match accepts.
const int kBarcodePrefixMinLength = 12;

/// Whether [receipt] and [catalog] name the same product.
bool barcodesMatch(String receipt, String catalog) {
  final a = receipt.trim();
  final b = catalog.trim();
  if (a.isEmpty || b.isEmpty) return false;
  if (a == b) return true;
  return barcodePrefixVariant(a, b);
}

/// The 12/13-digit prefix variation only (no exact match).
bool barcodePrefixVariant(String receipt, String catalog) {
  final a = receipt.trim();
  final b = catalog.trim();
  if (a.isEmpty || b.isEmpty || a == b) return false;
  final shorter = a.length <= b.length ? a : b;
  final longer = identical(shorter, a) ? b : a;
  if (shorter.length < kBarcodePrefixMinLength) return false;
  if (longer.length - shorter.length != 1) return false;
  return longer.startsWith(shorter);
}
