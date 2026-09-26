import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/cycle_provider.dart';
import '../theme/app_theme.dart';

/// Reached from Sign In's "Forgot password?" link. Uses the existing
/// server-side /reset_password endpoint (already wired up in
/// CycleProvider.resetPassword) -- this screen was the missing piece,
/// since Sign In's button previously had an empty onPressed.
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
  bool _obscurePassword = true;
  bool _isSubmitting = false;
  bool _isDone = false;

  /// False until the verification code has been requested. The server
  /// requires a code to confirm the reset, so this screen has two steps
  /// rather than one.
  bool _codeSent = false;

  /// Populated only when the backend runs with debug codes enabled
  /// (development). Never shown as if it were the real code in
  /// production, where the server omits it.
  String? _debugCode;
  String? _errorText;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _newPasswordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  /// Step 1: ask the server to email a verification code.
  Future<void> _handleRequestCode() async {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      setState(() => _errorText = 'Please enter your email address.');
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

    final result = await context.read<CycleProvider>().requestPasswordReset(
      email: email,
    );

    if (!mounted) return;

    setState(() {
      _isSubmitting = false;
      if (result.error != null) {
        _errorText = result.error;
      } else {
        _codeSent = true;
        _debugCode = result.debugCode;
      }
    });
  }

  /// Step 2: submit the emailed code with the new password.
  Future<void> _handleReset() async {
    final email = _emailController.text.trim();
    final code = _codeController.text.trim();
    final newPassword = _newPasswordController.text;
    final confirm = _confirmController.text;

    if (email.isEmpty || newPassword.isEmpty || confirm.isEmpty) {
      setState(() => _errorText = 'Please fill in all fields.');
      return;
    }
    if (code.isEmpty) {
      setState(() => _errorText = 'Please enter the verification code.');
      return;
    }
    if (!email.contains('@')) {
      setState(() => _errorText = 'Please enter a valid email address.');
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
      email: email,
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
                    : _codeSent
                    ? 'Enter the code we emailed you and choose a new password.'
                    : 'Enter your email and we will send a verification code.',
                style: AppTextStyles.sans(
                  size: 13,
                  color: AppColors.textSecondary,
                ),
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
              ] else ...[
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
                if (_codeSent) ...[
                  const SizedBox(height: 18),
                  Text(
                    'Verification Code',
                    style: AppTextStyles.sans(
                      size: 12,
                      weight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildTextField(
                    controller: _codeController,
                    hint: '8-digit code from your email',
                    keyboardType: TextInputType.number,
                  ),
                  if (_debugCode != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Development code: $_debugCode',
                      style: AppTextStyles.sans(
                        size: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
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
                    onPressed: _isSubmitting
                        ? null
                        : (_codeSent ? _handleReset : _handleRequestCode),
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
                            _codeSent ? 'Reset Password' : 'Send Code',
                            style: AppTextStyles.sans(
                              size: 14,
                              weight: FontWeight.w700,
                              color: Colors.white,
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
