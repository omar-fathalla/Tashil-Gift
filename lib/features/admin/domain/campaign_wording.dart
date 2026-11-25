/// C-06: display wording for the campaign page.
///
/// Gift names are stored data: the default voucher names (`فواتشر 50 جنيه`,
/// `كارت فواتشر مشتريات`) are written to `allocatedPrizes.name` and the
/// voucher checks on the app and the server (`security_functions.js`
/// VOUCHER_NAME_RE, `AllocatedPrize.isVoucher`) match on «فواتشر». So the
/// stored value never changes; only what the admin sees does.
class CampaignWording {
  CampaignWording._();

  static final RegExp _voucherWord = RegExp(r'فواتشرات|فواتشر|فوتشر|فاوتشر');

  /// The gift name as shown on the page (the stored name is unchanged).
  static String giftLabel(String storedName) {
    if (storedName.isEmpty) return storedName;
    return storedName
        .replaceAll('كارت فواتشر مشتريات', 'كارت مشتريات')
        .replaceAll('كروت الفواتشرات', 'كروت المشتريات')
        .replaceAll(_voucherWord, 'كارت مشتريات');
  }
}
