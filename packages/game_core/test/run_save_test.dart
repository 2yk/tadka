/// Saving and resuming a run.
///
/// The bar is not "the numbers come back". It is that a resumed run behaves EXACTLY like one
/// that was never interrupted — same cards dealt, same shop offers, same everything — because
/// determinism is the contract the whole engine is built on. A resume that re-deals is a
/// resume that quietly hands the player a different game.
@TestOn('vm')
library;

import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// Plays a few deterministic actions so the run is genuinely mid-flight, not freshly dealt.
void _advance(RunState run) {
  doSwap(run, [0, 1]);
  doCook(run, [0, 1]);
  run.coins += 12;
  run.kitchenLevel += 2;
}

RunState _roundTrip(RunState run) {
  final restored = runFromJson(runToJson(run));
  expect(restored, isNotNull, reason: 'a save written by this build must load in this build');
  return restored!;
}

void main() {
  setUp(() {
    profileStore = MemoryProfileStore();
    reloadProfile();
  });

  group('round trip', () {
    test('restores the visible state of a mid-run save', () {
      final run = newRun(seed: 'SAVE-1', stake: 3, deckId: 'home');
      _advance(run);
      final r = _roundTrip(run);

      expect(r.seed, run.seed);
      expect(r.stake, run.stake);
      expect(r.deckId, run.deckId);
      expect(r.cityIndex, run.cityIndex);
      expect(r.serviceIndex, run.serviceIndex);
      expect(r.coins, run.coins);
      expect(r.kitchenLevel, run.kitchenLevel);
      expect(r.score, run.score);
      expect(r.target, run.target);
      expect(r.totalScore, run.totalScore);
      expect(r.cooksLeft, run.cooksLeft);
      expect(r.swapsLeft, run.swapsLeft);
      expect(r.status, run.status);
      expect(r.hand.map((c) => c.id).toList(), run.hand.map((c) => c.id).toList());
      expect(r.deck.length, run.deck.length);
      expect(r.history.length, run.history.length);
    });

    test('the route survives — it is rebuilt from the seed, not stored', () {
      final run = newRun(seed: 'SAVE-ROUTE', stake: 1);
      final r = _roundTrip(run);
      expect(r.route.map((c) => c.id).toList(), run.route.map((c) => c.id).toList());
      expect(r.route.map((c) => c.targets).toList(), run.route.map((c) => c.targets).toList());
    });

    test('utensils and blends come back', () {
      final run = newRun(seed: 'SAVE-INV', stake: 1);
      run.utensils.addAll([kUtensilById['iron_tawa']!, kUtensilById['tandoor']!]);
      // Every deck now opens with a blend or two so the rack is discoverable, so this asserts
      // the whole rack rather than assuming it started empty.
      run.blends.addAll([kBlendById['sun_dry']!, kBlendById['chili_oil']!]);
      final expectedBlends = run.blends.map((b) => b.id).toList();
      final r = _roundTrip(run);
      expect(r.utensils.map((u) => u.id).toList(), ['iron_tawa', 'tandoor']);
      expect(r.blends.map((b) => b.id).toList(), expectedBlends);
    });
  });

  group('the guarantee that matters', () {
    test('a resumed run deals exactly what an uninterrupted one would', () {
      final live = newRun(seed: 'SAVE-DET', stake: 1);
      _advance(live);

      // Fork: one run carries on, the other is saved and resumed at the same instant.
      final resumed = _roundTrip(live);

      for (var i = 0; i < 6; i++) {
        doSwap(live, [0]);
        doSwap(resumed, [0]);
        expect(
          resumed.hand.map((c) => c.id).toList(),
          live.hand.map((c) => c.id).toList(),
          reason: 'draw $i diverged — the resumed run is playing a different game',
        );
      }
    });

    test('a resumed run rolls the same bazaar', () {
      final live = newRun(seed: 'SAVE-SHOP', stake: 1);
      _advance(live);
      final resumed = _roundTrip(live);

      for (var i = 0; i < 4; i++) {
        final a = rollOffers(live).map((o) => '${o.kind}:${o.id}:${o.cost}').toList();
        final b = rollOffers(resumed).map((o) => '${o.kind}:${o.id}:${o.cost}').toList();
        expect(b, a, reason: 'shop roll $i diverged');
      }
    });
  });

  group('blend-mutated cards', () {
    test('survive, because they are saved whole rather than looked up by id', () {
      final run = newRun(seed: 'SAVE-BLEND', stake: 1);
      run.blends.add(kBlendById['chili_oil']!);
      final chiliOil = run.blends.length - 1;
      final victim = run.hand.indexWhere((c) => c.family != 'spicy');
      expect(victim, isNot(-1));

      applyBlend(run, chiliOil, [victim]);
      final mutated = run.hand[victim];
      expect(mutated.family, 'spicy');
      expect(mutated.display, startsWith('Chili '));

      final r = _roundTrip(run);
      expect(r.hand[victim].family, 'spicy',
          reason: 'an id lookup would silently undo the blend the player paid for');
      expect(r.hand[victim].display, mutated.display);
      expect(r.hand[victim].rank, mutated.rank);
    });

    test('a Sun-Dry duplicate survives despite sharing an id with its source', () {
      final run = newRun(seed: 'SAVE-DUP', stake: 1);
      run.blends.add(kBlendById['sun_dry']!);
      // The deck's own starting blends sit ahead of it, so index by position from the end.
      final sunDry = run.blends.length - 1;
      final before = run.hand.length;
      applyBlend(run, sunDry, [0]);
      expect(run.hand.length, before + 1);

      final r = _roundTrip(run);
      expect(r.hand.length, before + 1);
      expect(r.hand.map((c) => c.id).toList(), run.hand.map((c) => c.id).toList());
    });

    test('a prized card stays prized', () {
      final run = newRun(seed: 'SAVE-PRIZED', stake: 1);
      run.hand[0] = run.hand[0].copyWith(prized: true);
      final r = _roundTrip(run);
      expect(r.hand[0].prized, isTrue, reason: 'prized is worth +25 flavour — losing it is a bug');
    });
  });

  group('the Long Route', () {
    test('survives, including its generated city and merged critic', () {
      final run = newRun(seed: 'SAVE-ENDLESS', stake: 1);
      startEndlessCity(run, 3);
      expect(run.endlessCityObj, isNotNull);

      final r = _roundTrip(run);
      expect(r.endless, isTrue);
      expect(r.endlessCity, 3);
      expect(r.endlessCityObj!.id, run.endlessCityObj!.id);
      expect(r.endlessCityObj!.targets, run.endlessCityObj!.targets);
      expect(r.endlessBase, run.endlessBase);
      // The Long Route generates critics at runtime, so they exist in no catalog. A lookup
      // by id would come back empty and quietly drop the boss rule.
      expect(r.endlessCityObj!.criticObj?.name, run.endlessCityObj!.criticObj?.name);
      expect(r.endlessCityObj!.criticObj?.maxCards, run.endlessCityObj!.criticObj?.maxCards);
    });
  });

  group('refusing a bad save', () {
    test('a future version is declined rather than guessed at', () {
      final run = newRun(seed: 'SAVE-V', stake: 1);
      final j = runToJson(run)..['v'] = kRunSaveVersion + 1;
      expect(runFromJson(j), isNull);
    });

    test('a save naming a utensil this build does not have is declined', () {
      final run = newRun(seed: 'SAVE-GONE', stake: 1);
      final j = runToJson(run)..['utensils'] = ['a_utensil_that_was_removed'];
      expect(runFromJson(j), isNull,
          reason: 'resuming a run short one utensil is worse than starting fresh');
    });

    test('a truncated save is declined without throwing', () {
      final run = newRun(seed: 'SAVE-TRUNC', stake: 1);
      final j = runToJson(run)..remove('hand');
      expect(runFromJson(j), isNull);
    });

    test('garbage is declined without throwing', () {
      expect(runFromJson(<String, Object?>{}), isNull);
      expect(runFromJson(<String, Object?>{'v': kRunSaveVersion}), isNull);
    });
  });

  group('resume prompt', () {
    test('offers a run in progress and not a finished one', () {
      final run = newRun(seed: 'SAVE-DONE', stake: 1);
      expect(isResumable(run), isTrue);
      run.status = 'won';
      expect(isResumable(run), isFalse);
      run.status = 'lost';
      expect(isResumable(run), isFalse);
    });

    test('describes where the player left off', () {
      final run = newRun(seed: 'SAVE-DESC', stake: 1);
      final s = resumeSummary(run);
      expect(s, contains(cityOf(run).name));
      expect(s, contains('${run.target}'));
    });
  });
}
