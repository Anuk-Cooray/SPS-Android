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

  int _resendCountdown = 42;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Pre-fill first 3 digits as in mockup
    _otpControllers[0].text = '4';
    _otpControllers[1].text = '8';
    _otpControllers[2].text = '2';

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCountdown > 0) {
        setState(() => _resendCountdown--);
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

  void _handleContinue() {
    final email = _emailController.text.trim();
    if (email.isNotEmpty) {
      context.read<ParkingStateManager>().login(email);
      widget.onLoginSuccess();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpace.xxl),

              // Logo badge
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

              const SizedBox(height: AppSpace.xl),

              // Title
              Text(
                'Park smarter.\nBook in seconds.',
                style: AppText.h1.copyWith(color: c.textPrimary),
              ),

              const SizedBox(height: AppSpace.sm),

              // Subtitle
              Text(
                "Enter your email. We'll send you a 6-digit verification code.",
                style: AppText.body.copyWith(color: c.textSecondary),
              ),

              const SizedBox(height: AppSpace.xxl),

              // Email Field
              Text('Email', style: AppText.label.copyWith(color: c.textSecondary)),
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
                  hintText: 'name@example.com',
                ),
              ),

              const SizedBox(height: AppSpace.xl),

              // Verification code
              Text(
                'Verification code',
                style: AppText.label.copyWith(color: c.textSecondary),
              ),
              const SizedBox(height: AppSpace.xs),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(6, (index) {
                  final isFocused = index == 3;
                  return SizedBox(
                    width: 48,
                    height: 56,
                    child: Container(
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isFocused ? c.accent : c.border,
                          width: isFocused ? 2 : 1,
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
                          if (val.isNotEmpty && index < 5) {
                            _focusNodes[index + 1].requestFocus();
                          }
                        },
                      ),
                    ),
                  );
                }),
              ),

              const SizedBox(height: AppSpace.sm),

              Text(
                'Code sent to your inbox · Resend in 0:${_resendCountdown.toString().padLeft(2, '0')}',
                style: AppText.caption.copyWith(color: c.textSecondary),
              ),

              const Spacer(),

              // Continue Button
              PrimaryButton(
                text: 'Continue',
                onPressed: _handleContinue,
              ),

              const SizedBox(height: AppSpace.md),

              // Terms
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

              const SizedBox(height: AppSpace.md),
            ],
          ),
        ),
      ),
    );
  }
}
