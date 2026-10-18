import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_buttons.dart';
import '../../data/services/parking_state_manager.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback onLoginSuccess;

  const LoginScreen({super.key, required this.onLoginSuccess});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController(text: 'anuk@example.com');
  final List<TextEditingController> _otpControllers =
      List.generate(6, (i) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (i) => FocusNode());

  int _resendCountdown = 0;
  Timer? _timer;
  bool _isLoading = false;
  String? _emailError;
  String? _otpError;

  @override
  void initState() {
    super.initState();
    // Pre-fill demo digits
    _otpControllers[0].text = '4';
    _otpControllers[1].text = '8';
    _otpControllers[2].text = '2';
    _otpControllers[3].text = '1';
    _otpControllers[4].text = '0';
    _otpControllers[5].text = '0';
  }

  void _startCountdown() {
    _timer?.cancel();
    _resendCountdown = 60;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCountdown > 0) {
        setState(() => _resendCountdown--);
      } else {
        timer.cancel();
      }
    });
  }

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

  bool _validateEmail(String email) {
    final emailRegex = RegExp(r'^[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+$');
    return emailRegex.hasMatch(email);
  }

  String _getOtpValue() {
    return _otpControllers.map((c) => c.text.trim()).join();
  }

  void _handleContinue() async {
    final email = _emailController.text.trim();
    final otp = _getOtpValue();

    bool hasError = false;

    if (email.isEmpty) {
      setState(() => _emailError = 'Please enter your email address');
      hasError = true;
    } else if (!_validateEmail(email)) {
      setState(() => _emailError = 'Please enter a valid email address (e.g. name@sliit.lk)');
      hasError = true;
    } else {
      setState(() => _emailError = null);
    }

    if (otp.length < 6) {
      setState(() => _otpError = 'Please enter the complete 6-digit verification code');
      hasError = true;
    } else {
      setState(() => _otpError = null);
    }

    if (hasError) return;

    setState(() => _isLoading = true);

    if (mounted) {
      await context.read<ParkingStateManager>().login(email);
      if (mounted) {
        setState(() => _isLoading = false);
        widget.onLoginSuccess();
      }
    }
  }

  void _fillNewUserDemo() {
    setState(() {
      _emailController.text = 'newdriver@sliit.lk';
      _otpControllers[0].text = '9';
      _otpControllers[1].text = '9';
      _otpControllers[2].text = '8';
      _otpControllers[3].text = '8';
      _otpControllers[4].text = '7';
      _otpControllers[5].text = '7';
      _emailError = null;
      _otpError = null;
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpace.xl),

              // Top Logo Badge & Demo Fast-Fill
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
                    onPressed: _fillNewUserDemo,
                    icon: Icon(Icons.person_add_alt_1_rounded, size: 16, color: c.accent),
                    label: Text(
                      'Test New User',
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

              // Title
              Text(
                'Park smarter.\nBook in seconds.',
                style: AppText.h1.copyWith(color: c.textPrimary),
              ),

              const SizedBox(height: AppSpace.xs),

              // Subtitle
              Text(
                "Enter your campus email. We'll send you a 6-digit verification code.",
                style: AppText.body.copyWith(color: c.textSecondary),
              ),

              const SizedBox(height: AppSpace.xl),

              // Email Field
              Text('Email Address', style: AppText.label.copyWith(color: c.textSecondary)),
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
                  hintText: 'e.g. anuk@sliit.lk',
                  errorText: _emailError,
                ),
                onChanged: (_) {
                  if (_emailError != null) setState(() => _emailError = null);
                },
              ),

              const SizedBox(height: AppSpace.xl),

              // Verification code
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Verification Code',
                    style: AppText.label.copyWith(color: c.textSecondary),
                  ),
                  Text(
                    'Demo code: 482100',
                    style: AppText.caption.copyWith(color: c.accent, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.xs),

              // 6 Digits Row
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
                          color: _focusNodes[index].hasFocus ? c.accent : c.border,
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
                          if (val.isNotEmpty && index < 5) {
                            _focusNodes[index + 1].requestFocus();
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
                const SizedBox(height: AppSpace.xs),
                Text(
                  _otpError!,
                  style: AppText.caption.copyWith(color: c.danger, fontSize: 12),
                ),
              ],

              const SizedBox(height: AppSpace.sm),

              // Resend countdown
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _resendCountdown > 0
                        ? 'Code sent to inbox · Resend in 0:${_resendCountdown.toString().padLeft(2, '0')}'
                        : 'Did not receive code?',
                    style: AppText.caption.copyWith(color: c.textSecondary),
                  ),
                  if (_resendCountdown == 0)
                    InkWell(
                      onTap: () {
                        _startCountdown();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('A fresh 6-digit code has been sent.')),
                        );
                      },
                      child: Text(
                        'Resend code',
                        style: AppText.caption.copyWith(
                          color: c.accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: AppSpace.xxl),

              // Continue Button
              PrimaryButton(
                text: 'Verify & Continue',
                isLoading: _isLoading,
                onPressed: _handleContinue,
              ),

              const SizedBox(height: AppSpace.md),

              // Terms & Conditions
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
          ),
        ),
      ),
    );
  }
}
