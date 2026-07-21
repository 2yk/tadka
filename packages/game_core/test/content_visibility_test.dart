/// What `kShowAllContent` does, in both positions.
///
/// The build ships content-complete and discovery-gated, and during an internal test that
/// gating hides most of what exists: 95 utensils of which a fresh profile is offered 74, three
/// recipes shown as `? ? ?`, four of five decks and seven of eight stakes padlocked. None of
/// that is discoverable in a few days of play, so the internal build turns it all on.
///
/// **Both positions ship**, which is why both are asserted here. The `on` group is the promise
/// to the tester: everything the game contains is reachable from run one. The `off` group is
/// the promise to the eventual player: the ladder still exists, still gates, and still hands
/// out rewards — so flipping one boolean restores a normal progression build and nothing else
/// has to move.
///
/// The switch must also stay a *read* override. Every write path — `unlockThing`,
/// `setStakeProgress`, `recordRecipe`, the achievement bus — has to keep recording the real
/// progression underneath it, or the flag stops being reversible and a tester's save becomes
/// meaningless. That is the last group.
@TestOn('vm')
library;

import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

void main() {
  final showAllDefault = kShowAllContent;

  setUp(() {
    profileStore = MemoryProfileStore();
    profile = defaultProfile();
    drainUnlockQueue();
    kShowAllContent = showAllDefault;
  });
  tearDown(() {
    kShowAllContent = showAllDefault;
    activeDeckCatalog = kDecks;
  });

  test('the internal-testing switch ships ON', () {
    // Deliberate, and the whole point of the task that added it. If this ever needs to flip
    // for a public build, flip it here and this test — nothing else.
    expect(showAllDefault, isTrue,
        reason: 'the internal build must show its content; see the doc on kShowAllContent');
  });

  group('with the switch ON, everything is reachable from run one', () {
    test('every utensil in the catalog can be offered', () {
      final pool = unlockedUtensilPool().map((u) => u.id).toSet();
      expect(pool.length, equals(kUtensils.length));
      for (final u in kUtensils) {
        expect(pool, contains(u.id), reason: '${u.id} cannot be offered');
        expect(isUnlocked('utensil', u.id), isTrue);
      }
      // Including the ones the ladder gates, which is what the owner could not see.
      for (final id in [...kStakeGatedUtensils.keys, 'clay_handi', 'tandoor', 'jubako']) {
        expect(isUnlocked('utensil', id), isTrue, reason: '$id is still locked');
      }
    });

    test('the shop really does deal Rares to a fresh profile', () {
      // The pool being open is not the same as the shop using it: `rollOffers` snapshots
      // `unlockedUtensilPool` and then filters by rolled rarity. Play enough bazaars that a
      // 10%-weighted Rare is a near certainty, and check one actually turns up.
      final seen = <String>{};
      for (var i = 0; i < 40; i++) {
        final run = newRun(seed: 'SHOP-$i');
        for (final o in rollOffers(run)) {
          if (o.kind == 'utensil') seen.add(o.id);
        }
      }
      final rares = seen.where((id) => kUtensilById[id]!.rarity == 'rare');
      expect(rares, isNotEmpty, reason: 'a fresh profile never met a Rare');
      expect(seen.any((id) => !kStartUtensils.contains(id)), isTrue,
          reason: 'the shop is still drawing only from the starter set');
    });

    test('every blend can be offered', () {
      for (final b in kBlends) {
        expect(isUnlocked('blend', b.id), isTrue, reason: '${b.id} is locked');
      }
      expect(activeBlendCatalog.length, equals(kBlends.length));
      final seen = <String>{};
      for (var i = 0; i < 60; i++) {
        final run = newRun(seed: 'BLENDSHOP-$i');
        for (final o in rollOffers(run)) {
          if (o.kind == 'blend') seen.add(o.id);
        }
      }
      expect(seen, isNotEmpty, reason: 'the bazaar never offered a blend at all');
    });

    test('every deck is selectable, and every stake with it', () {
      final playable = kDecks.where((d) => !d.reserved).map((d) => d.id).toList();
      expect(unlockedDecks().map((d) => d.id).toList(), equals(playable));
      for (final id in playable) {
        expect(maxStake(id), equals(kStakes.length), reason: '$id stake ladder is closed');
      }
      // Reserved decks stay out: Monsoon Larder has no mechanics behind it, so listing it
      // would show a tester an empty box rather than content.
      expect(unlockedDecks().any((d) => d.reserved), isFalse);
    });

    test('a run can actually be started on every deck at every stake', () {
      for (final d in kDecks.where((d) => !d.reserved)) {
        for (var s = 1; s <= kStakes.length; s++) {
          profile = defaultProfile();
          final run = newRun(seed: 'ALL-${d.id}-$s', stake: s, deckId: d.id);
          expect(run.stake, equals(s));
          expect(run.deckId, equals(d.id));
          expect(run.hand.length, equals(8));
        }
      }
    });
  });

  group('with the switch OFF, the discovery ladder is exactly as it was', () {
    setUp(() => kShowAllContent = false);

    test('a fresh profile is offered only the starter utensils', () {
      expect(unlockedUtensilPool().map((u) => u.id).toSet(), equals(kStartUtensils.toSet()));
      expect(isUnlocked('utensil', 'clay_handi'), isFalse);
      expect(isUnlocked('utensil', 'grandmother_ladle'), isFalse);
      expect(kUtensils.where((u) => !isUnlocked('utensil', u.id)), isNotEmpty,
          reason: 'nothing is gated — the unlock ladder has nothing left to give');
    });

    test('only the Home deck is selectable, at stake 1', () {
      expect(unlockedDecks().map((d) => d.id).toList(), equals(['home']));
      expect(maxStake('home'), equals(1));
      expect(isUnlocked('deck', 'royal'), isFalse);
    });

    test('an earned unlock still opens exactly what it names', () {
      unlockThing('utensil', 'clay_handi');
      expect(isUnlocked('utensil', 'clay_handi'), isTrue);
      expect(isUnlocked('utensil', 'tandoor'), isFalse, reason: 'one unlock opened two things');
      unlockThing('deck', 'coastal');
      expect(unlockedDecks().map((d) => d.id).toList(), equals(['home', 'coastal']));
      setStakeProgress('coastal', 4);
      expect(maxStake('coastal'), equals(4));
      expect(maxStake('home'), equals(1), reason: 'stake progress is per deck');
    });

    test('the achievement bus still grants what it always granted', () {
      emit('dish_played', const AchievementPayload(pattern: 'flush', cards: 5));
      expect(profile.achievementsDone, contains('first_flush'));
      expect(isUnlocked('utensil', 'golden_sieve'), isTrue);
      expect(drainUnlockQueue().any((m) => m.contains('First Flush')), isTrue);
    });
  });

  group('the switch is a read override, never a write one', () {
    test('unlocks, stake progress and recipes are still recorded with it ON', () {
      expect(kShowAllContent, isTrue);
      // Nothing below reads back through `isUnlocked` — these assert the SAVE, which is what
      // makes the flag reversible. Flip it off afterwards and the profile is a real profile.
      expect(unlockThing('utensil', 'clay_handi'), isTrue, reason: 'not written to the save');
      expect(unlockThing('utensil', 'clay_handi'), isFalse, reason: 'toast fired twice');
      expect(profile.unlocks['utensils'], equals(['clay_handi']));

      setStakeProgress('home', 3);
      expect(profile.stakeProgress['home'], equals(3));

      recordRecipe('perfect_palate');
      expect(profile.recipesDiscovered, contains('perfect_palate'));
      expect(drainUnlockQueue().any((m) => m.contains('Secret recipe found')), isTrue);

      emit('dish_played', const AchievementPayload(pattern: 'full_house', cards: 5));
      expect(profile.achievementsDone, contains('feast_mode'));
      expect(profile.unlocks['utensils'], contains('butchers_block'));

      // And now the reversal: with the flag off, the save that was built while it was on is
      // an ordinary gated profile.
      kShowAllContent = false;
      expect(isUnlocked('utensil', 'clay_handi'), isTrue);
      expect(isUnlocked('utensil', 'butchers_block'), isTrue);
      expect(isUnlocked('utensil', 'tandoor'), isFalse);
      expect(maxStake('home'), equals(3));
    });

    test('a stake win still advances the ladder with it ON', () {
      final run = newRun(seed: 'LADDER', stake: 3, deckId: 'home');
      onRunWon(run);
      expect(profile.stakeProgress['home'], equals(4));
      expect(profile.unlocks['utensils'], contains('grandmother_ladle'),
          reason: 'the stake-3 reward still has to be granted and saved');
    });
  });

  group('every deck opens with a blend, so the rack is discoverable', () {
    test('each playable deck starts with at least one', () {
      for (final d in kDecks.where((d) => !d.reserved)) {
        expect(d.startBlends, isNotEmpty, reason: '${d.id} never shows a blend rack');
        for (final id in d.startBlends) {
          expect(kBlendById[id], isNotNull, reason: '${d.id}: $id is not a blend');
        }
      }
    });

    test('a new run really holds them', () {
      for (final d in kDecks.where((d) => !d.reserved)) {
        profile = defaultProfile();
        final run = newRun(seed: 'START-${d.id}', deckId: d.id);
        expect(run.blends.map((b) => b.id).toList(), equals(d.startBlends),
            reason: '${d.id} did not deal its starting blends');
        expect(run.blends.length, lessThanOrEqualTo(3), reason: '${d.id} is over the rack cap');
      }
    });

    test('they teach rather than power a build', () {
      // Cheap, ported, well-understood verbs only — nothing that makes the opening hand
      // strong. A starting blend is a tutorial, not an advantage.
      const teaching = {'chili_oil', 'sea_salt', 'fermentation', 'sun_dry', 'sharpen', 'mise', 'brine'};
      for (final d in kDecks.where((d) => !d.reserved)) {
        for (final id in d.startBlends) {
          expect(teaching, contains(id), reason: '${d.id}: $id is a purchase, not a lesson');
          expect(kBlendById[id]!.cost, lessThanOrEqualTo(4), reason: '$id is a premium blend');
        }
      }
    });

    test('the deck identity line names them, so the picker is honest', () {
      for (final d in kDecks.where((d) => !d.reserved)) {
        for (final id in d.startBlends) {
          expect(d.identity, contains(kBlendById[id]!.name),
              reason: '${d.id} starts with ${kBlendById[id]!.name} without saying so');
        }
      }
    });

    // The seam that keeps the recorded run traces honest. `newRun` copies `startBlends` into
    // `run.blends`, which every recorded step snapshots, so the ported decks have to stay
    // exactly as the JS build knows them and only this one field may differ.
    test('the ported decks differ from the live ones in startBlends and identity only', () {
      expect(kPortedDecks.length, equals(kDecks.length));
      for (var i = 0; i < kDecks.length; i++) {
        final live = kDecks[i];
        final ported = kPortedDecks[i];
        expect(live.id, equals(ported.id));
        expect(live.name, equals(ported.name));
        expect(live.familyDelta, equals(ported.familyDelta));
        expect(live.trim, equals(ported.trim));
        expect(live.startRareUtensil, equals(ported.startRareUtensil));
        expect(live.cooks, equals(ported.cooks));
        expect(live.utensilSlots, equals(ported.utensilSlots));
        expect(live.reserved, equals(ported.reserved));
        // The pantry itself must be identical, or the traces are replaying a different deck.
        expect(buildPantry(live).map((c) => c.id).toList(),
            equals(buildPantry(ported).map((c) => c.id).toList()));
      }
    });

    test('pinning activeDeckCatalog is what newRun actually reads', () {
      activeDeckCatalog = kPortedDecks;
      profile = defaultProfile();
      expect(newRun(seed: 'PINNED', deckId: 'home').blends, isEmpty);
      activeDeckCatalog = kDecks;
      profile = defaultProfile();
      expect(newRun(seed: 'PINNED', deckId: 'home').blends, isNotEmpty);
    });
  });
}
