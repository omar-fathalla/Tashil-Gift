import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:al_mraay/core/security/rep_login_policy.dart';
import 'package:al_mraay/main.dart';
import 'package:al_mraay/features/company_portal/presentation/company_manager_portal_screen.dart';
import 'package:al_mraay/features/client_portal/presentation/client_receipt_upload_screen.dart';
import 'package:al_mraay/features/client_portal/presentation/rep_upload_gate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => RepLoginPolicy.setRuntimeOverride(null));

  group('Route Resolution & Portal Dispatch Tests', () {
    testWidgets('onGenerateInitialRoutes resolves single-resolution portal and promoter routes without decomposing', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MyApp(),
        ),
      );

      final element = tester.element(find.byType(MyApp));
      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));

      // 1. Initial route for agency ops: /ops/1434?event=y5ujNVYJxsYIEgK1xmQL
      final initialRoutes1 = materialApp.onGenerateInitialRoutes!('/ops/1434?event=y5ujNVYJxsYIEgK1xmQL');
      expect(initialRoutes1.length, 1, reason: 'Must return exactly one route to prevent pushing root admin guard');
      final route1 = initialRoutes1.first as MaterialPageRoute;
      final built1 = route1.builder(element);
      expect(built1, isA<CompanyManagerPortalScreen>());
      final portal1 = built1 as CompanyManagerPortalScreen;
      expect(portal1.companySlug, '1434');
      expect(portal1.initialEventId, 'y5ujNVYJxsYIEgK1xmQL');
      expect(portal1.isAgencyOpsMode, isTrue);

      // 2. Initial route for brand executive: /portal/1434?event=y5ujNVYJxsYIEgK1xmQL
      final initialRoutes2 = materialApp.onGenerateInitialRoutes!('/portal/1434?event=y5ujNVYJxsYIEgK1xmQL');
      expect(initialRoutes2.length, 1);
      final route2 = initialRoutes2.first as MaterialPageRoute;
      final built2 = route2.builder(element);
      expect(built2, isA<CompanyManagerPortalScreen>());
      final portal2 = built2 as CompanyManagerPortalScreen;
      expect(portal2.companySlug, '1434');
      expect(portal2.initialEventId, 'y5ujNVYJxsYIEgK1xmQL');
      expect(portal2.isAgencyOpsMode, isFalse);

      // 3. Initial route for promoter / customer: /c/1434?event=y5ujNVYJxsYIEgK1xmQL
      final initialRoutes3 = materialApp.onGenerateInitialRoutes!('/c/1434?event=y5ujNVYJxsYIEgK1xmQL');
      expect(initialRoutes3.length, 1);
      final route3 = initialRoutes3.first as MaterialPageRoute;
      final built3 = route3.builder(element);
      expect(built3, isA<ClientReceiptUploadScreen>());
      final client3 = built3 as ClientReceiptUploadScreen;
      expect(client3.companySlug, '1434');
      expect(client3.initialEventId, 'y5ujNVYJxsYIEgK1xmQL');

      // 4. Hash route support: /#/ops/1434?event=y5ujNVYJxsYIEgK1xmQL
      final initialRoutes4 = materialApp.onGenerateInitialRoutes!('/#/ops/1434?event=y5ujNVYJxsYIEgK1xmQL');
      expect(initialRoutes4.length, 1);
      final route4 = initialRoutes4.first as MaterialPageRoute;
      final built4 = route4.builder(element);
      expect(built4, isA<CompanyManagerPortalScreen>());
      final portal4 = built4 as CompanyManagerPortalScreen;
      expect(portal4.companySlug, '1434');
      expect(portal4.isAgencyOpsMode, isTrue);
    });

    testWidgets('onGenerateRoute dispatches routes identically for runtime navigation', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MyApp(),
        ),
      );

      final element = tester.element(find.byType(MyApp));
      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));

      final route1 = materialApp.onGenerateRoute!(
        const RouteSettings(name: '/ops/1434?event=y5ujNVYJxsYIEgK1xmQL'),
      ) as MaterialPageRoute;
      final built1 = route1.builder(element);
      expect(built1, isA<CompanyManagerPortalScreen>());

      final route2 = materialApp.onGenerateRoute!(
        const RouteSettings(name: '/portal/1434?event=y5ujNVYJxsYIEgK1xmQL'),
      ) as MaterialPageRoute;
      final built2 = route2.builder(element);
      expect(built2, isA<CompanyManagerPortalScreen>());

      final route3 = materialApp.onGenerateRoute!(
        const RouteSettings(name: '/c/1434?event=y5ujNVYJxsYIEgK1xmQL'),
      ) as MaterialPageRoute;
      final built3 = route3.builder(element);
      expect(built3, isA<ClientReceiptUploadScreen>());

      final repRoute = materialApp.onGenerateRoute!(
        const RouteSettings(name: '/rep/1434?event=y5ujNVYJxsYIEgK1xmQL'),
      ) as MaterialPageRoute;
      final builtRep = repRoute.builder(element);
      expect(builtRep, isA<RepUploadGate>());
      final gate = builtRep as RepUploadGate;
      expect(gate.companySlug, '1434');
      expect(gate.initialEventId, 'y5ujNVYJxsYIEgK1xmQL');

      RepLoginPolicy.setRuntimeOverride(true);
      final gatedPublic = materialApp.onGenerateRoute!(
        const RouteSettings(name: '/c/1434'),
      ) as MaterialPageRoute;
      expect(gatedPublic.builder(element), isA<RepUploadGate>());
      RepLoginPolicy.setRuntimeOverride(false);
      final openPublic = materialApp.onGenerateRoute!(
        const RouteSettings(name: '/promoter/1434'),
      ) as MaterialPageRoute;
      expect(openPublic.builder(element), isA<ClientReceiptUploadScreen>());
    });
  });
}
