import 'package:flutter_test/flutter_test.dart';

import 'package:toplinkai_app/api/service_request.dart';

void main() {
  group('ChatRefineResult', () {
    test('reads the launched flag', () {
      final result = ChatRefineResult.fromJson({
        'category': 'lawn-care',
        'launched': false,
        'urgency': 'today',
        'notes': 'mow my lawn',
      });
      expect(result.category, 'lawn-care');
      expect(result.launched, isFalse);
    });

    test('treats a missing launched flag as launched', () {
      final result = ChatRefineResult.fromJson({'category': 'plumbing', 'urgency': 'today', 'notes': ''});
      expect(result.launched, isTrue);
    });
  });

  group('ServiceRequestSubmission', () {
    test('a new request has no message and is not waitlisted', () {
      final submission = ServiceRequestSubmission.fromJson({'request_id': 7, 'status': 'new'});
      expect(submission.requestId, 7);
      expect(submission.isWaitlisted, isFalse);
      expect(submission.message, isNull);
    });

    test('a waitlisted request carries the coming-soon message', () {
      final submission = ServiceRequestSubmission.fromJson({
        'request_id': 8,
        'status': 'waitlisted',
        'message': 'Coming soon in your area',
      });
      expect(submission.isWaitlisted, isTrue);
      expect(submission.message, 'Coming soon in your area');
    });
  });
}
