import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../config/app_config.dart';
import '../services/api_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

const int kGoldColor = 0xFFC9A961;

class _SettingsScreenState extends State<SettingsScreen> {
  int _tabIndex = 0;
  bool _loading = false;
  bool _saving = false;
  bool _picking = false;

  // Profile controllers
  final _profileFirstNameCtrl = TextEditingController();
  final _profileLastNameCtrl = TextEditingController();
  final _profileEmailCtrl = TextEditingController();
  final _profilePhoneCtrl = TextEditingController();
  final _profileAddressCtrl = TextEditingController();

  // Company controllers
  final _companyNameCtrl = TextEditingController();
  final _companyEmailCtrl = TextEditingController();
  final _companyPhoneCtrl = TextEditingController();
  final _companyAddressCtrl = TextEditingController();
  final _companyTaxCtrl = TextEditingController();
  final _companyVatCtrl = TextEditingController(text: '18');
  String _companyCurrency = 'TZS';
  String? _logoPath;
  String? _logoUrl;

  // Security controllers
  final _currentPasswordCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  bool _showPassword = false;

  // Notifications toggles
  bool _emailNotifications = true;
  bool _pushNotifications = true;
  bool _invoiceNotifications = true;
  bool _paymentReminders = true;

  // Appearance settings
  String _theme = 'light';
  String _language = 'en';

  TextStyle get _sectionTitleStyle =>
      Theme.of(context).textTheme.titleLarge!.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.1,
        color: Theme.of(context).colorScheme.onSurface,
      );

  TextStyle get _sectionSubtitleStyle =>
      Theme.of(context).textTheme.bodyMedium!.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        height: 1.35,
      );

  TextStyle get _fieldLabelStyle =>
      Theme.of(context).textTheme.labelLarge!.copyWith(
        fontWeight: FontWeight.w600,
        fontSize: 12,
        letterSpacing: 0,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );

  TextStyle get _fieldValueStyle =>
      Theme.of(context).textTheme.bodyLarge!.copyWith(
        fontWeight: FontWeight.w500,
        fontSize: 15,
        height: 1.25,
        color: Theme.of(context).colorScheme.onSurface,
      );

  BoxDecoration get _panelDecoration => BoxDecoration(
    color: const Color(0xFFFFFCF7),
    borderRadius: BorderRadius.circular(24),
    border: Border.all(color: const Color(0xFFE7DED0)),
    boxShadow: const [
      BoxShadow(
        color: Color(0x110F172A),
        blurRadius: 20,
        offset: Offset(0, 10),
      ),
    ],
  );

  BoxDecoration get _fieldDecoration => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: const Color(0xFFE3DACB)),
    boxShadow: const [
      BoxShadow(color: Color(0x0A0F172A), blurRadius: 10, offset: Offset(0, 4)),
    ],
  );

  @override
  void initState() {
    super.initState();
    _loadCompanySettings();
    _loadProfile();
  }

  @override
  void dispose() {
    _profileFirstNameCtrl.dispose();
    _profileLastNameCtrl.dispose();
    _profileEmailCtrl.dispose();
    _profilePhoneCtrl.dispose();
    _profileAddressCtrl.dispose();
    _companyNameCtrl.dispose();
    _companyEmailCtrl.dispose();
    _companyPhoneCtrl.dispose();
    _companyAddressCtrl.dispose();
    _companyTaxCtrl.dispose();
    _companyVatCtrl.dispose();
    _currentPasswordCtrl.dispose();
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      dynamic data;
      try {
        data = await ApiService.get('/profile');
      } catch (_) {
        try {
          data = await ApiService.get('/user');
        } catch (_) {
          return; // Both endpoints failed
        }
      }

      if (data == null) return;

      final profile = _extractProfileMap(data);
      if (profile == null || profile.isEmpty) return;

      final fullName = _stringFrom(profile, const [
        'name',
        'full_name',
        'fullName',
        'username',
      ]);
      final nameParts = _splitName(fullName);
      final firstName = _stringFrom(profile, const ['first_name', 'firstName']);
      final lastName = _stringFrom(profile, const ['last_name', 'lastName']);

      if (!mounted) return;
      setState(() {
        _profileFirstNameCtrl.text = firstName.isNotEmpty
            ? firstName
            : nameParts.$1;
        _profileLastNameCtrl.text = lastName.isNotEmpty
            ? lastName
            : nameParts.$2;
        _profileEmailCtrl.text = _stringFrom(profile, const ['email']);
        _profilePhoneCtrl.text = _stringFrom(profile, const [
          'phone',
          'phone_number',
          'phoneNumber',
          'mobile',
          'telephone',
        ]);
        _profileAddressCtrl.text = _stringFrom(profile, const [
          'address',
          'physical_address',
          'physicalAddress',
          'location',
        ]);
      });
    } catch (e) {
      debugPrint('Profile load error: $e');
    }
  }

  Map<String, dynamic>? _extractProfileMap(dynamic data) {
    if (data is! Map) return null;

    final root = Map<String, dynamic>.from(data);
    for (final key in const ['data', 'user', 'profile', 'settings']) {
      final nested = root[key];
      if (nested is Map) {
        final map = Map<String, dynamic>.from(nested);
        if (_looksLikeProfile(map)) return map;

        for (final nestedKey in const ['user', 'profile']) {
          final deeper = map[nestedKey];
          if (deeper is Map) {
            final deeperMap = Map<String, dynamic>.from(deeper);
            if (_looksLikeProfile(deeperMap)) return deeperMap;
          }
        }
      }
    }

    return _looksLikeProfile(root) ? root : root;
  }

  bool _looksLikeProfile(Map<String, dynamic> map) {
    return const [
      'first_name',
      'firstName',
      'last_name',
      'lastName',
      'name',
      'full_name',
      'fullName',
      'email',
      'phone',
      'phone_number',
      'mobile',
      'address',
    ].any(map.containsKey);
  }

  String _stringFrom(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value == null) continue;

      final text = value.toString().trim();
      if (text.isNotEmpty && text.toLowerCase() != 'null') {
        return text;
      }
    }
    return '';
  }

  (String, String) _splitName(String fullName) {
    final normalized = fullName.trim();
    if (normalized.isEmpty) return ('', '');

    final parts = normalized
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return ('', '');
    if (parts.length == 1) return (parts.first, '');

    return (parts.first, parts.sublist(1).join(' '));
  }

  Future<void> _loadCompanySettings() async {
    setState(() => _loading = true);
    try {
      final data = await ApiService.get('/settings/company');
      final settings = (data['settings'] ?? data['data'] ?? data) as Map;

      if (!mounted) return;
      setState(() {
        _companyNameCtrl.text = (settings['company_name'] ?? '').toString();
        _companyEmailCtrl.text = (settings['company_email'] ?? '').toString();
        _companyPhoneCtrl.text = (settings['company_phone'] ?? '').toString();
        _companyAddressCtrl.text = (settings['company_address'] ?? '')
            .toString();
        _companyTaxCtrl.text = (settings['tax_registration_number'] ?? '')
            .toString();
        _companyVatCtrl.text =
            (settings['default_vat'] ?? settings['defaultVat'] ?? '18')
                .toString();

        final rawCurrency = (settings['default_currency'] ?? 'TZS')
            .toString()
            .toUpperCase()
            .trim();
        _companyCurrency = rawCurrency == 'TZ' ? 'TZS' : rawCurrency;
        if (_companyCurrency != 'TZS' && _companyCurrency != 'USD') {
          _companyCurrency = 'TZS';
        }

        final logo = (settings['logo_url'] ?? settings['logoUrl'] ?? '')
            .toString();
        if (logo.isEmpty) {
          _logoUrl = null;
        } else if (logo.startsWith('http://') || logo.startsWith('https://')) {
          _logoUrl = logo;
        } else {
          _logoUrl = '$kBackendOrigin${logo.startsWith('/') ? '' : '/'}$logo';
        }
      });
    } catch (_) {
      //
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1400,
    );
    if (xfile == null) return;
    setState(() => _logoPath = xfile.path);
  }

  Future<void> _saveProfile() async {
    setState(() => _saving = true);
    try {
      try {
        await ApiService.put('/profile', {
          'first_name': _profileFirstNameCtrl.text.trim(),
          'last_name': _profileLastNameCtrl.text.trim(),
          'email': _profileEmailCtrl.text.trim(),
          'phone': _profilePhoneCtrl.text.trim(),
          'address': _profileAddressCtrl.text.trim(),
        });
      } catch (_) {
        await ApiService.post('/profile', {
          'first_name': _profileFirstNameCtrl.text.trim(),
          'last_name': _profileLastNameCtrl.text.trim(),
          'email': _profileEmailCtrl.text.trim(),
          'phone': _profilePhoneCtrl.text.trim(),
          'address': _profileAddressCtrl.text.trim(),
          '_method': 'PUT',
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile saved successfully.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Profile update failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveCompany() async {
    setState(() => _saving = true);
    try {
      final body = {
        'company_name': _companyNameCtrl.text,
        'company_email': _companyEmailCtrl.text,
        'company_phone': _companyPhoneCtrl.text,
        'company_address': _companyAddressCtrl.text,
        'tax_registration_number': _companyTaxCtrl.text,
        'default_currency': _companyCurrency,
        'default_vat': _companyVatCtrl.text,
      };

      await ApiService.post('/settings/company', body);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Company settings saved successfully.')),
      );
      await _loadCompanySettings();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Company save failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _updatePassword() async {
    final current = _currentPasswordCtrl.text.trim();
    final next = _newPasswordCtrl.text.trim();
    final confirm = _confirmPasswordCtrl.text.trim();

    if (current.isEmpty || next.isEmpty || confirm.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fill all password fields.')),
      );
      return;
    }
    if (next != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password confirmation does not match.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await ApiService.post('/change-password', {
        'current_password': current,
        'password': next,
        'password_confirmation': confirm,
      });

      _currentPasswordCtrl.clear();
      _newPasswordCtrl.clear();
      _confirmPasswordCtrl.clear();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated successfully.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Password update failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F3EC),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                _buildTabSelector(),
                const SizedBox(height: 18),
                if (_tabIndex == 0) _buildProfileTab(),
                if (_tabIndex == 1) _buildCompanyTab(),
                if (_tabIndex == 2) _buildNotificationsTab(),
                if (_tabIndex == 3) _buildAppearanceTab(),
                if (_tabIndex == 4) _buildSecurityTab(),
              ],
            ),
    );
  }

  Widget _buildTabSelector() {
    const tabs = [
      'Profile',
      'Company',
      'Notifications',
      'Appearance',
      'Security',
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(
          tabs.length,
          (ix) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(tabs[ix]),
              ),
              selected: _tabIndex == ix,
              onSelected: (selected) {
                if (selected) setState(() => _tabIndex = ix);
              },
              selectedColor: const Color(kGoldColor),
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: _tabIndex == ix
                      ? const Color(kGoldColor)
                      : const Color(0xFFE7DED0),
                ),
              ),
              side: BorderSide(
                color: _tabIndex == ix
                    ? const Color(kGoldColor)
                    : const Color(0xFFE7DED0),
              ),
              labelStyle: TextStyle(
                color: _tabIndex == ix ? Colors.white : const Color(0xFF5B6770),
                fontWeight: _tabIndex == ix ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompanyTab() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _panelDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHero(
            icon: Icons.apartment_rounded,
            title: 'Company Information',
            subtitle:
                'Manage the business details shown across invoices, quotations, and reports.',
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF4EEE3),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE7DED0)),
            ),
            child: Row(
              children: [
                _logoPreview(),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Company Logo',
                        style: _fieldLabelStyle.copyWith(fontSize: 15),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Upload a square logo for quotes, invoices, and exported documents.',
                        style: _sectionSubtitleStyle.copyWith(fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.tonalIcon(
                        onPressed: _picking ? null : _pickLogo,
                        icon: const Icon(Icons.upload_rounded),
                        label: const Text('Change Logo'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF1F2937),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _companyNameCtrl,
            label: 'Company Name',
            icon: Icons.business,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: _companyEmailCtrl,
            label: 'Email',
            icon: Icons.email,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: _companyPhoneCtrl,
            label: 'Phone',
            icon: Icons.phone,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: _companyAddressCtrl,
            label: 'Address',
            icon: Icons.location_on,
            maxLines: 3,
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final shouldStack = constraints.maxWidth < 360;

              final taxField = _buildTextField(
                controller: _companyTaxCtrl,
                label: 'Tax Number',
                icon: Icons.description,
              );
              final vatField = _buildTextField(
                controller: _companyVatCtrl,
                label: 'Default VAT (%)',
                icon: Icons.percent,
                keyboardType: TextInputType.number,
              );

              if (shouldStack) {
                return Column(
                  children: [taxField, const SizedBox(height: 12), vatField],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: taxField),
                  const SizedBox(width: 12),
                  Expanded(child: vatField),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          _buildCurrencyDropdown(),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _saveCompany,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(kGoldColor),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(color: Colors.white),
                    )
                  : const Text(
                      'Save Company',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileTab() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _panelDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHero(
            icon: Icons.person_outline_rounded,
            title: 'Personal Information',
            subtitle: 'Update the personal details tied to your account.',
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _profileFirstNameCtrl,
            label: 'First Name',
            icon: Icons.person,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: _profileLastNameCtrl,
            label: 'Last Name',
            icon: Icons.person,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: _profileEmailCtrl,
            label: 'Email',
            icon: Icons.email,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: _profilePhoneCtrl,
            label: 'Phone',
            icon: Icons.phone,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: _profileAddressCtrl,
            label: 'Address',
            icon: Icons.location_on,
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _saveProfile,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(kGoldColor),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(color: Colors.white),
                    )
                  : const Text(
                      'Save Profile',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationsTab() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Notification Preferences',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('Email Notifications'),
            subtitle: const Text('Receive email alerts for important events'),
            value: _emailNotifications,
            onChanged: (val) => setState(() => _emailNotifications = val),
            activeColor: const Color(kGoldColor),
          ),
          SwitchListTile(
            title: const Text('Push Notifications'),
            subtitle: const Text('Receive push alerts on your device'),
            value: _pushNotifications,
            onChanged: (val) => setState(() => _pushNotifications = val),
            activeColor: const Color(kGoldColor),
          ),
          SwitchListTile(
            title: const Text('Invoice Alerts'),
            subtitle: const Text('Get notified about invoice events'),
            value: _invoiceNotifications,
            onChanged: (val) => setState(() => _invoiceNotifications = val),
            activeColor: const Color(kGoldColor),
          ),
          SwitchListTile(
            title: const Text('Payment Reminders'),
            subtitle: const Text('Get payment due reminders'),
            value: _paymentReminders,
            onChanged: (val) => setState(() => _paymentReminders = val),
            activeColor: const Color(kGoldColor),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Preferences saved.')),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(kGoldColor),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: const Text(
                'Save Preferences',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppearanceTab() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Appearance Settings',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          Text('Theme', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
          RadioListTile(
            value: 'light',
            groupValue: _theme,
            onChanged: (val) => setState(() => _theme = val ?? 'light'),
            title: const Text('Light'),
            activeColor: const Color(kGoldColor),
          ),
          RadioListTile(
            value: 'dark',
            groupValue: _theme,
            onChanged: (val) => setState(() => _theme = val ?? 'light'),
            title: const Text('Dark'),
            activeColor: const Color(kGoldColor),
          ),
          RadioListTile(
            value: 'system',
            groupValue: _theme,
            onChanged: (val) => setState(() => _theme = val ?? 'light'),
            title: const Text('System Default'),
            activeColor: const Color(kGoldColor),
          ),
          const SizedBox(height: 16),
          Text('Language', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
          DropdownButton<String>(
            value: _language,
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: 'en', child: Text('English')),
              DropdownMenuItem(value: 'sw', child: Text('Swahili')),
            ],
            onChanged: (val) => setState(() => _language = val ?? 'en'),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Theme and language updated.')),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(kGoldColor),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: const Text(
                'Save Appearance',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityTab() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Security Settings',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          _buildPasswordField(
            controller: _currentPasswordCtrl,
            label: 'Current Password',
            icon: Icons.lock,
          ),
          const SizedBox(height: 12),
          _buildPasswordField(
            controller: _newPasswordCtrl,
            label: 'New Password',
            icon: Icons.lock_outline,
          ),
          const SizedBox(height: 12),
          _buildPasswordField(
            controller: _confirmPasswordCtrl,
            label: 'Confirm Password',
            icon: Icons.lock_outline,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _updatePassword,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(kGoldColor),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(color: Colors.white),
                    )
                  : const Text(
                      'Update Password',
                      style: TextStyle(color: Colors.white),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    IconData? icon,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(label, style: _fieldLabelStyle),
        ),
        Container(
          decoration: _fieldDecoration,
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            obscureText: obscureText,
            maxLines: maxLines,
            style: _fieldValueStyle,
            decoration: InputDecoration(
              hintText: label,
              hintStyle: _fieldValueStyle.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w400,
              ),
              prefixIcon: icon != null
                  ? Padding(
                      padding: const EdgeInsets.only(left: 10, right: 6),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF5DB),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(icon, color: const Color(kGoldColor)),
                      ),
                    )
                  : null,
              prefixIconConstraints: const BoxConstraints(
                minHeight: 56,
                minWidth: 56,
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 18,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: const BorderSide(
                  color: Color(kGoldColor),
                  width: 1.6,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCurrencyDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text('Default Currency', style: _fieldLabelStyle),
        ),
        Container(
          decoration: _fieldDecoration,
          child: DropdownButtonFormField<String>(
            initialValue: _companyCurrency,
            isExpanded: true,
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
            borderRadius: BorderRadius.circular(18),
            style: _fieldValueStyle,
            items: const [
              DropdownMenuItem(
                value: 'TZS',
                child: Text('TZS - Tanzanian Shilling'),
              ),
              DropdownMenuItem(value: 'USD', child: Text('USD - US Dollar')),
            ],
            onChanged: (val) => setState(() => _companyCurrency = val ?? 'TZS'),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 16,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: const BorderSide(
                  color: Color(kGoldColor),
                  width: 1.6,
                ),
              ),
            ),
            selectedItemBuilder: (context) => const [
              Align(
                alignment: Alignment.centerLeft,
                child: Text('TZS - Tanzanian Shilling'),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('USD - US Dollar'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHero({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF4E6C2), Color(0xFFF9F4E8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: const Color(kGoldColor), size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _sectionTitleStyle),
                const SizedBox(height: 4),
                Text(subtitle, style: _sectionSubtitleStyle),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    IconData? icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(label, style: _fieldLabelStyle),
        ),
        Container(
          decoration: _fieldDecoration,
          child: TextField(
            controller: controller,
            obscureText: !_showPassword,
            style: _fieldValueStyle,
            decoration: InputDecoration(
              hintText: label,
              hintStyle: _fieldValueStyle.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w400,
              ),
              prefixIcon: icon != null
                  ? Padding(
                      padding: const EdgeInsets.only(left: 10, right: 6),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF5DB),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(icon, color: const Color(kGoldColor)),
                      ),
                    )
                  : null,
              prefixIconConstraints: const BoxConstraints(
                minHeight: 56,
                minWidth: 56,
              ),
              suffixIcon: IconButton(
                onPressed: () => setState(() => _showPassword = !_showPassword),
                icon: Icon(
                  _showPassword ? Icons.visibility : Icons.visibility_off,
                ),
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 18,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: const BorderSide(
                  color: Color(kGoldColor),
                  width: 1.6,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _logoPreview() {
    final image = _logoPath;
    if (image != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Image.file(
          File(image),
          width: 120,
          height: 120,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _logoPlaceholder(),
        ),
      );
    }

    if (_logoUrl != null && _logoUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: CachedNetworkImage(
          imageUrl: _logoUrl!,
          width: 120,
          height: 120,
          fit: BoxFit.cover,
          errorWidget: (context, url, error) => _logoPlaceholder(),
          placeholder: (context, url) => const SizedBox(
            width: 120,
            height: 120,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        ),
      );
    }

    return _logoPlaceholder();
  }

  Widget _logoPlaceholder() {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        color: const Color(0xFFF8F1E3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE7DED0)),
      ),
      child: const Icon(
        Icons.business_outlined,
        color: Color(kGoldColor),
        size: 48,
      ),
    );
  }
}
