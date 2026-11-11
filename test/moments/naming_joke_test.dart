import 'package:ai_lab_tycoon/ui/moments/naming_joke.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('plain names are fine', () {
    expect(namingJoke('GL-2'), isNull);
    expect(namingJoke('Garage Model'), isNull);
    expect(versionSuffixTokens('turbo'), isEmpty, reason: 'first token is the name');
  });

  test('one or two suffixes are tolerated', () {
    expect(versionSuffixTokens('GL-4-turbo'), ['turbo']);
    expect(namingJoke('GL-4 turbo preview'), isNull);
  });

  test('three or more suffixes trigger the joke', () {
    expect(namingJoke('GL-4-turbo-preview-0613'), 'Users are confused by your naming scheme.');
    expect(namingJoke('GL 4 Pro Max Ultra'), isNotNull);
    expect(versionSuffixTokens('GL-4o-mini-2024-07-18-preview').length, 3);
  });

  test('date stamps count, random numbers do not', () {
    expect(versionSuffixTokens('GL-0613'), ['0613']);
    expect(versionSuffixTokens('GL-20240513'), ['20240513']);
    expect(versionSuffixTokens('GL-7-1337-42'), isEmpty);
  });

  test('more suffixes, funnier warning', () {
    final three = namingJoke('a mini turbo pro')!;
    final five = namingJoke('a mini turbo pro max ultra')!;
    expect(three, isNot(five));
  });
}
