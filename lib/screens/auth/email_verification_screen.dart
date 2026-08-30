import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import '../../providers/user_role_provider.dart';
import '../../services/auth_service.dart';
import '../../widgets/auth_wrapper.dart';

// ─── Brand Colours ────────────────────────────────────────────────────────────
const _navy       = Color(0xFF003366);
const _navyMid    = Color(0xFF004080);
const _navyDark   = Color(0xFF002244);
const _accent     = Color(0xFFA8C4E0);
const _surface    = Color(0xFFF8FAFC);
const _white      = Color(0xFFFFFFFF);
const _border     = Color(0xFFE2EAF4);
const _textDark   = Color(0xFF1A2B3C);
const _textMid    = Color(0xFF4A5568);
const _textLight  = Color(0xFF8A9BB0);
const _green      = Color(0xFF16A34A);
const _red        = Color(0xFFDC2626);

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({super.key});

  @override
  State<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final AuthService _authService = AuthService();

  bool _isChecking = false;
  bool _isResending = false;
  int _resendCountdown = 0;
  Timer? _resendTimer;
  Timer? _autoCheckTimer;
  String? _message;

  @override
  void initState() {
    super.initState();
    // Auto-check every 4 seconds in background
    _autoCheckTimer = Timer.periodic(const Duration(seconds: 4), (_) => _checkEmailVerified(silent: true));
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _autoCheckTimer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    setState(() => _resendCountdown = 60);
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCountdown > 0) {
        setState(() => _resendCountdown--);
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _checkEmailVerified({bool silent = false}) async {
    if (!silent) setState(() => _isChecking = true);
    try {
      final user = _auth.currentUser;
      await user?.reload();
      final refreshedUser = _auth.currentUser;

      if (refreshedUser != null && refreshedUser.emailVerified) {
        _autoCheckTimer?.cancel();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Email verified successfully! Welcome to PRISM.'),
              backgroundColor: _green,
              duration: Duration(seconds: 2),
            ),
          );
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const AuthWrapper()),
            (_) => false,
          );
        }
      } else if (!silent && mounted) {
        setState(() {
          _message = 'Email is not verified yet. Please check your inbox and click the verification link.';
        });
      }
    } catch (e) {
      if (!silent && mounted) {
        setState(() => _message = 'Error checking verification: $e');
      }
    } finally {
      if (!silent && mounted) setState(() => _isChecking = false);
    }
  }

  Future<void> _resendVerificationEmail() async {
    setState(() {
      _isResending = true;
      _message = null;
    });

    try {
      final user = _auth.currentUser;
      await user?.sendEmailVerification();
      _startResendTimer();
      if (mounted) {
        setState(() {
          _message = 'A new verification link has been sent to ${user?.email}.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _message = 'Failed to resend email: $e');
      }
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    final email = user?.email ?? '';

    return Scaffold(
      backgroundColor: _surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Container(
              color: _navy,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Positioned(
                    right: -60, top: -71,
                    child: Container(
                      width: 209, height: 207,
                      decoration: BoxDecoration(color: _navyMid.withValues(alpha: 0.4), shape: BoxShape.circle),
                    ),
                  ),
                  Positioned(
                    left: -20, top: -30,
                    child: Container(
                      width: 153, height: 151,
                      decoration: BoxDecoration(color: _navyDark.withValues(alpha: 0.3), shape: BoxShape.circle),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text('PRISM', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 3, height: 1.0)),
                            SizedBox(height: 3),
                            Text('ACCOUNT ACTIVATION', style: TextStyle(color: _accent, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
                          ],
                        ),
                        GestureDetector(
                          onTap: () async {
                            _autoCheckTimer?.cancel();
                            _resendTimer?.cancel();
                            context.read<UserRoleProvider>().clear();
                            await _authService.signOut();
                            if (context.mounted) {
                              Navigator.pushAndRemoveUntil(
                                context,
                                MaterialPageRoute(builder: (_) => const AuthWrapper()),
                                (_) => false,
                              );
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.10),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Text('Sign Out', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Content Card ────────────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: _white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _border),
                    boxShadow: [
                      BoxShadow(
                        color: _navy.withValues(alpha: 0.05),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 64, height: 64,
                          decoration: const BoxDecoration(
                            color: Color(0x14003366),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.mark_email_unread_rounded, color: _navy, size: 34),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Verify Your Email Address',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _textDark, fontSize: 20, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      RichText(
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          style: const TextStyle(color: _textMid, fontSize: 14, height: 1.5),
                          children: [
                            const TextSpan(text: 'We sent a verification link to\n'),
                            TextSpan(text: email, style: const TextStyle(fontWeight: FontWeight.w700, color: _navy)),
                            const TextSpan(text: '.\n\nPlease open the link in your email to activate your account.'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Spam Folder Heads-up Banner
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFDE68A)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Icon(Icons.info_outline_rounded, color: Color(0xFFD97706), size: 18),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Can\'t find the email? Please check your Spam folder. You may mark it as "Not Spam" to receive future notifications.',
                                style: TextStyle(color: Color(0xFF92400E), fontSize: 12, height: 1.4, fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      if (_message != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0x14003366),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _accent.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            _message!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: _navy, fontSize: 12, fontWeight: FontWeight.w500),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      ElevatedButton(
                        onPressed: _isChecking ? null : () => _checkEmailVerified(silent: false),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _navy,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        child: _isChecking
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Text('I Have Verified My Email', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 12),

                      OutlinedButton(
                        onPressed: (_isResending || _resendCountdown > 0) ? null : _resendVerificationEmail,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(color: _border, width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(
                          _resendCountdown > 0
                              ? 'Resend in ${_resendCountdown}s'
                              : (_isResending ? 'Sending...' : 'Resend Verification Email'),
                          style: TextStyle(
                            color: _resendCountdown > 0 ? _textLight : _navy,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
