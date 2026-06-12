import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import 'driver_trips_screen.dart';
import 'drivers_screen.dart';
import 'forgot_password_screen.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _obscure = true;
  bool _rememberMe = false;
  bool _busy = false;
  String? _emailError;
  String? _passError;

  bool _validateInputs() {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text.trim();

    String? emailError;
    String? passError;

    if (email.isEmpty) {
      emailError = 'Email is required';
    } else if (!email.contains('@')) {
      emailError = 'Enter a valid email address';
    }

    if (pass.isEmpty) {
      passError = 'Password is required';
    }

    setState(() {
      _emailError = emailError;
      _passError = passError;
    });

    return emailError == null && passError == null;
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text.trim();
    if (!_validateInputs()) return;

    setState(() => _busy = true);
    final auth = context.read<AuthProvider>();
    final ok = await auth.login(email, pass, rememberMe: _rememberMe);
    if (!mounted) return;

    setState(() => _busy = false);
    if (!ok) return;

    if (auth.hasRole('Driver')) {
      Map<String, dynamic>? user;
      try {
        user = await ApiService.refreshMeCache();
      } catch (_) {
        user = await ApiService.getCurrentUser();
      }
      if (!mounted) return;

      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => user == null
              ? const DriversScreen()
              : DriverTripsScreen(driver: user!, useCurrentAssignments: true),
        ),
        (_) => false,
      );
      return;
    }

    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (_) => false,
    );
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F5),
      body: Stack(
        children: [
          Positioned(
            left: -120,
            bottom: -140,
            child: Container(
              width: 340,
              height: 340,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFFDFA1).withOpacity(0.22),
              ),
            ),
          ),
          Positioned(
            right: -160,
            top: -90,
            child: Container(
              width: 380,
              height: 380,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFE9C778).withOpacity(0.45),
                  width: 28,
                ),
              ),
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 400;

              return SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: SafeArea(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 460),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            isCompact ? 12 : 16,
                            22,
                            isCompact ? 12 : 16,
                            20,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                padding: EdgeInsets.fromLTRB(
                                  isCompact ? 14 : 20,
                                  isCompact ? 18 : 22,
                                  isCompact ? 14 : 20,
                                  18,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFFFFF),
                                  borderRadius: BorderRadius.circular(26),
                                  border: Border.all(
                                    color: const Color(0xFFE6E9F0),
                                    width: 1.2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(
                                        0xFF101828,
                                      ).withOpacity(0.08),
                                      blurRadius: 28,
                                      offset: const Offset(0, 12),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF8F1DD),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: const Text(
                                        'SHER ERP',
                                        style: TextStyle(
                                          color: Color(0xFFB88910),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    const Text(
                                      'Welcome Back',
                                      style: TextStyle(
                                        color: Color(0xFF0F1F3D),
                                        fontSize: 24,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'Sign in to your Sher ERP account',
                                      style: TextStyle(
                                        color: Color(0xFF667085),
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    if (auth.error != null) ...[
                                      _errorBanner(auth.error!),
                                      const SizedBox(height: 10),
                                    ],
                                    _fieldBox(
                                      icon: Icons.email_outlined,
                                      label: 'Email Address',
                                      controller: _emailCtrl,
                                      obscureText: false,
                                      errorText: _emailError,
                                      suffix: const SizedBox(
                                        width: 28,
                                        height: 28,
                                        child: Icon(
                                          Icons.visibility_outlined,
                                          size: 20,
                                          color: Colors.transparent,
                                        ),
                                      ),
                                      keyboardType: TextInputType.emailAddress,
                                      onChanged: (_) {
                                        if (_emailError != null) {
                                          setState(() => _emailError = null);
                                        }
                                      },
                                    ),
                                    const SizedBox(height: 12),
                                    _fieldBox(
                                      icon: Icons.lock_outline,
                                      label: 'Password',
                                      controller: _passCtrl,
                                      obscureText: _obscure,
                                      errorText: _passError,
                                      onChanged: (_) {
                                        if (_passError != null) {
                                          setState(() => _passError = null);
                                        }
                                      },
                                      onSubmitted: (_) => _submit(),
                                      suffix: IconButton(
                                        onPressed: () => setState(
                                          () => _obscure = !_obscure,
                                        ),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                          minWidth: 28,
                                          minHeight: 28,
                                        ),
                                        splashRadius: 18,
                                        icon: Icon(
                                          _obscure
                                              ? Icons.visibility_off_outlined
                                              : Icons.visibility_outlined,
                                          color: const Color(0xFF7B8190),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      alignment: WrapAlignment.spaceBetween,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      runSpacing: 4,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Checkbox(
                                              value: _rememberMe,
                                              onChanged: (value) => setState(
                                                () =>
                                                    _rememberMe = value ?? true,
                                              ),
                                              side: const BorderSide(
                                                color: Color(0xFFD4B25E),
                                              ),
                                              activeColor: const Color(
                                                0xFFD4A72C,
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(5),
                                              ),
                                            ),
                                            const Text(
                                              'Remember me',
                                              style: TextStyle(
                                                color: Color(0xFF344054),
                                                fontSize: 16,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                        TextButton(
                                          onPressed: () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    const ForgotPasswordScreen(),
                                              ),
                                            );
                                          },
                                          style: TextButton.styleFrom(
                                            minimumSize: Size.zero,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                              vertical: 4,
                                            ),
                                            tapTargetSize: MaterialTapTargetSize
                                                .shrinkWrap,
                                          ),
                                          child: const Text(
                                            'Forgot Password?',
                                            style: TextStyle(
                                              color: Color(0xFFC08E13),
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    SizedBox(
                                      width: double.infinity,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [
                                              Color(0xFFDBAE32),
                                              Color(0xFFBF8F18),
                                            ],
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(
                                                0xFFD6A32B,
                                              ).withOpacity(0.35),
                                              blurRadius: 12,
                                              offset: const Offset(0, 6),
                                            ),
                                          ],
                                        ),
                                        child: ElevatedButton(
                                          onPressed: _busy ? null : _submit,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.transparent,
                                            shadowColor: Colors.transparent,
                                            foregroundColor: Colors.white,
                                            disabledForegroundColor:
                                                Colors.white70,
                                            disabledBackgroundColor:
                                                Colors.transparent,
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 16,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                            ),
                                          ),
                                          child: _busy
                                              ? const SizedBox(
                                                  width: 22,
                                                  height: 22,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: Colors.white,
                                                      ),
                                                )
                                              : Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    SizedBox(
                                                      width: isCompact
                                                          ? 10
                                                          : 20,
                                                    ),
                                                    const Expanded(
                                                      child: Text(
                                                        'Sign In',
                                                        textAlign:
                                                            TextAlign.center,
                                                        style: TextStyle(
                                                          fontSize: 20,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                    ),
                                                    const Icon(
                                                      Icons.arrow_forward,
                                                      size: 24,
                                                    ),
                                                  ],
                                                ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Column(
                                children: [
                                  Text(
                                    'Secure  •  Reliable  •  Trusted',
                                    style: TextStyle(
                                      color: Color(0xFF667085),
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    '© 2026 Sher Vehicle Leasing. All rights reserved.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Color(0xFF98A2B3),
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _fieldBox({
    required IconData icon,
    required String label,
    required TextEditingController controller,
    required bool obscureText,
    String? errorText,
    Widget? suffix,
    TextInputType? keyboardType,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(left: 2, right: 2, bottom: 6),
            child: _errorBanner(errorText),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFFFFFF), Color(0xFFFCFCFE)],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: errorText == null
                  ? const Color(0xFFD9DCE2)
                  : const Color(0xFFEC928F),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F1DD),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFB88910).withOpacity(0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(icon, color: const Color(0xFFB88910)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Color(0xFF475467),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    TextField(
                      controller: controller,
                      keyboardType: keyboardType,
                      obscureText: obscureText,
                      onChanged: onChanged,
                      onSubmitted: onSubmitted,
                      textAlignVertical: TextAlignVertical.center,
                      style: const TextStyle(
                        color: Color(0xFF1D2939),
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        border: InputBorder.none,
                        suffixIcon: suffix,
                        suffixIconConstraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                          maxWidth: 36,
                          maxHeight: 36,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _errorBanner(String? message) {
    if (message == null || message.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF2F1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF4B6B4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              Icons.error_outline,
              size: 16,
              color: Color(0xFFB42318),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFB42318),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
