import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
void main() {
  test('voucherSerialMode backward compatible', () {
    expect(EventModel.resolveVoucherSerialMode({}), 'optional');
    expect(EventModel.resolveVoucherSerialMode({'requireVoucherSerials': true}), 'required');
    expect(EventModel.resolveVoucherSerialMode({'requireVoucherSerials': false}), 'optional');
    expect(EventModel.resolveVoucherSerialMode({'voucherSerialMode': 'hidden', 'requireVoucherSerials': true}), 'hidden');
    expect(EventModel.resolveVoucherSerialMode({'voucherSerialMode': 'bogus', 'require_voucher_serials': true}), 'required');
  });
}
