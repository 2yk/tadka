/// The Daily Route — one seeded run per day, the same for everyone.
///
/// The concept doc calls this the #1 "come back tomorrow" hook, and it costs nothing to run:
/// no server, no accounts. Every run has always been a pure function of its seed, so a date
/// string IS the challenge — two players on the same day get identical cards, shops and
/// critics, and can compare scores honestly.
///
/// The date is taken in LOCAL time deliberately. A UTC rollover would flip the puzzle
/// mid-evening for players east of Greenwich, which for an India-first game is most of the
/// audience.
library;

import 'package:game_core/game_core.dart' as gc;

/// The seed for [day]. Stable, human-readable, and obviously a date if it shows up in a bug
/// report.
String dailySeed(DateTime day) {
  final y = day.year.toString().padLeft(4, '0');
  final m = day.month.toString().padLeft(2, '0');
  final d = day.day.toString().padLeft(2, '0');
  return 'DAILY-$y$m$d';
}

/// Calendar key used to decide whether today's run has been played.
String dayKey(DateTime day) => dailySeed(day).substring(6);

/// Everything the UI needs to describe today's challenge.
class DailyStatus {
  const DailyStatus({
    required this.seed,
    required this.playedToday,
    required this.streak,
    required this.bestScore,
  });

  final String seed;
  final bool playedToday;
  final int streak;
  final int bestScore;
}

DailyStatus dailyStatus(DateTime now) {
  final d = gc.profile.daily;
  return DailyStatus(
    seed: dailySeed(now),
    playedToday: d.lastPlayed == dayKey(now),
    streak: d.streak,
    bestScore: d.bestDailyScore,
  );
}

/// Records a finished Daily run.
///
/// The streak advances only when yesterday was the previous entry — playing today after a
/// gap restarts at 1 rather than silently continuing, which is the whole point of a streak.
/// Replaying the same day never double-counts.
void recordDaily(DateTime now, int totalScore) {
  final d = gc.profile.daily;
  final today = dayKey(now);
  if (d.lastPlayed == today) {
    if (totalScore > d.bestDailyScore) d.bestDailyScore = totalScore;
    gc.saveProfile();
    return;
  }
  final yesterday = dayKey(now.subtract(const Duration(days: 1)));
  d.streak = d.lastPlayed == yesterday ? d.streak + 1 : 1;
  d.lastPlayed = today;
  if (totalScore > d.bestDailyScore) d.bestDailyScore = totalScore;
  gc.saveProfile();
}

/// The Daily is played on fixed settings so every player faces the same run — a deck or stake
/// choice would make scores incomparable, which is the only thing the mode is for.
const String kDailyDeck = 'home';
const int kDailyStake = 1;
