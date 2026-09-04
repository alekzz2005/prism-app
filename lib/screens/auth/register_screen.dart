import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import 'email_verification_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _authService = AuthService();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _error;

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String? _validatePassword(String? v) {
    if (v == null || v.isEmpty) return 'Enter a password';
    if (v.length < 8) return 'Password must be at least 8 characters';
    if (!RegExp(r'[A-Z]').hasMatch(v)) return 'Must include at least 1 uppercase letter (A-Z)';
    if (!RegExp(r'[a-z]').hasMatch(v)) return 'Must include at least 1 lowercase letter (a-z)';
    if (!RegExp(r'[0-9!@#\$%^&*(),.?":{}|<>]').hasMatch(v)) {
      return 'Must include at least 1 number or special character';
    }
    return null;
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final first = _firstNameController.text.trim();
    final middleRaw = _middleNameController.text.trim();
    final middleInitial = middleRaw.isNotEmpty ? middleRaw[0].toUpperCase() : '';
    final last = _lastNameController.text.trim();

    final fullName = middleInitial.isNotEmpty
        ? '$first $middleInitial. $last'
        : '$first $last';

    try {
      await _authService.register(
        email: _emailController.text.trim().toLowerCase(),
        password: _passwordController.text,
        fullName: fullName,
      );
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const EmailVerificationScreen()),
        (_) => false,
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      body: Stack(
        children: [
          // Background top section
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.of(context).size.height * 0.35,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFF003366),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(40),
                  bottomRight: Radius.circular(40),
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: -50,
                    right: -50,
                    child: CircleAvatar(
                      radius: 100,
                      backgroundColor: const Color(0xFF004080).withValues(alpha: 0.4),
                    ),
                  ),
                  Positioned(
                    top: 50,
                    left: -30,
                    child: CircleAvatar(
                      radius: 70,
                      backgroundColor: const Color(0xFF002244).withValues(alpha: 0.3),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: Column(
                        children: [
                          const Text(
                            'Create Account',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Join PRISM to monitor your injection skills',
                            style: TextStyle(
                              color: Color(0xFFA8C4E0),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Main Card
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(24),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // First Name
                                  _label('FIRST NAME'),
                                  TextFormField(
                                    key: const Key('register_first_name'),
                                    controller: _firstNameController,
                                    textCapitalization: TextCapitalization.words,
                                    style: const TextStyle(color: Color(0xFF1A2B3C)),
                                    decoration: _inputDecoration('e.g. Juan', Icons.person_outline),
                                    validator: (v) =>
                                        (v == null || v.trim().isEmpty) ? 'Enter your first name' : null,
                                  ),
                                  const SizedBox(height: 14),

                                  // Middle Name
                                  _label('MIDDLE NAME (OPTIONAL)'),
                                  TextFormField(
                                    key: const Key('register_middle_name'),
                                    controller: _middleNameController,
                                    textCapitalization: TextCapitalization.words,
                                    style: const TextStyle(color: Color(0xFF1A2B3C)),
                                    decoration: _inputDecoration('e.g. Dela Cruz', Icons.person_outline),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Only the first letter will be saved as the middle initial.',
                                    style: TextStyle(color: Color(0xFF8A9BB0), fontSize: 10),
                                  ),
                                  const SizedBox(height: 14),

                                  // Last Name
                                  _label('LAST NAME'),
                                  TextFormField(
                                    key: const Key('register_last_name'),
                                    controller: _lastNameController,
                                    textCapitalization: TextCapitalization.words,
                                    style: const TextStyle(color: Color(0xFF1A2B3C)),
                                    decoration: _inputDecoration('e.g. Santos', Icons.badge_outlined),
                                    validator: (v) =>
                                        (v == null || v.trim().isEmpty) ? 'Enter your last name' : null,
                                  ),
                                  const SizedBox(height: 14),

                                  // Email Address
                                  _label('EMAIL ADDRESS'),
                                  TextFormField(
                                    key: const Key('register_email'),
                                    controller: _emailController,
                                    keyboardType: TextInputType.emailAddress,
                                    style: const TextStyle(color: Color(0xFF1A2B3C)),
                                    decoration: _inputDecoration('e.g. student@cit.edu', Icons.email_outlined),
                                    validator: (v) {
                                      if (v == null || v.trim().isEmpty) return 'Enter your email address';
                                      final clean = v.trim().toLowerCase();
                                      if (!AuthService.isValidEmail(clean)) {
                                        return 'Please enter a valid email address';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 14),

                                  // Password
                                  _label('PASSWORD'),
                                  TextFormField(
                                    key: const Key('register_password'),
                                    controller: _passwordController,
                                    obscureText: _obscurePassword,
                                    style: const TextStyle(color: Color(0xFF1A2B3C)),
                                    decoration: _inputDecoration(
                                      'Create a password',
                                      Icons.lock_outline,
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _obscurePassword
                                              ? Icons.visibility_off_outlined
                                              : Icons.visibility_outlined,
                                          color: const Color(0xFF8A9BB0),
                                          size: 20,
                                        ),
                                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                      ),
                                    ),
                                    validator: _validatePassword,
                                  ),
                                   const SizedBox(height: 4),

                                   // Password Requirements
                                   Padding(
                                     padding: const EdgeInsets.only(left: 2),
                                     child: Column(
                                       crossAxisAlignment: CrossAxisAlignment.start,
                                       children: const [
                                         Text('• Must be at least 8 characters long', style: TextStyle(color: Color(0xFF8A9BB0), fontSize: 10)),
                                         SizedBox(height: 2),
                                         Text('• Must include uppercase (A–Z) & lowercase (a–z)', style: TextStyle(color: Color(0xFF8A9BB0), fontSize: 10)),
                                         SizedBox(height: 2),
                                         Text('• Must include at least 1 number or special character', style: TextStyle(color: Color(0xFF8A9BB0), fontSize: 10)),
                                       ],
                                     ),
                                   ),
                                   const SizedBox(height: 14),

                                  // Confirm Password
                                  _label('CONFIRM PASSWORD'),
                                  TextFormField(
                                    key: const Key('register_confirm_password'),
                                    controller: _confirmPasswordController,
                                    obscureText: _obscureConfirmPassword,
                                    style: const TextStyle(color: Color(0xFF1A2B3C)),
                                    decoration: _inputDecoration(
                                      'Re-enter password',
                                      Icons.check_circle_outline_rounded,
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _obscureConfirmPassword
                                              ? Icons.visibility_off_outlined
                                              : Icons.visibility_outlined,
                                          color: const Color(0xFF8A9BB0),
                                          size: 20,
                                        ),
                                        onPressed: () => setState(
                                            () => _obscureConfirmPassword = !_obscureConfirmPassword),
                                      ),
                                    ),
                                    validator: (v) {
                                      if (v == null || v.isEmpty) return 'Confirm your password';
                                      if (v != _passwordController.text) return 'Passwords do not match';
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 18),

                                  // Role display
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF4F7FB),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: const Color(0xFFE2EAF4)),
                                    ),
                                    child: const Row(
                                      children: [
                                        Icon(Icons.school_outlined, color: Color(0xFF8A9BB0), size: 18),
                                        SizedBox(width: 10),
                                        Text('Role:', style: TextStyle(color: Color(0xFF8A9BB0), fontSize: 13)),
                                        SizedBox(width: 4),
                                        Text(
                                          'Nursing Student',
                                          style: TextStyle(
                                            color: Color(0xFF003366),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 20),

                                  if (_error != null) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFEF2F2),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: const Color(0xFFFCA5A5)),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 16),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              _error!,
                                              style: const TextStyle(color: Color(0xFF991B1B), fontSize: 12),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                  ],

                                  ElevatedButton(
                                    key: const Key('register_submit'),
                                    onPressed: _isLoading ? null : _register,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF003366),
                                      padding: const EdgeInsets.symmetric(vertical: 15),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      elevation: 0,
                                    ),
                                    child: _isLoading
                                        ? const SizedBox(
                                            height: 20,
                                            width: 20,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2, color: Colors.white),
                                          )
                                        : const Text(
                                            'Sign Up',
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                "Already have an account? ",
                                style: TextStyle(color: Color(0xFF8A9BB0), fontWeight: FontWeight.w500),
                              ),
                              GestureDetector(
                                onTap: () => Navigator.pop(context),
                                child: const Text(
                                  "Sign In",
                                  style: TextStyle(
                                    color: Color(0xFF003366),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF003366),
            letterSpacing: 0.8,
          ),
        ),
      );

  InputDecoration _inputDecoration(String hint, IconData icon, {Widget? suffixIcon}) =>
      InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFFB0BEC5), fontSize: 13),
        prefixIcon: Icon(icon, color: const Color(0xFF8A9BB0), size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2EAF4)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2EAF4)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF003366), width: 1.5),
        ),
      );

}
