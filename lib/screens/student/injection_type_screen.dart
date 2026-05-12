import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/injection_config.dart';
import '../../providers/session_state_provider.dart';
import '../../services/auth_service.dart';
import '../../providers/user_role_provider.dart';
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
      Color(0xFF7C3AED)
    ),
    'SubQ': (
      'Subcutaneous',
      'Fat layer beneath the skin',
      '45°',
      Icons.rotate_right,
      Color(0xFF2563EB)
    ),
    'IV': (
      'Intravenous',
      'Directly into a vein',
      '15°',
      Icons.water_drop_outlined,
      Color(0xFF059669)
    ),
    'ID': (
      'Intradermal',
      'Between skin layers',
      '10°',
      Icons.layers_outlined,
      Color(0xFFD97706)
    ),
  };

  @override
  Widget build(BuildContext context) {
    final name =
        context.watch<UserRoleProvider>().fullName ?? 'Student';

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Column(
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
                    color: Colors.white54, fontSize: 12)),
          ],
        ),
        actions: [
          // My Sessions button
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
          // Sign out
          IconButton(
            key: const Key('student_signout'),
            icon: const Icon(Icons.logout, color: Colors.white38),
            tooltip: 'Sign out',
            onPressed: () async {
              await AuthService().signOut();
              context.read<UserRoleProvider>().clear();
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select Injection Type',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Choose the injection type for your return-demonstration.',
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                children:
                    InjectionConfigService.allTypes.map((type) {
                  final (label, desc, angle, icon, color) =
                      _typeDetails[type]!;
                  return _TypeCard(
                    type: type,
                    label: label,
                    description: desc,
                    angle: angle,
                    icon: icon,
                    color: color,
                  );
                }).toList(),
              ),
            ),
          ],
        ),
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
  final Color color;

  const _TypeCard({
    required this.type,
    required this.label,
    required this.description,
    required this.angle,
    required this.icon,
    required this.color,
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
              builder: (_) =>
                  DetectionScreen(injectionType: type)),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          border:
              Border.all(color: color.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 38, color: color),
            const SizedBox(height: 10),
            Text(type,
                style: TextStyle(
                    color: color,
                    fontSize: 24,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 2),
            Text(description,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white38, fontSize: 10)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('Target $angle',
                  style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}
