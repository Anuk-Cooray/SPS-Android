// email_otp_auth.dart
// Smart Parking (J26-IT-335) — Server-Side Email OTP Sign-In (Firebase Auth custom tokens)
// Codes are issued and verified only by the requestEmailOtp / verifyEmailOtp callables.
// A successful verification returns a custom token that creates the Firebase Auth session.

import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'cloud_functions_client.dart';

/// Identity of the signed-in driver, taken from the Firebase Auth session.
class AuthenticatedUser {
  final String uid;
  final String email;

  const AuthenticatedUser({required this.uid, required this.email});
}

/// Response of `requestEmailOtp`. [demoCode] is returned by the server only under the emulator.
class OtpRequestResult {
  final DateTime? expiresAt;
  final String? demoCode;

  const OtpRequestResult({this.expiresAt, this.demoCode});
}

/// A sign-in failure carrying a message suitable for display.
class OtpAuthException implements Exception {
  final String code;
  final String message;

  const OtpAuthException(this.code, this.message);

  @override
  String toString() => 'OtpAuthException($code): $message';
}

abstract class EmailOtpAuthGateway {
  AuthenticatedUser? get currentUser;

  /// Waits for the persisted Firebase Auth session (if any) to be restored at startup.
  Future<AuthenticatedUser?> restoreSession();
  Future<OtpRequestResult> requestOtp(String email);
  Future<AuthenticatedUser> verifyOtp(String email, String code);
  Future<String?> getIdToken();
  Future<void> signOut();
}

/// Maps server error codes from the OTP callables to the login screen's messages.
OtpAuthException otpErrorFromServer(Object error, {required bool verifying}) {
  if (error is OtpAuthException) return error;
  if (error is CloudFunctionsException) {
    switch (error.code) {
      case 'permission-denied':
        return const OtpAuthException('permission-denied', 'Incorrect code. Please check it and try again.');
      case 'resource-exhausted':
        return verifying
            ? const OtpAuthException(
                'resource-exhausted', 'Too many incorrect attempts. Please request a fresh code.')
            : const OtpAuthException(
                'resource-exhausted', 'Please wait a moment before requesting another code.');
      case 'failed-precondition':
        return const OtpAuthException(
            'failed-precondition', 'Verification code has expired or was already used. Please request a new code.');
      case 'invalid-argument':
        return OtpAuthException('invalid-argument', error.message);
    }
  }
  if (error is fb.FirebaseAuthException) {
    return const OtpAuthException('auth-failed', 'Sign-in could not be completed. Please request a new code.');
  }
  return OtpAuthException(
    'unavailable',
    verifying
        ? 'Unable to reach the verification server. Check your connection and try again.'
        : 'Failed to send verification code. Check your connection and try again.',
  );
}

class FirebaseEmailOtpAuthGateway implements EmailOtpAuthGateway {
  final CloudFunctionsClient _functions;
  fb.FirebaseAuth? _authInstance;

  FirebaseEmailOtpAuthGateway(this._functions);

  fb.FirebaseAuth get _auth => _authInstance ??= fb.FirebaseAuth.instance;

  @override
  AuthenticatedUser? get currentUser {
    try {
      final user = _auth.currentUser;
      if (user == null || user.email == null) return null;
      return AuthenticatedUser(uid: user.uid, email: user.email!);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<AuthenticatedUser?> restoreSession() async {
    try {
      await _auth.authStateChanges().first.timeout(const Duration(seconds: 3));
    } catch (_) {}
    return currentUser;
  }

  @override
  Future<OtpRequestResult> requestOtp(String email) async {
    try {
      final res = await _functions.call('requestEmailOtp', {'email': email});
      final expiresAt = res['expiresAt'];
      final demoCode = res['demoCode'];
      return OtpRequestResult(
        expiresAt: expiresAt is String ? DateTime.tryParse(expiresAt) : null,
        demoCode: demoCode is String ? demoCode : null,
      );
    } catch (e) {
      throw otpErrorFromServer(e, verifying: false);
    }
  }

  @override
  Future<AuthenticatedUser> verifyOtp(String email, String code) async {
    try {
      final res = await _functions.call('verifyEmailOtp', {'email': email, 'code': code});
      final customToken = res['customToken'];
      if (customToken is! String || customToken.isEmpty) {
        throw const OtpAuthException('internal', 'Sign-in could not be completed. Please request a new code.');
      }
      final credential = await _auth.signInWithCustomToken(customToken);
      final user = credential.user;
      if (user == null) {
        throw const OtpAuthException('internal', 'Sign-in could not be completed. Please request a new code.');
      }
      return AuthenticatedUser(uid: user.uid, email: user.email ?? email);
    } catch (e) {
      throw otpErrorFromServer(e, verifying: true);
    }
  }

  @override
  Future<String?> getIdToken() async {
    try {
      return await _auth.currentUser?.getIdToken();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (_) {}
  }
}
