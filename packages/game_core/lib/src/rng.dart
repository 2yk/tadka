/// Deterministic seeded PRNG — a faithful port of §RNG from the web build.
///
/// Same seed => same run. This underwrites seed sharing, reproducible bug reports,
/// the future Daily Route, and the golden tests.
///
/// PORTING NOTE (the trap): JavaScript's bitwise operators coerce to 32 bits, but Dart
/// ints are 64-bit. Every intermediate here is masked back to 32 bits to reproduce
/// `Math.imul`, `|0` and `>>>` exactly. `_h` and `_a` are held as *unsigned* 32-bit
/// values (0 .. 2^32-1), which makes `>>` a logical shift and matches JS `>>>`.
/// Divergence would silently change every shuffle and shop roll, so
/// `test/vectors_test.dart` asserts this against the JS engine's own output.
library;

const int _mask32 = 0xFFFFFFFF;

/// 32-bit multiply, equivalent to JS `Math.imul`.
///
/// The low 32 bits of a product are identical whether the operands are read as signed
/// or unsigned, so masking the (possibly 64-bit-overflowing) Dart product is correct.
int _imul(int a, int b) => (a * b) & _mask32;

/// String hash — JS `xmur3`. Consumes UTF-16 code units, so `codeUnitAt` here lines up
/// with `charCodeAt` there, including surrogate pairs in emoji seeds.
int _xmur3(String str) {
  var h = (1779033703 ^ str.length) & _mask32;
  for (var i = 0; i < str.length; i++) {
    h = _imul(h ^ str.codeUnitAt(i), 3432918353);
    h = ((h << 13) | (h >> 19)) & _mask32;
  }
  h = _imul(h ^ (h >> 16), 2246822507);
  h = _imul(h ^ (h >> 13), 3266489909);
  return (h ^ (h >> 16)) & _mask32;
}

/// Seeded random source. Construct with [Rng.new] and draw with [next].
class Rng {
  Rng(String seed) : _a = _xmur3(seed);

  int _a;

  /// The generator's position in its sequence. Opaque — save it, restore it, don't reason
  /// about the number.
  ///
  /// Exists so a saved run can resume mid-sequence. Determinism is the seed contract this
  /// codebase is built on, so restoring a run has to continue the identical draw sequence
  /// rather than restart it and re-deal cards the player has already seen.
  int get state => _a;

  void restore(int state) => _a = state & _mask32;

  /// JS `mulberry32` — returns a double in [0, 1).
  double next() {
    _a = (_a + 0x6D2B79F5) & _mask32;
    var t = _imul(_a ^ (_a >> 15), (1 | _a) & _mask32);
    t = (((t + _imul(t ^ (t >> 7), (61 | t) & _mask32)) & _mask32) ^ t) & _mask32;
    return ((t ^ (t >> 14)) & _mask32) / 4294967296.0;
  }

  /// Uniform integer in [0, n).
  int nextInt(int n) => (next() * n).floor();

  /// Uniform element of [arr].
  T pick<T>(List<T> arr) => arr[(next() * arr.length).floor()];

  /// Fisher-Yates over a copy; the input list is not mutated.
  List<T> shuffle<T>(List<T> arr) {
    final a = List<T>.of(arr);
    for (var i = a.length - 1; i > 0; i--) {
      final j = (next() * (i + 1)).floor();
      final tmp = a[i];
      a[i] = a[j];
      a[j] = tmp;
    }
    return a;
  }

  /// Weighted choice over (key, weight) pairs — used for shop rarity rolls.
  K weighted<K>(List<(K, num)> pairs) {
    final total = pairs.fold<num>(0, (s, p) => s + p.$2);
    var r = next() * total;
    for (final (k, w) in pairs) {
      if ((r -= w) < 0) return k;
    }
    return pairs.last.$1;
  }
}
