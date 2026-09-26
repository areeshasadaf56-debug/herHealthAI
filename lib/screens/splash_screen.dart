import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/cycle_provider.dart';
import '../services/backend_launcher.dart';
import 'sign_in_screen.dart';
import 'home_shell.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  /// False until we've confirmed the API is reachable. The app used to
  /// assume the backend was already running, so anyone who started the
  /// Flutter app before the Python server hit "could not reach the
  /// server" on every screen. We now start it ourselves.
  bool _apiReady = false;
  bool _apiFailed = false;

  @override
  void initState() {
    super.initState();
    _navigateAfterDelay();
  }

  Future<void> _navigateAfterDelay() async {
    final cycle = context.read<CycleProvider>();
    final start = DateTime.now();

    // Wait until CycleProvider has actually finished reading the saved
    // login state from SharedPreferences. A fixed delay isn't reliable —
    // on a real phone (especially the first launch after install) that
    // read can take longer than the timer, so isLoggedIn was still at its
    // default (false) when we checked it, which bounced logged-in users
    // back to Sign In every time.
    while (!cycle.isLoaded) {
      await Future.delayed(const Duration(milliseconds: 50));
      if (!mounted) return;
    }

    // Bring the API up (or confirm it is already up). This must NOT block
    // the UI for long: if the backend is slow to load its model, or can't
    // start at all, the user would sit on a frozen splash and conclude the
    // app is broken. So we give it a short bounded window, then move on
    // regardless -- the launcher keeps starting the backend in the
    // background, and any screen that needs the API reports its own error.
    final ready = await Future.any<bool>([
      BackendLauncher.ensureRunning(),
      Future<bool>.delayed(const Duration(seconds: 6), () => false),
    ]).then((value) => value);
    if (!mounted) return;
    setState(() {
      _apiReady = ready;
      _apiFailed = !ready;
    });

    // Keep a small minimum splash duration so it doesn't flash instantly
    // on fast devices.
    const minSplash = Duration(milliseconds: 900);
    final elapsed = DateTime.now().difference(start);
    if (elapsed < minSplash) {
      await Future.delayed(minSplash - elapsed);
    }

    if (!mounted) return;

    final destination = cycle.isLoggedIn
        ? const HomeShell()
        : const SignInScreen();

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => destination),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(
                Icons.favorite_rounded,
                color: Colors.white,
                size: 44,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Saheli',
              style: AppTextStyles.serif(size: 28, weight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Your wellness companion',
              style: AppTextStyles.sans(
                size: 13,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _apiReady
                  ? 'Connected'
                  : (_apiFailed
                        ? 'Starting local service...'
                        : 'Connecting...'),
              style: AppTextStyles.sans(
                size: 11,
                color: _apiFailed
                    ? AppColors.textSecondary
                    : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 36),
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
