import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:encargalo/features/auth/presentation/auth_screens.dart';
import 'package:encargalo/app/theme.dart';

void main() {
  for (final width in [360.0, 390.0, 430.0]) {
    testWidgets(
      'Configuración pendiente sin login ficticio a $width px y texto ampliado',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(Brightness.light),
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 900),
                textScaler: TextScaler.linear(1.5),
              ),
              child: const ConfigurationScreen(),
            ),
          ),
        );
        expect(find.text('Conexión cloud pendiente'), findsOneWidget);
        expect(find.text('Ingresar'), findsNothing);
        expect(tester.takeException(), null);
      },
    );
  }
}
