import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/service_requests/service_request_evidence.dart';

void main() {
  test('private loader accepts same-request paths and legacy Next URLs only', () {
    expect(
      requestPhotoPath('request-a/photo.jpg', 'request-a'),
      'request-a/photo.jpg',
    );
    expect(
      requestPhotoPath(
        'https://hkjpojobdbbtjkhaudki.supabase.co/storage/v1/object/public/service-request-photos/request-a/photo.jpg',
        'request-a',
      ),
      'request-a/photo.jpg',
    );
    for (final path in [
      'request-b/photo.jpg',
      'request-a/../photo.jpg',
      'https://outside.invalid/request-a/photo.jpg',
      'request-a/photo.jpg?token=other',
    ]) {
      expect(() => requestPhotoPath(path, 'request-a'), throwsFormatException);
    }
  });
}
