import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/injection_config.dart';
import '../../providers/session_state_provider.dart';
import '../../services/auth_service.dart';
import '../../providers/user_role_provider.dart';
import '../../widgets/auth_wrapper.dart';
import 'detection_screen.dart';
import 'my_sessions_screen.dart';

/// UC-3.2 — Student selects an injection type before starting a session.
class InjectionTypeScreen extends StatelessWidget {
  const InjectionTypeScreen({super.key});

  static const _typeDetails = {
    'IM': (
      'Intramuscular',
      'Deep muscle tissue injection',
      '90°',
      Icons.arrow_upward,
    ),
    'SubQ': (
      'Subcutaneous',
      'Fat layer beneath the skin',
      '45°',
      Icons.rotate_right,
    ),
    'IV': (
      'Intravenous',
      'Directly into a vein',
      '15°',
      Icons.water_drop_outlined,
    ),
    'ID': (
      'Intradermal',
      'Between skin layers',
      '10°',
      Icons.layers_outlined,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final name = context.watch<UserRoleProvider>().fullName ?? 'Student';

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // ── Navy Blue Header Background ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 181,
            child: Container(color: const Color(0xFF003366)),
          ),
          // ── Top Left Decorative Circle ──
          Positioned(
            top: 28,
            left: -20,
            width: 153,
            height: 151,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF002244).withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
            ),
          ),
          // ── Top Right Decorative Circle ──
          Positioned(
            top: -71,
            right: -87,
            width: 209,
            height: 207,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF004080).withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
            ),
          ),
          
          // ── Main Content ──
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── AppBar Area ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('PRISM',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 2)),
                            Text('Welcome, $name',
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12)),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            key: const Key('my_sessions_button'),
                            icon: const Icon(Icons.history, color: Colors.white70),
                            tooltip: 'My Sessions',
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const MySessionsScreen()),
                            ),
                          ),
                          IconButton(
                            key: const Key('student_signout'),
                            icon: const Icon(Icons.logout, color: Colors.white38),
                            tooltip: 'Sign out',
                            onPressed: () async {
                              await AuthService().signOut();
                              if (!context.mounted) return;
                              context.read<UserRoleProvider>().clear();
                              Navigator.pushAndRemoveUntil(
                                context,
                                MaterialPageRoute(builder: (_) => const AuthWrapper()),
                                (_) => false,
                              );
                            },
                          ),
                        ],
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                
                // ── Header Titles ──
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select Injection Type',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Choose the injection type for your return-demonstration.',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                
                // ── Vertical Card List ──
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
                    itemCount: InjectionConfigService.allTypes.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 16),
                    itemBuilder: (context, index) {
                      final type = InjectionConfigService.allTypes[index];
                      final details = _typeDetails[type]!;
                      return _TypeCard(
                        type: type,
                        label: details.$1,
                        description: details.$2,
                        angle: details.$3,
                        icon: details.$4,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  final String type;
  final String label;
  final String description;
  final String angle;
  final IconData icon;

  const _TypeCard({
    required this.type,
    required this.label,
    required this.description,
    required this.angle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: Key('injection_type_$type'),
      onTap: () {
        final config = InjectionConfigService.getConfig(type);
        context.read<SessionStateProvider>().setConfig(config);
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => DetectionScreen(injectionType: type)),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE2EAF4), width: 2),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Row(
          children: [
            // Icon container
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFFEEF3F9),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: const Color(0xFF003366), size: 28),
            ),
            const SizedBox(width: 16),
            
            // Text Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$label ($type)',
                    style: const TextStyle(
                      color: Color(0xFF003366),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(
                      color: Color(0xFF8A9BB0),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            
            // Target Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF3F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Target $angle',
                style: const TextStyle(
                  color: Color(0xFF4A7BAF),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
