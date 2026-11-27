import 'package:al_mraay/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'support/emulator.dart';
import 'support/flows.dart';

void main() {
  patrolTest('admin signs in and sees the dashboard', ($) async {
    assertEmulatorBuild();
    await seedAdmin();

    app.main();
    await signInAsAdmin($);

    expect($('الفواتير'), findsWidgets);
    expect($(TextFormField), findsNothing);
  });
}
