// Headless balance simulator — the Dart successor to tools/sim.mjs.
//
// Target CLI (build spec §9):
//   dart run tools/sim -n 2000 --policy random
// printing the score distribution, average death city and utensil pick stats.
//
// Scaffold only: argument parsing and the bot land with the game_core port.

import 'dart:io';

void main(List<String> arguments) {
  stdout.writeln('tadka sim — not implemented yet.');
  stdout.writeln('The engine port into packages/game_core comes first;');
  stdout.writeln('until then use the M0 simulator: node tools/sim.mjs');
  exitCode = 0;
}
