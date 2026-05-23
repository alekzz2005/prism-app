import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
const _red        = Color(0xFFDC2626);
// ─────────────────────────────────────────────────────────────────────────────

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _notificationsEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadNotificationPreference();
  }

  Future<void> _loadNotificationPreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
    });
  }

  Future<void> _toggleNotifications(bool value) async {
    setState(() {
      _notificationsEnabled = value;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications_enabled', value);
  }

  String _formatNameWithInitial(String fullName) {
    if (fullName.isEmpty) return 'User';
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return fullName;
    
    if (parts.length == 2) {
      // Inject "M." if only two words are provided
      return '${parts[0]} M. ${parts[1]}';
    } else {
      // e.g. First Middle Last
      final first = parts[0];
      final middle = parts[1];
      final last = parts.sublist(2).join(' ');
      return '$first ${middle[0].toUpperCase()}. $last';
    }
  }

  void _showLogoutConfirmation() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [BoxShadow(color: Color(0x1A001E3C), blurRadius: 16, offset: Offset(0, 4))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(color: const Color(0x1AEF4444), shape: BoxShape.circle),
                alignment: Alignment.center,
                child: SvgPicture.string(
                  '<svg width="28" height="28" viewBox="0 0 24 24" fill="none"><path d="M15.75 9V5.25A2.25 2.25 0 0013.5 3h-6a2.25 2.25 0 00-2.25 2.25v13.5A2.25 2.25 0 007.5 21h6a2.25 2.25 0 002.25-2.25V15M12 9l-3 3m0 0l3 3m-3-3h12.75" stroke="#DC2626" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>',
                ),
              ),
              const SizedBox(height: 20),
              const Text('Sign Out', style: TextStyle(color: _textDark, fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text('Are you sure you want to sign out of PRISM?', textAlign: TextAlign.center, style: TextStyle(color: _textMid, fontSize: 14)),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: _border)),
                      ),
                      child: const Text('Cancel', style: TextStyle(color: _textMid, fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        final nav = Navigator.of(context);
                        final userRole = context.read<UserRoleProvider>();
                        Navigator.pop(ctx); // close dialog
                        await AuthService().signOut();
                        userRole.clear();
                        nav.pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const AuthWrapper()),
                          (_) => false,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _red,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Sign Out', style: TextStyle(color: _white, fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final roleProvider = context.watch<UserRoleProvider>();
    final user = FirebaseAuth.instance.currentUser;
    
    final rawName = roleProvider.fullName ?? 'User';
    final formattedName = _formatNameWithInitial(rawName);
    final email = user?.email ?? 'No email provided';
    final initials = rawName.isNotEmpty ? rawName[0].toUpperCase() : '?';

    return Scaffold(
      backgroundColor: _surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Container(
              color: _navy,
              width: double.infinity,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  // Decorative circles
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
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                        Column(
                          children: [
                            const Text('PRISM', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 5, height: 1)),
                            const SizedBox(height: 3),
                            const Text('PROFILE', style: TextStyle(color: _accent, fontSize: 9, fontWeight: FontWeight.w400, letterSpacing: 1.5)),
                          ],
                        ),
                        const SizedBox(width: 40), // Balance the back button
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Overlapping Avatar & Info ───────────────────────────────────
            Transform.translate(
              offset: const Offset(0, -60),
              child: Column(
                children: [
                  Container(
                    width: 110, height: 110,
                    decoration: BoxDecoration(
                      color: _white,
                      shape: BoxShape.circle,
                      border: Border.all(color: _surface, width: 4),
                      boxShadow: const [BoxShadow(color: Color(0x1A001E3C), blurRadius: 12, offset: Offset(0, 4))],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      initials,
                      style: const TextStyle(color: _navy, fontSize: 40, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(formattedName, style: const TextStyle(color: _textDark, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                  const SizedBox(height: 4),
                  Text(email, style: const TextStyle(color: _textMid, fontSize: 14)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0x14003366),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      roleProvider.isInstructor ? 'Clinical Instructor' : 'Nursing Student',
                      style: const TextStyle(color: _navy, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                    ),
                  ),
                ],
              ),
            ),

            // ── Settings List ───────────────────────────────────────────────
            Expanded(
              child: Transform.translate(
                offset: const Offset(0, -30),
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    const Text('ACCOUNT SETTINGS', style: TextStyle(color: _textLight, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                    const SizedBox(height: 12),
                    
                    // Notifications Toggle
                    _buildSettingsTile(
                      icon: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none"><path d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9" stroke="#4A5568" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>',
                      title: 'Push Notifications',
                      subtitle: 'Receive updates on feedback',
                      trailing: Switch(
                        value: _notificationsEnabled,
                        onChanged: _toggleNotifications,
                        activeThumbColor: _white,
                        activeTrackColor: _navy,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Change Password
                    _buildSettingsTile(
                      icon: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none"><path d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" stroke="#4A5568" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>',
                      title: 'Change Password',
                      subtitle: 'Update your account security',
                      trailing: SvgPicture.string('<svg width="18" height="18" viewBox="0 0 18 18" fill="none"><path d="M7 4l5 5-5 5" stroke="#A8C4E0" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>'),
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Change Password functionality coming soon.')),
                        );
                      },
                    ),
                    const SizedBox(height: 32),

                    // Logout Button
                    GestureDetector(
                      onTap: _showLogoutConfirmation,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: const Color(0x0AEF4444),
                          border: Border.all(color: const Color(0x33EF4444)),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SvgPicture.string('<svg width="20" height="20" viewBox="0 0 24 24" fill="none"><path d="M15.75 9V5.25A2.25 2.25 0 0013.5 3h-6a2.25 2.25 0 00-2.25 2.25v13.5A2.25 2.25 0 007.5 21h6a2.25 2.25 0 002.25-2.25V15M12 9l-3 3m0 0l3 3m-3-3h12.75" stroke="#DC2626" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>'),
                            const SizedBox(width: 10),
                            const Text('Sign Out', style: TextStyle(color: _red, fontSize: 14, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsTile({
    required String icon,
    required String title,
    required String subtitle,
    required Widget trailing,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border, width: 1.5),
          boxShadow: const [BoxShadow(color: Color(0x05001E3C), blurRadius: 8, offset: Offset(0, 2))],
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(10)),
              alignment: Alignment.center,
              child: SvgPicture.string(icon),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: _textDark, fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: _textLight, fontSize: 12)),
                ],
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}
