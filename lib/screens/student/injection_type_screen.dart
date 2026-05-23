import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../core/injection_config.dart';
import '../../providers/session_state_provider.dart';
import '../../services/auth_service.dart';
import '../../providers/user_role_provider.dart';
import '../../widgets/auth_wrapper.dart';
import 'detection_screen.dart';
import 'my_sessions_screen.dart';
import '../shared/profile_screen.dart';

/// UC-3.2 — Student selects an injection type before starting a session.
class InjectionTypeScreen extends StatelessWidget {
  const InjectionTypeScreen({super.key});

  static const _typeDetails = {
    'IM': (
      'Intramuscular',
      'Deep muscle tissue injection',
      '90°',
      '''<svg width="28" height="28" viewBox="0 0 28 28" fill="none" xmlns="http://www.w3.org/2000/svg">
          <path d="M14 22V6M14 6l-5 5M14 6l5 5" stroke="#003366" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
        </svg>''',
    ),
    'SubQ': (
      'Subcutaneous',
      'Fat layer beneath the skin',
      '45°',
      '''<svg width="28" height="28" viewBox="0 0 28 28" fill="none" xmlns="http://www.w3.org/2000/svg">
          <path d="M6 22L22 6" stroke="#003366" stroke-width="2" stroke-linecap="round"/>
          <path d="M22 6l-6 0M22 6l0 6" stroke="#003366" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
        </svg>''',
    ),
    'IV': (
      'Intravenous',
      'Directly into a vein',
      '15°',
      '''<svg width="28" height="28" viewBox="0 0 28 28" fill="none" xmlns="http://www.w3.org/2000/svg">
          <circle cx="14" cy="10" r="4" stroke="#003366" stroke-width="1.8"/>
          <path d="M7 22c0-4 14-4 14 0" stroke="#003366" stroke-width="1.8" stroke-linecap="round"/>
          <path d="M14 14v4" stroke="#003366" stroke-width="1.8" stroke-linecap="round"/>
        </svg>''',
    ),
    'ID': (
      'Intradermal',
      'Between skin layers',
      '10°',
      '''<svg width="28" height="28" viewBox="0 0 28 28" fill="none" xmlns="http://www.w3.org/2000/svg">
          <rect x="4" y="10" width="20" height="4" rx="2" stroke="#003366" stroke-width="1.8"/>
          <rect x="4" y="16" width="20" height="4" rx="2" stroke="#003366" stroke-width="1.8" opacity="0.4"/>
        </svg>''',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final name = context.watch<UserRoleProvider>().fullName ?? 'Student';

    return Scaffold(
      backgroundColor: const Color(0xFFE8EDF2),
      body: Column(
        children: [
          // ── Navy header block ──
          Container(
            color: const Color(0xFF003366),
            child: Stack(
              children: [
                // Decorative circles
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

                // Content
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // AppBar row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'PRISM',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 2,
                                    height: 1.0,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Welcome, $name',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                // History icon
                                GestureDetector(
                                  key: const Key('my_sessions_button'),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const MySessionsScreen()),
                                  ),
                                  child: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      color: Colors.transparent,
                                    ),
                                    alignment: Alignment.center,
                                    child: SvgPicture.string(
                                      '''<svg width="22" height="22" viewBox="0 0 22 22" fill="none" xmlns="http://www.w3.org/2000/svg">
                                          <circle cx="11" cy="11" r="8" stroke="rgba(255,255,255,0.7)" stroke-width="1.6"/>
                                          <path d="M11 7v4.5l3 1.8" stroke="rgba(255,255,255,0.7)" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>
                                          <path d="M4.5 4.5L3 3M17.5 4.5L19 3" stroke="rgba(255,255,255,0.4)" stroke-width="1.3" stroke-linecap="round"/>
                                        </svg>''',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 2),
                                // Logout icon
                                GestureDetector(
                                  key: const Key('student_signout'),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => const ProfileScreen()),
                                    );
                                  },
                                  child: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      color: Colors.transparent,
                                    ),
                                    alignment: Alignment.center,
                                    child: SvgPicture.string(
                                      '''<svg width="20" height="20" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
                                          <path d="M7 17H4a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h3" stroke="rgba(255,255,255,0.38)" stroke-width="1.5" stroke-linecap="round"/>
                                          <path d="M13 14l4-4-4-4M17 10H8" stroke="rgba(255,255,255,0.38)" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
                                        </svg>''',
                                    ),
                                  ),
                                ),
                              ],
                            )
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Title block
                        const Text(
                          'Select Injection Type',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Choose the injection type for your return-demonstration.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Card list ──
          Expanded(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: ListView.separated(
                padding: EdgeInsets.zero,
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
                    iconSvg: details.$4,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeCard extends StatefulWidget {
  final String type;
  final String label;
  final String description;
  final String angle;
  final String iconSvg;

  const _TypeCard({
    required this.type,
    required this.label,
    required this.description,
    required this.angle,
    required this.iconSvg,
  });

  @override
  State<_TypeCard> createState() => _TypeCardState();
}

class _TypeCardState extends State<_TypeCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        key: Key('injection_type_${widget.type}'),
        onTap: () {
          final config = InjectionConfigService.getConfig(widget.type);
          context.read<SessionStateProvider>().setConfig(config);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DetectionScreen(injectionType: widget.type),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(
              color: _isHovered ? const Color(0xFFA8C4E0) : const Color(0xFFE2EAF4),
              width: 2,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
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
                alignment: Alignment.center,
                child: SvgPicture.string(widget.iconSvg),
              ),
              const SizedBox(width: 16),

              // Text Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${widget.label} (${widget.type})',
                      style: const TextStyle(
                        color: Color(0xFF003366),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.description,
                      style: const TextStyle(
                        color: Color(0xFF8A9BB0),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),

              // Target Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF3F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Target ${widget.angle}',
                  style: const TextStyle(
                    color: Color(0xFF4A7BAF),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
