import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/clients/client_context_provider.dart';
import 'package:vortice_app/models/profile.dart';

void main() {
  group('isVorticeStaffRole', () {
    test('treats owner and employee as Vórtice staff', () {
      expect(isVorticeStaffRole(UserRole.owner), isTrue);
      expect(isVorticeStaffRole(UserRole.employee), isTrue);
    });

    test('treats client-side roles as non-staff', () {
      expect(isVorticeStaffRole(UserRole.client), isFalse);
      expect(isVorticeStaffRole(UserRole.clientAdmin), isFalse);
      expect(isVorticeStaffRole(UserRole.clientMechanic), isFalse);
      expect(isVorticeStaffRole(UserRole.operator), isFalse);
    });
  });
}
