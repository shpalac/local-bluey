import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/endpoint.dart';

void main() {
  test('joins base and path cleanly (#118)', () {
    expect(endpoint('http://h/v1', '/audio/speech'), 'http://h/v1/audio/speech');
    expect(endpoint('http://h/v1/', '/audio/speech'), 'http://h/v1/audio/speech');
    expect(endpoint('http://h/v1//', 'audio/speech'), 'http://h/v1/audio/speech');
    expect(endpoint(' http://h/v1 ', '/x'), 'http://h/v1/x');
  });
}
