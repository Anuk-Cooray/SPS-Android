import 'package:smart_parking/data/services/email_otp_auth.dart';

/// In-memory stand-in for the requestEmailOtp / verifyEmailOtp callables + Firebase Auth.
/// Behaves like the emulator: it echoes the issued code as `demoCode`.
class FakeEmailOtpAuthGateway implements EmailOtpAuthGateway {
  final Map<String, String> _issued = {};
  AuthenticatedUser? _user;
  int signOutCount = 0;

  static const String fixedCode = '424242';

  @override
  AuthenticatedUser? get currentUser => _user;

  @override
  Future<AuthenticatedUser?> restoreSession() async => _user;

  @override
  Future<OtpRequestResult> requestOtp(String email) async {
    _issued[email] = fixedCode;
    return OtpRequestResult(
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      demoCode: fixedCode,
    );
  }

  @override
  Future<AuthenticatedUser> verifyOtp(String email, String code) async {
    final expected = _issued[email];
    if (expected == null) {
      throw const OtpAuthException('failed-precondition', 'Verification code has expired or was already used. Please request a new code.');
    }
    if (expected != code) {
      throw const OtpAuthException('permission-denied', 'Incorrect code. Please check it and try again.');
    }
    _issued.remove(email);
    return _user = AuthenticatedUser(uid: 'uid-${email.hashCode.abs()}', email: email);
  }

  @override
  Future<String?> getIdToken() async => _user == null ? null : 'fake-id-token';

  @override
  Future<void> signOut() async {
    signOutCount++;
    _user = null;
  }
}
