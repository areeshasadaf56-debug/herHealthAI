import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/cycle_provider.dart';
import '../theme/app_theme.dart';

/// Reached from Sign In's "Forgot password?" link -- a 2-step reset:
///
///   Step 1: the user enters their email and a 6-digit code is emailed
///           out (proving they own the address).
///   Step 2: they enter the code + the new password here, and the server
///           only applies the change once the code checks out. (The old
///           one-screen version just accepted {email, new_password},
///           which would have let anyone reset anybody's password.)
///
/// DEV MODE: with no SMTP configured on the server, the code is returned
/// directly and displayed in a highlighted chip instead of being emailed.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmController = TextEditingController();

  int _step = 0; // 0 = email, 1 = code + new password
  String? _devCode;
  bool _isSubmitting = false;
  bool _isDone = false;
  bool _obscurePassword = true;
  String? _errorText;
  int _resendIn = 0;
  Timer? _resendTimer;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _newPasswordController.dispose();
    _confirmController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendIn = 60);
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

  Future<void> _handleSendCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _errorText = 'Please enter your email.');
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

    // Same generic result whether or not the email is registered -- no
    // account enumeration from this screen. If nothing arrives, the user
    // checks their inbox/spam and can resend after the cooldown.
    final result = await context
        .read<CycleProvider>()
        .requestVerificationCode(email: email, purpose: 'reset');

    if (!mounted) return;

    setState(() {
      _isSubmitting = false;
      _devCode = result.devCode;
      if (result.error != null) {
        _errorText = result.error;
      } else {
        _step = 1;
        _startCooldown();
      }
    });
  }

  Future<void> _handleReset() async {
    final code = _codeController.text.trim();
    final newPassword = _newPasswordController.text;
    final confirm = _confirmController.text;

    if (code.isEmpty || newPassword.isEmpty || confirm.isEmpty) {
      setState(() => _errorText = 'Please fill in all fields.');
      return;
    }
    if (newPassword.length < 6) {
      setState(() => _errorText = 'Password must be at least 6 characters.');
      return;
    }
    if (newPassword != confirm) {
      setState(() => _errorText = 'Passwords do not match.');
      return;
    }

    setState(() {
      _errorText = null;
      _isSubmitting = true;
    });

    final error = await context.read<CycleProvider>().resetPassword(
          email: _emailController.text.trim(),
          code: code,
          newPassword: newPassword,
        );

    if (!mounted) return;

    if (error != null) {
      setState(() {
        _errorText = error;
        _isSubmitting = false;
      });
      return;
    }

    setState(() {
      _isSubmitting = false;
      _isDone = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final emailText = _emailController.text.trim();

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
              Text('Reset Password', style: AppTextStyles.serif(size: 24)),
              const SizedBox(height: 8),
              Text(
                _isDone
                    ? 'Your password has been updated.'
                    : _step == 0
                        ? "We'll email you a 6-digit code to prove this is "
                            'your account. Then you choose the new password.'
                        : 'Enter the code we sent to $emailText and choose a '
                            'new password.',
                style: AppTextStyles.sans(
                  size: 13,
                  color: AppColors.textSecondary,
                ).copyWith(height: 1.4),
              ),
              const SizedBox(height: 32),
              if (_isDone) ...[
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
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Back to Sign In',
                      style: AppTextStyles.sans(
                        size: 14,
                        weight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ] else if (_step == 0) ...[
                Text(
                  'Email',
                  style: AppTextStyles.sans(size: 12, weight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                _buildTextField(
                  controller: _emailController,
                  hint: 'you@example.com',
                  keyboardType: TextInputType.emailAddress,
                ),
                if (_errorText != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _errorText!,
                    style: AppTextStyles.sans(
                      size: 12,
                      color: AppColors.periodRed,
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                _submitButton(label: 'Send Code', onPressed: _handleSendCode),
              ] else ...[
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
                Text(
                  '6-digit code',
                  style: AppTextStyles.sans(size: 12, weight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                _buildTextField(
                  controller: _codeController,
                  hint: 'From your email',
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 18),
                Text(
                  'New Password',
                  style: AppTextStyles.sans(size: 12, weight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                _buildTextField(
                  controller: _newPasswordController,
                  hint: 'At least 6 characters',
                  obscureText: _obscurePassword,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Confirm New Password',
                  style: AppTextStyles.sans(size: 12, weight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                _buildTextField(
                  controller: _confirmController,
                  hint: 'Re-enter new password',
                  obscureText: _obscurePassword,
                ),
                if (_errorText != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _errorText!,
                    style: AppTextStyles.sans(
                      size: 12,
                      color: AppColors.periodRed,
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                _submitButton(label: 'Reset Password', onPressed: _handleReset),
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed: (_resendIn > 0 || _isSubmitting)
                        ? null
                        : _handleSendCode,
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

  Widget _submitButton({required String label, required VoidCallback onPressed}) {
    return SizedBox(
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
        onPressed: _isSubmitting ? null : onPressed,
        child: _isSubmitting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: AppTextStyles.sans(
                  size: 14,
                  weight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    bool obscureText = false,
    TextInputType? keyboardType,
    Widget? suffixIcon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        style: AppTextStyles.sans(size: 14),
        cursorColor: AppColors.primary,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AppTextStyles.sans(
            size: 13,
            color: AppColors.textSecondary,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          suffixIcon: suffixIcon,
        ),
      ),
    );
  }
}
