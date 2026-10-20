import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_buttons.dart';
import '../../data/services/email_otp_auth.dart';
import '../../data/services/parking_state_manager.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback onLoginSuccess;

  const LoginScreen({super.key, required this.onLoginSuccess});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // 0: Email Entry, 1: 6-Digit OTP Verification
  int _step = 0;

  final _emailController = TextEditingController(
    text: AppConfig.kDemoMode ? 'anuk@example.com' : '',
  );
  final List<TextEditingController> _otpControllers =
      List.generate(6, (i) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (i) => FocusNode());

  int _resendCountdown = 0;
  Timer? _timer;
  bool _isSending = false;
  bool _isVerifying = false;
  String? _emailError;
  String? _otpError;
  String? _lastSentCode;

  @override
  void dispose() {
    _emailController.dispose();
    for (var c in _otpControllers) {
      c.dispose();
    }
    for (var f in _focusNodes) {
      f.dispose();
    }
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdown([int seconds = 60]) {
    _timer?.cancel();
    _resendCountdown = seconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendCountdown > 0) {
        setState(() => _resendCountdown--);
      } else {
        timer.cancel();
      }
    });
  }

  bool _validateEmail(String email) {
    final emailRegex = RegExp(r'^[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+$');
    return emailRegex.hasMatch(email);
  }

  String _getOtpValue() {
    return _otpControllers.map((c) => c.text.trim()).join();
  }

  void _autoFillCode() {
    if (_lastSentCode == null || _lastSentCode!.length != 6) return;
    for (int i = 0; i < 6; i++) {
      _otpControllers[i].text = _lastSentCode![i];
    }
    setState(() {
      _otpError = null;
    });
    _focusNodes[5].unfocus();
  }

  void _handleSendCode() async {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      setState(() => _emailError = 'Please enter your email address');
      return;
    }

    if (!_validateEmail(email)) {
      setState(() => _emailError = 'Please enter a valid campus email (e.g. name@sliit.lk)');
      return;
    }

    setState(() {
      _emailError = null;
      _isSending = true;
    });

    try {
      final state = context.read<ParkingStateManager>();
      final code = await state.sendVerificationOtp(email);

      if (!mounted) return;

      // Clear any previous OTP inputs
      for (var c in _otpControllers) {
        c.clear();
      }

      setState(() {
        _lastSentCode = code;
        _isSending = false;
        _otpError = null;
        _step = 1;
      });

      _startCountdown(60);

      // Focus first digit box after transition
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _focusNodes.isNotEmpty) {
          _focusNodes[0].requestFocus();
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _emailError = e is OtpAuthException
            ? e.message
            : 'Failed to generate verification code. Please try again.';
      });
    }
  }

  void _handleVerifyCode() async {
    final email = _emailController.text.trim();
    final otp = _getOtpValue();

    if (otp.length < 6) {
      setState(() => _otpError = 'Please enter the complete 6-digit verification code');
      return;
    }

    setState(() {
      _otpError = null;
      _isVerifying = true;
    });

    final state = context.read<ParkingStateManager>();
    final result = await state.verifyOtp(email, otp);

    if (!mounted) return;

    if (result.isValid) {
      setState(() => _isVerifying = false);
      widget.onLoginSuccess();
    } else {
      setState(() {
        _isVerifying = false;
        _otpError = result.errorMessage ?? 'Invalid verification code';
      });
    }
  }

  void _handleResendCode() async {
    if (_resendCountdown > 0) return;

    final email = _emailController.text.trim();
    setState(() {
      _otpError = null;
      _isSending = true;
    });

    final state = context.read<ParkingStateManager>();
    final String? code;
    try {
      code = await state.sendVerificationOtp(email);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _otpError = e is OtpAuthException
            ? e.message
            : 'Failed to generate verification code. Please try again.';
      });
      return;
    }

    if (!mounted) return;

    for (var c in _otpControllers) {
      c.clear();
    }

    setState(() {
      _lastSentCode = code;
      _isSending = false;
    });

    _startCountdown(60);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('A fresh 6-digit code has been issued for $email'),
        duration: const Duration(seconds: 3),
      ),
    );

    if (_focusNodes.isNotEmpty) {
      _focusNodes[0].requestFocus();
    }
  }

  void _selectPresetEmail(String email) {
    setState(() {
      _emailController.text = email;
      _emailError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _step == 0 ? _buildEmailStep(c) : _buildOtpStep(c),
          ),
        ),
      ),
    );
  }

  // --- Step 1: Email Address Entry ---
  Widget _buildEmailStep(AppColors c) {
    return Column(
      key: const ValueKey('email_step'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpace.xl),

        // Brand Logo and Header Badge
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: c.primary,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Text(
                'P',
                style: AppText.h1.copyWith(
                  color: c.onPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _selectPresetEmail('newdriver@sliit.lk'),
              icon: Icon(Icons.person_add_alt_1_rounded, size: 16, color: c.accent),
              label: Text(
                'Register New Driver',
                style: AppText.caption.copyWith(
                  color: c.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 36),
                side: BorderSide(color: c.accent.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),

        const SizedBox(height: AppSpace.xl),

        // Title & Description
        Text(
          'Park smarter.\nBook in seconds.',
          style: AppText.h1.copyWith(color: c.textPrimary),
        ),

        const SizedBox(height: AppSpace.xs),

        Text(
          'Enter your campus email. We will generate and send a 6-digit verification code to verify your session.',
          style: AppText.body.copyWith(color: c.textSecondary),
        ),

        // Preset quick chips for convenient campus testing
        if (AppConfig.kDemoMode) ...[
          Wrap(
            spacing: AppSpace.sm,
            children: [
              ActionChip(
                avatar: const Icon(Icons.account_circle_outlined, size: 16),
                label: const Text('anuk@example.com'),
                onPressed: () => _selectPresetEmail('anuk@example.com'),
              ),
              ActionChip(
                avatar: const Icon(Icons.school_outlined, size: 16),
                label: const Text('driver@sliit.lk'),
                onPressed: () => _selectPresetEmail('driver@sliit.lk'),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.xl),
        ],

        // Email Field
        Text('Campus Email Address', style: AppText.label.copyWith(color: c.textSecondary)),
        const SizedBox(height: AppSpace.xs),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          style: AppText.body.copyWith(
            color: c.textPrimary,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            prefixIcon: Icon(
              Icons.mail_outline_rounded,
              color: c.textSecondary,
              size: 20,
            ),
            hintText: 'e.g. anuk@example.com',
            errorText: _emailError,
          ),
          onChanged: (_) {
            if (_emailError != null) setState(() => _emailError = null);
          },
          onSubmitted: (_) => _handleSendCode(),
        ),

        const SizedBox(height: AppSpace.xxl),

        // Send Code Action Button
        PrimaryButton(
          text: 'Send Verification Code',
          icon: Icons.arrow_forward_rounded,
          isLoading: _isSending,
          onPressed: _handleSendCode,
        ),

        const SizedBox(height: AppSpace.md),

        // Terms Footnote
        Center(
          child: Text.rich(
            TextSpan(
              text: 'By continuing you agree to the ',
              style: AppText.caption.copyWith(color: c.textSecondary),
              children: [
                TextSpan(
                  text: 'Terms',
                  style: TextStyle(
                    color: c.textPrimary,
                    decoration: TextDecoration.underline,
                  ),
                ),
                const TextSpan(text: ' and '),
                TextSpan(
                  text: 'Privacy Policy',
                  style: TextStyle(
                    color: c.textPrimary,
                    decoration: TextDecoration.underline,
                  ),
                ),
                const TextSpan(text: '.'),
              ],
            ),
          ),
        ),

        const SizedBox(height: AppSpace.xl),
      ],
    );
  }

  // --- Step 2: 6-Digit OTP Entry ---
  Widget _buildOtpStep(AppColors c) {
    final email = _emailController.text.trim();

    return Column(
      key: const ValueKey('otp_step'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpace.lg),

        // Navigation row to go back
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            InkWell(
              onTap: () {
                setState(() {
                  _step = 0;
                  _otpError = null;
                });
              },
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: Row(
                  children: [
                    Icon(Icons.arrow_back_rounded, size: 20, color: c.textPrimary),
                    const SizedBox(width: AppSpace.xs),
                    Text(
                      'Change Email',
                      style: AppText.body.copyWith(
                        color: c.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: c.surfaceMuted,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Step 2 of 2',
                style: AppText.caption.copyWith(
                  color: c.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: AppSpace.xl),

        // Title
        Text(
          'Verify your email',
          style: AppText.h1.copyWith(color: c.textPrimary),
        ),

        const SizedBox(height: AppSpace.xs),

        // Subtitle with destination email
        Text.rich(
          TextSpan(
            text: 'We sent a 6-digit verification code to\n',
            style: AppText.body.copyWith(color: c.textSecondary),
            children: [
              TextSpan(
                text: email,
                style: TextStyle(
                  color: c.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: AppSpace.lg),

        // In-App Verification Alert Banner (Research & Testing Convenience)
        if (AppConfig.kDemoMode && _lastSentCode != null)
          Container(
            padding: const EdgeInsets.all(AppSpace.md),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: c.accent.withValues(alpha: 0.4)),
              boxShadow: [
                BoxShadow(
                  color: c.accent.withValues(alpha: 0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: c.accentSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.mark_email_read_rounded, color: c.accent, size: 20),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Verification Code: $_lastSentCode',
                        style: AppText.body.copyWith(
                          color: c.textPrimary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Valid for 5 min · Backed by Cloud Firestore',
                        style: AppText.caption.copyWith(color: c.textSecondary, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _autoFillCode,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    backgroundColor: c.accentSoft,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(
                    'Auto-fill code',
                    style: AppText.caption.copyWith(
                      color: c.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: AppSpace.xl),

        Text(
          'Enter 6-Digit Code',
          style: AppText.label.copyWith(color: c.textSecondary),
        ),
        const SizedBox(height: AppSpace.sm),

        // 6 Digit Box Row with Auto-Advance & Pasting
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(6, (index) {
            return SizedBox(
              width: 48,
              height: 56,
              child: Container(
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _focusNodes[index].hasFocus
                        ? c.accent
                        : (_otpControllers[index].text.isNotEmpty ? c.textPrimary : c.border),
                    width: _focusNodes[index].hasFocus ? 2 : 1,
                  ),
                ),
                alignment: Alignment.center,
                child: TextField(
                  controller: _otpControllers[index],
                  focusNode: _focusNodes[index],
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 1,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  style: AppText.h2.copyWith(
                    color: c.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: const InputDecoration(
                    counterText: '',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: (val) {
                    if (_otpError != null) {
                      setState(() => _otpError = null);
                    }

                    if (val.isNotEmpty) {
                      if (index < 5) {
                        _focusNodes[index + 1].requestFocus();
                      } else {
                        _focusNodes[index].unfocus();
                      }
                    } else if (val.isEmpty && index > 0) {
                      _focusNodes[index - 1].requestFocus();
                    }
                  },
                ),
              ),
            );
          }),
        ),

        if (_otpError != null) ...[
          const SizedBox(height: AppSpace.sm),
          Row(
            children: [
              Icon(Icons.error_outline_rounded, color: c.danger, size: 16),
              const SizedBox(width: AppSpace.xs),
              Expanded(
                child: Text(
                  _otpError!,
                  style: AppText.caption.copyWith(color: c.danger, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],

        const SizedBox(height: AppSpace.md),

        // Resend Timer Row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _resendCountdown > 0
                  ? 'Resend code in 0:${_resendCountdown.toString().padLeft(2, '0')}'
                  : 'Didn\'t receive the code?',
              style: AppText.caption.copyWith(color: c.textSecondary),
            ),
            if (_resendCountdown == 0)
              InkWell(
                onTap: _handleResendCode,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    'Resend code',
                    style: AppText.caption.copyWith(
                      color: c.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),

        const SizedBox(height: AppSpace.xxl),

        // Verify & Continue Button
        PrimaryButton(
          text: 'Verify & Continue',
          isLoading: _isVerifying,
          onPressed: _handleVerifyCode,
        ),

        const SizedBox(height: AppSpace.xl),
      ],
    );
  }
}
