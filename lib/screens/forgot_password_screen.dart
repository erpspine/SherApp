import 'package:flutter/material.dart';

import '../services/api_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _identifierCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  bool _sendingCode = false;
  bool _resettingPassword = false;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  String? _fallbackToken;
  String? _deliveryChannel;

  String _normalizeIdentifier(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.contains('@')) return trimmed;

    final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return trimmed;
    if (digits.startsWith('255')) return digits;
    if (digits.startsWith('0') && digits.length == 10) {
      return '255${digits.substring(1)}';
    }
    if (digits.length == 9) return '255$digits';

    return digits;
  }

  Future<void> _sendCode() async {
    final identifier = _normalizeIdentifier(_identifierCtrl.text);
    if (identifier.isEmpty) {
      _showMessage('Enter email or phone number first.', isError: true);
      return;
    }

    _identifierCtrl.text = identifier;

    setState(() => _sendingCode = true);
    try {
      final data = await ApiService.requestPasswordReset(identifier);
      if (!mounted) return;

      final token = (data['resetToken'] ?? '').toString().trim();
      final channel = (data['channel'] ?? '').toString();

      setState(() {
        _fallbackToken = token.isNotEmpty ? token : null;
        _deliveryChannel = channel;
      });

      if (token.isNotEmpty) {
        _tokenCtrl.text = token;
      }

      final message =
          (data['message'] ?? 'Password reset token request completed.')
              .toString();
      _showMessage(message);
    } on ApiException catch (e) {
      if (!mounted) return;
      _showMessage(e.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      _showMessage(
        'Failed to request reset token. Please try again.',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _sendingCode = false);
      }
    }
  }

  Future<void> _resetPassword() async {
    final identifier = _normalizeIdentifier(_identifierCtrl.text);
    final token = _tokenCtrl.text.trim();
    final newPassword = _newPasswordCtrl.text;
    final confirmPassword = _confirmPasswordCtrl.text;

    _identifierCtrl.text = identifier;

    if (identifier.isEmpty) {
      _showMessage('Email or phone number is required.', isError: true);
      return;
    }
    if (token.isEmpty) {
      _showMessage('Reset token is required.', isError: true);
      return;
    }
    if (newPassword.length < 8) {
      _showMessage(
        'New password must be at least 8 characters.',
        isError: true,
      );
      return;
    }
    if (newPassword != confirmPassword) {
      _showMessage('Password confirmation does not match.', isError: true);
      return;
    }

    setState(() => _resettingPassword = true);
    try {
      final data = await ApiService.resetPassword(
        identifier: identifier,
        token: token,
        password: newPassword,
        passwordConfirmation: confirmPassword,
      );
      if (!mounted) return;

      final message = (data['message'] ?? 'Password reset successfully.')
          .toString();
      _showMessage(message);

      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      _showMessage(e.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      _showMessage(
        'Failed to reset password. Please try again.',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _resettingPassword = false);
      }
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? const Color(0xFFB42318) : null,
      ),
    );
  }

  @override
  void dispose() {
    _identifierCtrl.dispose();
    _tokenCtrl.dispose();
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final busy = _sendingCode || _resettingPassword;

    return Scaffold(
      appBar: AppBar(title: const Text('Reset Password')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Use your email or phone number to receive a reset token, then set a new password.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _identifierCtrl,
                enabled: !busy,
                keyboardType: TextInputType.text,
                decoration: const InputDecoration(
                  labelText: 'Email or Phone',
                  hintText: 'example: 0760299974 or +255760299974',
                  helperText:
                      'Phone accepted as 076..., 760..., 255..., or +255...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 44,
                child: ElevatedButton(
                  onPressed: busy ? null : _sendCode,
                  child: _sendingCode
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Send Reset Token'),
                ),
              ),
              if (_fallbackToken != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF4E6),
                    border: Border.all(color: const Color(0xFFFFB020)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.info_outline,
                            color: Color(0xFFB87503),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _deliveryChannel == 'sms'
                                  ? 'SMS delivery unavailable'
                                  : 'Email delivery unavailable',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFB87503),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Your reset token is displayed below. Copy it and paste into the Reset Token field:',
                        style: TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: SelectableText(
                                _fallbackToken!,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'monospace',
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 18),
                              onPressed: () {
                                _tokenCtrl.text = _fallbackToken!;
                                _showMessage('Token copied to field');
                              },
                              tooltip: 'Copy to field',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              TextField(
                controller: _tokenCtrl,
                enabled: !busy,
                decoration: const InputDecoration(
                  labelText: 'Reset Token',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _newPasswordCtrl,
                enabled: !busy,
                obscureText: _obscureNew,
                decoration: InputDecoration(
                  labelText: 'New Password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscureNew = !_obscureNew),
                    icon: Icon(
                      _obscureNew
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmPasswordCtrl,
                enabled: !busy,
                obscureText: _obscureConfirm,
                decoration: InputDecoration(
                  labelText: 'Confirm New Password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    onPressed: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                    icon: Icon(
                      _obscureConfirm
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: busy ? null : _resetPassword,
                  child: _resettingPassword
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Reset Password'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
