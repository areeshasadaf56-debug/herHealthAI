import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/cycle_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/app_brand.dart';
import '../widgets/app_text_field.dart';
import 'sign_up_screen.dart';
import 'forgot_password_screen.dart';
import 'home_shell.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isSubmitting = false;
  String? _errorText;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorText = 'Please enter both email and password.');
      return;
    }
    if (!email.contains('@')) {
      setState(() => _errorText = 'Please enter a valid email address.');
      return;
    }

    setState(() {
      _errorText = null;
      _isSubmitting = true;
    });

    // Actually authenticate against the backend. This used to be a stub
    // that accepted any password and walked straight into the app, which
    // meant the session token every other screen depends on was never
    // issued -- /profile and /chat would then 401.
    final error = await context.read<CycleProvider>().signIn(
      email: email,
      password: password,
    );
    if (!mounted) return;

    if (error != null) {
      setState(() {
        _errorText = error;
        _isSubmitting = false;
      });
      return;
    }

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const HomeShell()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Center(child: const AppLogoMark(size: 72)),
                        const SizedBox(height: AppSpacing.sm),
                        const Center(
                          child: AppWordmark(
                            size: 26,
                            centered: true,
                            subtitle: 'Welcome back. Sign in to continue.',
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        AppTextField(
                          label: 'Email',
                          controller: _emailController,
                          hint: 'you@example.com',
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 18),
                        AppTextField(
                          label: 'Password',
                          controller: _passwordController,
                          hint: 'Enter your password',
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _handleSignIn(),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              size: 18,
                              color: AppColors.textSecondary,
                            ),
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),
                        ),
                        if (_errorText != null) ...[
                          const SizedBox(height: 12),
                          AppErrorBanner(message: _errorText!),
                        ],
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const ForgotPasswordScreen(),
                                ),
                              );
                            },
                            child: Text(
                              'Forgot password?',
                              style: AppTextStyles.sans(
                                size: 12,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          // No local styleFrom: the themed button already
                          // carries the radius, min height and a neutral
                          // disabled state. A local override here was also
                          // re-specifying `Colors.white` by hand.
                          child: ElevatedButton(
                            onPressed: _isSubmitting ? null : _handleSignIn,
                            child: _isSubmitting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                      valueColor: AlwaysStoppedAnimation(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : const Text('Sign In'),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                "Don't have an account?",
                                style: AppTextStyles.sans(
                                  size: 13,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              // A TextButton rather than a GestureDetector on
                              // a Text: gives the link a real 44pt touch
                              // target, a ripple, and a proper button role
                              // for screen readers.
                              TextButton(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const SignUpScreen(),
                                    ),
                                  );
                                },
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(0, 40),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text('Sign Up'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
