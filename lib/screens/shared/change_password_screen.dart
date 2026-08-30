import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../services/notification_service.dart';

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

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleChangePassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) {
      setState(() {
        _isLoading = false;
        _error = 'No authenticated user found.';
      });
      return;
    }

    final isPasswordUser = user.providerData.any((p) => p.providerId == 'password');

    try {
      if (isPasswordUser) {
        // 1. Re-authenticate existing password user
        final cred = EmailAuthProvider.credential(
          email: user.email!,
          password: _currentPasswordController.text,
        );
        await user.reauthenticateWithCredential(cred);

        // 2. Update password
        await user.updatePassword(_newPasswordController.text);
      } else {
        // Google OAuth user setting a password for the first time
        final cred = EmailAuthProvider.credential(
          email: user.email!,
          password: _newPasswordController.text,
        );
        try {
          await user.linkWithCredential(cred);
        } on FirebaseAuthException catch (linkError) {
          if (linkError.code == 'provider-already-linked' || linkError.code == 'credential-already-in-use') {
            await user.updatePassword(_newPasswordController.text);
          } else {
            rethrow;
          }
        }
        // Mark that user now has an active password
        await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
          'hasPassword': true,
        });
      }

      await NotificationService().sendNotification(
        uid: user.uid,
        title: isPasswordUser ? 'Password Updated' : 'Password Created',
        body: isPasswordUser
            ? 'Your PRISM account password was successfully updated.'
            : 'You have successfully created a password for your PRISM account.',
        type: 'security',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isPasswordUser
                ? 'Password updated successfully!'
                : 'Password set successfully! You can now log in with Google or your password.'),
            backgroundColor: _green,
            duration: const Duration(seconds: 4),
          ),
        );
        Navigator.pop(context);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          switch (e.code) {
            case 'wrong-password':
            case 'invalid-credential':
              _error = 'Current password is incorrect.';
              break;
            case 'weak-password':
              _error = 'The new password is too weak. Please use at least 8 characters.';
              break;
            case 'requires-recent-login':
              _error = 'For security, please log out and log in again before setting your password.';
              break;
            case 'too-many-requests':
              _error = 'Too many attempts. Please try again in a few moments.';
              break;
            case 'network-request-failed':
              _error = 'Network error. Please check your internet connection.';
              break;
            default:
              _error = e.message ?? 'Failed to update password. Please try again.';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'An error occurred. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isPasswordUser = user?.providerData.any((p) => p.providerId == 'password') ?? false;

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
                      decoration: BoxDecoration(
                        color: _navyMid.withValues(alpha: 0.4),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Positioned(
                    left: -20, top: -30,
                    child: Container(
                      width: 153, height: 151,
                      decoration: BoxDecoration(
                        color: _navyDark.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.10),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            alignment: Alignment.center,
                            child: SvgPicture.string(
                              '<svg width="18" height="18" viewBox="0 0 18 18" fill="none"><path d="M11 14L6 9L11 4" stroke="white" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>',
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('PRISM', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 3, height: 1.0)),
                            const SizedBox(height: 3),
                            Text(
                              isPasswordUser ? 'CHANGE PASSWORD' : 'SET PASSWORD',
                              style: const TextStyle(color: _accent, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Form ────────────────────────────────────────────────────────
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
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          isPasswordUser ? 'Update Security Password' : 'Set Account Password',
                          style: const TextStyle(color: _textDark, fontSize: 18, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          isPasswordUser
                              ? 'Enter your current password and set a new password for your PRISM account.'
                              : 'Create a password for your account so you can also sign in using your email and password alongside Google.',
                          style: const TextStyle(color: _textMid, fontSize: 13, height: 1.5),
                        ),
                        const SizedBox(height: 24),

                        // Current Password (only for existing password users)
                        if (isPasswordUser) ...[
                          const Text('Current Password', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _textDark)),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _currentPasswordController,
                            obscureText: _obscureCurrent,
                            style: const TextStyle(color: _textDark, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: 'Enter current password',
                              hintStyle: const TextStyle(color: _textLight, fontSize: 14),
                              prefixIcon: const Icon(Icons.lock_outline, color: _textLight, size: 20),
                              suffixIcon: IconButton(
                                icon: Icon(_obscureCurrent ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: _textLight, size: 20),
                                onPressed: () => setState(() => _obscureCurrent = !_obscureCurrent),
                              ),
                              filled: true,
                              fillColor: _surface,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _border)),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _border)),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _navy, width: 1.5)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            ),
                            validator: (v) => (v == null || v.isEmpty) ? 'Enter your current password' : null,
                          ),
                          const SizedBox(height: 18),
                        ],

                        // New Password
                        Text(isPasswordUser ? 'New Password' : 'Password', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _textDark)),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _newPasswordController,
                          obscureText: _obscureNew,
                          style: const TextStyle(color: _textDark, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: isPasswordUser ? 'Enter new password' : 'Create password',
                            hintStyle: const TextStyle(color: _textLight, fontSize: 14),
                            prefixIcon: const Icon(Icons.lock_reset_rounded, color: _textLight, size: 20),
                            suffixIcon: IconButton(
                              icon: Icon(_obscureNew ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: _textLight, size: 20),
                              onPressed: () => setState(() => _obscureNew = !_obscureNew),
                            ),
                            filled: true,
                            fillColor: _surface,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _border)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _border)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _navy, width: 1.5)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Enter a password';
                            if (v.length < 8) return 'Password must be at least 8 characters';
                            if (!RegExp(r'[A-Z]').hasMatch(v)) return 'Must include at least 1 uppercase letter (A-Z)';
                            if (!RegExp(r'[a-z]').hasMatch(v)) return 'Must include at least 1 lowercase letter (a-z)';
                            if (!RegExp(r'[0-9!@#\$%^&*(),.?":{}|<>]').hasMatch(v)) {
                              return 'Must include at least 1 number or special character';
                            }
                            if (isPasswordUser && v == _currentPasswordController.text) {
                              return 'New password must be different from current';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.only(left: 2),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text('• Must be at least 8 characters long', style: TextStyle(color: _textLight, fontSize: 10)),
                              SizedBox(height: 2),
                              Text('• Must include uppercase (A–Z) & lowercase (a–z)', style: TextStyle(color: _textLight, fontSize: 10)),
                              SizedBox(height: 2),
                              Text('• Must include at least 1 number or special character', style: TextStyle(color: _textLight, fontSize: 10)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),

                        // Confirm New Password
                        Text(isPasswordUser ? 'Confirm New Password' : 'Confirm Password', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _textDark)),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _confirmPasswordController,
                          obscureText: _obscureConfirm,
                          style: const TextStyle(color: _textDark, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: isPasswordUser ? 'Re-enter new password' : 'Confirm your password',
                            hintStyle: const TextStyle(color: _textLight, fontSize: 14),
                            prefixIcon: const Icon(Icons.check_circle_outline_rounded, color: _textLight, size: 20),
                            suffixIcon: IconButton(
                              icon: Icon(_obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: _textLight, size: 20),
                              onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                            ),
                            filled: true,
                            fillColor: _surface,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _border)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _border)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _navy, width: 1.5)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Confirm your password';
                            if (v != _newPasswordController.text) return 'Passwords do not match';
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),

                        if (_error != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: const Color(0x1AEF4444), borderRadius: BorderRadius.circular(10)),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline_rounded, color: _red, size: 18),
                                const SizedBox(width: 8),
                                Expanded(child: Text(_error!, style: const TextStyle(color: _red, fontSize: 12))),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],

                        ElevatedButton(
                          onPressed: _isLoading ? null : _handleChangePassword,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _navy,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          child: _isLoading
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: _white, strokeWidth: 2))
                              : Text(
                                  isPasswordUser ? 'Update Password' : 'Set Password',
                                  style: const TextStyle(color: _white, fontSize: 14, fontWeight: FontWeight.w700),
                                ),
                        ),
                      ],
                    ),
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
