// OWNER: ui-moments agent.
// The "your naming scheme is confusing" joke. Cosmetic only.

const _suffixWords = {
  'mini',
  'nano',
  'micro',
  'lite',
  'turbo',
  'preview',
  'pro',
  'max',
  'ultra',
  'plus',
  'flash',
  'instruct',
  'chat',
  'exp',
  'experimental',
  'beta',
  'alpha',
  'latest',
  'hd',
  'xl',
  'xxl',
  'large',
  'small',
  'medium',
  'reasoning',
  'thinking',
  'high',
  'low',
  'fast',
  'deluxe',
  'next',
  'final',
  'new',
  'omni',
  'edge',
  'rc',
  'vision',
  'o',
};

final _isoDate = RegExp(r'\d{4}-\d{2}-\d{2}');
final _splitter = RegExp(r'[\s\-_./+()]+');
final _mmdd = RegExp(r'^(0[1-9]|1[0-2])(0[1-9]|[12]\d|3[01])$');
final _yyyymmdd = RegExp(r'^20\d{2}(0[1-9]|1[0-2])(0[1-9]|[12]\d|3[01])$');
final _yymmdd = RegExp(r'^\d{2}(0[1-9]|1[0-2])(0[1-9]|[12]\d|3[01])$');

/// Version-ish suffix tokens in [name]: marketing words (mini, turbo, pro…)
/// and date stamps (0613, 2024-05-13, 20240513…). The first token is the
/// model's actual name and never counts.
List<String> versionSuffixTokens(String name) {
  final normalized = name.toLowerCase().replaceAll(_isoDate, ' 0101 ');
  final tokens = normalized.split(_splitter).where((t) => t.isNotEmpty).toList();
  if (tokens.length <= 1) return const [];
  final out = <String>[];
  for (final t in tokens.skip(1)) {
    if (_suffixWords.contains(t) || _mmdd.hasMatch(t) || _yymmdd.hasMatch(t) || _yyyymmdd.hasMatch(t)) {
      out.add(t);
    }
  }
  return out;
}

/// A funny warning when the name has 3+ version-ish suffixes, else null.
String? namingJoke(String name) {
  final n = versionSuffixTokens(name).length;
  if (n < 3) return null;
  if (n == 3) return 'Users are confused by your naming scheme.';
  if (n == 4) {
    return 'Your marketing team has started a group chat called "what is this model".';
  }
  return 'Analysts are now writing explainer threads on which of your models is which.';
}

/// Suggested suffixes the release sheet offers as one-tap chips.
const namingSuffixSuggestions = ['turbo', 'preview', 'mini', 'pro', '0613'];
