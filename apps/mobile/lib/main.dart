/// Spice Route — M1 Flutter shell.
///
/// All rules live in `package:game_core`; this app is presentation only.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:game_core/game_core.dart' as gc;
import 'package:shared_preferences/shared_preferences.dart';

import 'game_controller.dart';
import 'screens/bazaar_screen.dart';
import 'screens/help_sheet.dart';
import 'screens/recipe_book_screen.dart';
import 'screens/service_screen.dart';
import 'screens/start_screen.dart';
import 'screens/summary_screen.dart';
import 'theme.dart';
import 'widgets/juice.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  // Inject persistence before the profile is first read, so unlocks survive a relaunch.
  final prefs = await SharedPreferences.getInstance();
  gc.profileStore = PrefsProfileStore(prefs);
  gc.reloadProfile();
  runApp(TadkaApp(prefs: prefs));
}

class TadkaApp extends StatelessWidget {
  const TadkaApp({required this.prefs, super.key});

  final SharedPreferences prefs;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Spice Route',
    debugShowCheckedModeBanner: false,
    theme: T.theme(),
    home: GameRoot(prefs: prefs),
  );
}

class GameRoot extends StatefulWidget {
  const GameRoot({required this.prefs, super.key});

  final SharedPreferences prefs;

  @override
  State<GameRoot> createState() => _GameRootState();
}

class _GameRootState extends State<GameRoot> {
  late final GameController _controller = GameController(widget.prefs);
  final _particles = ParticleController();
  final _shake = ShakeController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChange);
  }

  void _onChange() => setState(() {});

  @override
  void dispose() {
    _controller.removeListener(_onChange);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final Widget screen = switch (c.phase) {
      Phase.start => StartScreen(controller: c),
      Phase.service => ServiceScreen(controller: c, particles: _particles, shake: _shake),
      Phase.bazaar => BazaarScreen(controller: c),
      Phase.recipeBook => RecipeBookScreen(onClose: c.closeRecipeBook),
      Phase.help => HelpSheet(onClose: c.closeHelp),
      Phase.summary || Phase.victory => SummaryScreen(controller: c),
    };

    return Scaffold(
      backgroundColor: T.bg,
      body: ParticleField(
        controller: _particles,
        child: ShakeBox(
          controller: _shake,
          child: Stack(
            children: [
              AnimatedSwitcher(
                duration: Motion.screenFade,
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween(begin: const Offset(0, 0.03), end: Offset.zero).animate(anim),
                    child: child,
                  ),
                ),
                child: KeyedSubtree(key: ValueKey(c.phase), child: screen),
              ),
              if (c.toasts.isNotEmpty)
                _UnlockToast(message: c.toasts.first, onDismiss: c.dismissToast),
            ],
          ),
        ),
      ),
    );
  }
}

/// Achievement / unlock banner. Unlocks are permanent and never lost on death, so this is the
/// one moment of progress a losing run still delivers — worth surfacing prominently.
class _UnlockToast extends StatelessWidget {
  const _UnlockToast({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Positioned(
    top: MediaQuery.paddingOf(context).top + 8,
    left: 16,
    right: 16,
    child: GestureDetector(
      onTap: onDismiss,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, -12 * (1 - t)), child: child),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: T.panel2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: T.brass, width: 1.5),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 14)],
          ),
          child: Row(
            children: [
              Expanded(child: Text(message, style: T.body.copyWith(fontWeight: FontWeight.w600))),
              const Icon(Icons.close, size: 16, color: T.dim),
            ],
          ),
        ),
      ),
    ),
  );
}
