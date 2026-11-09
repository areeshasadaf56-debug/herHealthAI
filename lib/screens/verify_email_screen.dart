import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/cycle_provider.dart';
import '../theme/app_theme.dart';
import 'home_shell.dart';

/// The code-entry step used right after sign-up: the account exists on
/// the server, but it can't be used until the 6-digit code emailed to
/// the user is confirmed. A code is requested automatically when this
/// screen opens and can be re-sent afterwards (the server enforces a
/// 60-second cooldown between sends).
///
/// LOCAL DEV ONLY: when the server has no SMTP mailbox configured, the
/// code is returned directly and displayed in a highlighted "dev mode"
/// chip instead of being emailed. On a configured production server this
/// chip can never appear.
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key, required this.email});

  final String email;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final _codeController = TextEditingController();
  bool _requesting = false;
  bool _verifying = false;
  String? _requestError;
  String? _verifyError;
  String? _devCode;
  int _resendIn = 0;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    _requestCode();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  Future<void> _requestCode() async {
    if (_requesting) return;
    setState(() {
      _requesting = true;
      _requestError = null;
    });

    final result = await context
        .read<CycleProvider>()
        .requestVerificationCode(email: widget.email, purpose: 'signup');

    if (!mounted) return;

    if (result.error != null) {
      setState(() {
        _requesting = false;
        _requestError = result.error;
      });
      return;
    }

    setState(() {
      _requesting = false;
      _devCode = result.devCode;
      _resendIn = 60;
    });
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final next = _resendIn - 1;
      setState(() => _resendIn = next <= 0 ? 0 : next);
      if (next <= 0) timer.cancel();
    });
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _verifyError = 'Enter the 6-digit code from your email.');
      return;
    }

    setState(() {
      _verifyError = null;
      _verifying = true;
    });

    final error = await context
        .read<CycleProvider>()
        .confirmVerificationCode(
          email: widget.email,
          purpose: 'signup',
          code: code,
        );

    if (!mounted) return;

    if (error != null) {
      setState(() {
        _verifyError = error;
        _verifying = false;
      });
      return;
    }

    // Verified + signed in -- the confirm response carried the account's
    // first session token, so go straight to the app like a sign-in.
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: const Icon(
                    Icons.arrow_back,
                    size: 18,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text('Verify Email', style: AppTextStyles.serif(size: 24)),
              const SizedBox(height: 8),
              Text(
                'We sent a 6-digit code to',
                style: AppTextStyles.sans(
                  size: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.email,
                style: AppTextStyles.sans(
                  size: 14,
                  weight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Enter it below to activate your account. The code expires '
                'in 10 minutes.',
                style: AppTextStyles.sans(
                  size: 12,
                  color: AppColors.textSecondary,
                ).copyWith(height: 1.4),
              ),
              const SizedBox(height: 24),
              if (_requesting)
                const Center(child: CircularProgressIndicator())
              else ...[
                if (_devCode != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.moodYellow.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.moodYellow.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Text(
                      'DEV MODE: this server has no email configured, so '
                      'your code is $_devCode (normally this arrives in '
                      'your email inbox).',
                      style: AppTextStyles.sans(
                        size: 12,
                        color: AppColors.textPrimary,
                      ).copyWith(height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (_requestError != null) ...[
                  Text(
                    _requestError!,
                    style: AppTextStyles.sans(
                      size: 12,
                      color: AppColors.periodRed,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  autofocus: true,
                  cursorColor: AppColors.primary,
                  style: AppTextStyles.sans(
                    size: 22,
                    weight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ).copyWith(letterSpacing: 8),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '······',
                    hintStyle: AppTextStyles.sans(
                      size: 20,
                      color: AppColors.textSecondary,
                    ),
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: AppColors.cardBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: AppColors.cardBorder),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                if (_verifyError != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _verifyError!,
                    style: AppTextStyles.sans(
                      size: 12,
                      color: AppColors.periodRed,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _verifying ? null : _verify,
                    child: _verifying
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'Verify',
                            style: AppTextStyles.sans(
                              size: 14,
                              weight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed:
                        (_resendIn > 0 || _requesting) ? null : _requestCode,
                    child: Text(
                      _resendIn > 0
                          ? 'Resend code ($_resendIn s)'
                          : 'Didn\'t get it? Send a new code',
                      style: AppTextStyles.sans(
                        size: 13,
                        weight: FontWeight.w600,
                        color: _resendIn > 0
                            ? AppColors.textSecondary
                            : AppColors.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
