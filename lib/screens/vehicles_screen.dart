import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../config/app_config.dart';
import '../services/api_service.dart';

class VehiclesScreen extends StatefulWidget {
  const VehiclesScreen({super.key});

  @override
  State<VehiclesScreen> createState() => _VehiclesScreenState();
}

enum _VehicleTab { all, active, inService, inactive }

enum _StatusKind { active, inService, inactive }

class _VehiclesScreenState extends State<VehiclesScreen> {
  final TextEditingController _searchCtrl = TextEditingController();

  // Form fields aligned with Vehicles.jsx createVehicleForm()
  final TextEditingController _vehicleNoCtrl = TextEditingController();
  final TextEditingController _plateNoCtrl = TextEditingController();
  final TextEditingController _makeCtrl = TextEditingController();
  final TextEditingController _modelCtrl = TextEditingController();
  final TextEditingController _yearCtrl = TextEditingController(
    text: DateTime.now().year.toString(),
  );
  final TextEditingController _seatsCtrl = TextEditingController();
  final TextEditingController _initialMileageCtrl = TextEditingController();
  final TextEditingController _chassisCtrl = TextEditingController();
  final TextEditingController _specsCtrl = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  XFile? _selectedPhoto;
  String _formStatus = 'Available';

  List<dynamic> _all = <dynamic>[];
  List<dynamic> _filtered = <dynamic>[];

  bool _loading = true;
  bool _showAddForm = false;
  _VehicleTab _tab = _VehicleTab.all;

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_applyFilters);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();

    _vehicleNoCtrl.dispose();
    _plateNoCtrl.dispose();
    _makeCtrl.dispose();
    _modelCtrl.dispose();
    _yearCtrl.dispose();
    _seatsCtrl.dispose();
    _initialMileageCtrl.dispose();
    _chassisCtrl.dispose();
    _specsCtrl.dispose();

    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ApiService.fetchList('/vehicles');
      if (!mounted) return;
      setState(() {
        _all = data;
        _loading = false;
      });
      _applyFilters();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _all = <dynamic>[];
        _filtered = <dynamic>[];
        _loading = false;
      });
    }
  }

  void _applyFilters() {
    final query = _searchCtrl.text.trim().toLowerCase();

    setState(() {
      _filtered = _all.where((row) {
        if (row is! Map) return false;

        final status = _statusFromRow(row);
        final tabMatches = switch (_tab) {
          _VehicleTab.all => true,
          _VehicleTab.active => status == _StatusKind.active,
          _VehicleTab.inService => status == _StatusKind.inService,
          _VehicleTab.inactive => status == _StatusKind.inactive,
        };

        if (!tabMatches) return false;

        if (query.isEmpty) return true;

        final make = (row['make'] ?? '').toString().toLowerCase();
        final model = (row['model'] ?? '').toString().toLowerCase();
        final year = (row['year'] ?? '').toString().toLowerCase();
        final plate = (row['plate_no'] ?? row['plateNo'] ?? '')
            .toString()
            .toLowerCase();

        return make.contains(query) ||
            model.contains(query) ||
            year.contains(query) ||
            plate.contains(query);
      }).toList();
    });
  }

  int get _totalCount => _all.length;

  int get _activeCount => _all.where((e) {
    if (e is! Map) return false;
    return _statusFromRow(e) == _StatusKind.active;
  }).length;

  int get _serviceCount => _all.where((e) {
    if (e is! Map) return false;
    return _statusFromRow(e) == _StatusKind.inService;
  }).length;

  int get _inactiveCount => _all.where((e) {
    if (e is! Map) return false;
    return _statusFromRow(e) == _StatusKind.inactive;
  }).length;

  bool _isCompact(BuildContext context) {
    return MediaQuery.of(context).size.width < 400;
  }

  @override
  Widget build(BuildContext context) {
    if (_showAddForm) {
      return _buildAddForm();
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: Theme.of(context).colorScheme.primary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
        children: [
          _header(),
          const SizedBox(height: 14),
          _actionRow(),
          const SizedBox(height: 14),
          _summaryCards(),
          const SizedBox(height: 14),
          _tabs(),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 50),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_filtered.isEmpty)
            _emptyState()
          else
            ..._filtered.map((e) => _vehicleCard(e as Map)).toList(),
          if (!_loading)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Showing 1 to ${_filtered.length} of $_totalCount vehicles',
                      style: const TextStyle(
                        color: Color(0xFF667085),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const Text(
                    'View All',
                    style: TextStyle(
                      color: Color(kGoldColor),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAddForm() {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            children: [
              _addFormHeader(),
              const SizedBox(height: 14),
              _sectionCard(
                title: 'Vehicle Information',
                child: Column(
                  children: [
                    _fieldPair(
                      leftLabel: 'Vehicle No',
                      leftRequired: true,
                      left: _fieldBox(
                        controller: _vehicleNoCtrl,
                        icon: Icons.confirmation_number_outlined,
                        hintText: 'CAR-001',
                      ),
                      rightLabel: 'Plate No',
                      rightRequired: true,
                      right: _fieldBox(
                        controller: _plateNoCtrl,
                        icon: Icons.pin_outlined,
                        hintText: 'T 123 ABC',
                      ),
                    ),
                    const SizedBox(height: 12),
                    _fieldPair(
                      leftLabel: 'Make',
                      leftRequired: true,
                      left: _fieldBox(
                        controller: _makeCtrl,
                        icon: Icons.directions_car_filled_outlined,
                        hintText: 'Toyota',
                      ),
                      rightLabel: 'Model',
                      rightRequired: true,
                      right: _fieldBox(
                        controller: _modelCtrl,
                        icon: Icons.directions_car_outlined,
                        hintText: 'Land Cruiser 200',
                      ),
                    ),
                    const SizedBox(height: 12),
                    _fieldPair(
                      leftLabel: 'Year',
                      leftRequired: true,
                      left: _fieldBox(
                        controller: _yearCtrl,
                        icon: Icons.calendar_month,
                        hintText: '2024',
                      ),
                      rightLabel: 'Chassis No',
                      rightRequired: true,
                      right: _fieldBox(
                        controller: _chassisCtrl,
                        icon: Icons.vpn_key_outlined,
                        hintText: 'JTMHX05J...',
                      ),
                    ),
                    const SizedBox(height: 12),
                    _fieldPair(
                      leftLabel: 'Seats',
                      leftRequired: true,
                      left: _fieldBox(
                        controller: _seatsCtrl,
                        icon: Icons.event_seat_outlined,
                        hintText: '7',
                      ),
                      rightLabel: 'Initial Mileage',
                      rightRequired: true,
                      right: _fieldBox(
                        controller: _initialMileageCtrl,
                        icon: Icons.speed_outlined,
                        hintText: '45200',
                      ),
                    ),
                    const SizedBox(height: 12),
                    _singleField(
                      label: 'Specs',
                      required: false,
                      child: _specsBox(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _sectionCard(
                title: 'Status & Photo',
                child: Column(
                  children: [
                    _singleField(
                      label: 'Status',
                      required: true,
                      child: _statusDropdown(),
                    ),
                    const SizedBox(height: 12),
                    _singleField(
                      label: 'Photo Attachment',
                      required: false,
                      child: _photoAttachmentField(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _formBottomBar(),
      ],
    );
  }

  Widget _addFormHeader() {
    return Row(
      children: [
        IconButton(
          onPressed: () => setState(() => _showAddForm = false),
          icon: const Icon(Icons.arrow_back_rounded),
          color: const Color(0xFF101828),
        ),
        const SizedBox(width: 4),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add New Vehicle',
                style: TextStyle(
                  color: Color(0xFF101828),
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              SizedBox(height: 5),
              Text(
                'Create vehicle record for fleet management',
                style: TextStyle(
                  color: Color(0xFF667085),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 20,
                decoration: BoxDecoration(
                  color: const Color(kGoldColor),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF101828),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Icon(
                Icons.info_outline,
                color: Color(0xFF98A2B3),
                size: 20,
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _fieldPair({
    required String leftLabel,
    required bool leftRequired,
    required Widget left,
    required String rightLabel,
    required bool rightRequired,
    required Widget right,
  }) {
    return Row(
      children: [
        Expanded(
          child: _singleField(
            label: leftLabel,
            required: leftRequired,
            child: left,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _singleField(
            label: rightLabel,
            required: rightRequired,
            child: right,
          ),
        ),
      ],
    );
  }

  Widget _singleField({
    required String label,
    required bool required,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            text: label,
            style: const TextStyle(
              color: Color(0xFF344054),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            children: [
              if (required)
                const TextSpan(
                  text: ' *',
                  style: TextStyle(color: Color(0xFFE5484D)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  Widget _fieldBox({
    required TextEditingController controller,
    required IconData icon,
    String? hintText,
  }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        isDense: true,
        hintText: hintText,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 16,
        ),
        prefixIcon: Icon(icon, color: const Color(0xFF667085), size: 20),
        filled: true,
        fillColor: Colors.white,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD0D5DD)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(kGoldColor), width: 1.5),
        ),
      ),
    );
  }

  Widget _specsBox() {
    return TextField(
      controller: _specsCtrl,
      maxLines: 3,
      decoration: InputDecoration(
        isDense: true,
        hintText: 'e.g. 4x4, diesel, automatic, pop-up roof',
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        filled: true,
        fillColor: Colors.white,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD0D5DD)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(kGoldColor), width: 1.5),
        ),
      ),
    );
  }

  Widget _statusDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD0D5DD)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _formStatus,
          isExpanded: true,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Color(0xFF667085),
          ),
          items: const [
            DropdownMenuItem(value: 'Available', child: Text('Available')),
            DropdownMenuItem(value: 'On Lease', child: Text('On Lease')),
            DropdownMenuItem(value: 'Maintenance', child: Text('Maintenance')),
            DropdownMenuItem(value: 'Retired', child: Text('Retired')),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() => _formStatus = value);
          },
        ),
      ),
    );
  }

  Widget _formBottomBar() {
    final compact = _isCompact(context);

    return Container(
      padding: EdgeInsets.fromLTRB(
        compact ? 10 : 14,
        10,
        compact ? 10 : 14,
        10,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE4E7EC))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: compact ? 96 : 130,
            height: 52,
            child: OutlinedButton(
              onPressed: () => setState(() => _showAddForm = false),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFD0D5DD)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: Color(0xFF344054),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: const Color(kGoldColor),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Save & Continue',
                        style: TextStyle(
                          fontSize: compact ? 13 : 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward_rounded),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1800,
      );
      if (picked == null || !mounted) return;
      setState(() => _selectedPhoto = picked);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not pick image. Please try again.'),
        ),
      );
    }
  }

  Widget _photoAttachmentField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _photoPickButton(
                icon: Icons.photo_library_outlined,
                label: 'Gallery',
                onTap: () => _pickPhoto(ImageSource.gallery),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _photoPickButton(
                icon: Icons.photo_camera_outlined,
                label: 'Camera',
                onTap: () => _pickPhoto(ImageSource.camera),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFD0D5DD)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.attachment_rounded,
                color: Color(0xFF667085),
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _selectedPhoto?.name ?? 'No photo selected',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _selectedPhoto == null
                        ? const Color(0xFF98A2B3)
                        : const Color(0xFF344054),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (_selectedPhoto != null)
                InkWell(
                  onTap: () => setState(() => _selectedPhoto = null),
                  borderRadius: BorderRadius.circular(20),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: Color(0xFF667085),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (_selectedPhoto != null) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 120,
              height: 90,
              child: Image.file(File(_selectedPhoto!.path), fit: BoxFit.cover),
            ),
          ),
        ],
      ],
    );
  }

  Widget _photoPickButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0xFFD0D5DD)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          foregroundColor: const Color(0xFF344054),
        ),
        icon: Icon(icon, size: 18),
        label: Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        Builder(
          builder: (ctx) => IconButton(
            onPressed: () => Scaffold.of(ctx).openDrawer(),
            icon: const Icon(Icons.menu_rounded, size: 30),
            color: const Color(0xFF1F2A44),
          ),
        ),
        const SizedBox(width: 2),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Vehicles',
                style: TextStyle(
                  color: Color(0xFF101828),
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                  height: 1,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Manage your fleet vehicles',
                style: TextStyle(
                  color: Color(0xFF667085),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () {},
          icon: const Icon(Icons.search_rounded, size: 30),
          color: const Color(0xFF1F2A44),
        ),
      ],
    );
  }

  Widget _actionRow() {
    final hasFilter = _tab != _VehicleTab.all;
    final compact = _isCompact(context);

    return Column(
      children: [
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE4E7EC)),
          ),
          child: Row(
            children: [
              const Icon(Icons.search_rounded, color: Color(0xFF98A2B3)),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    hintText: 'Search vehicles...',
                    hintStyle: TextStyle(
                      color: Color(0xFF98A2B3),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE4E7EC)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.filter_alt_outlined,
                      color: Color(0xFF667085),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Filter',
                      style: TextStyle(
                        color: Color(0xFF344054),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: hasFilter
                            ? const Color(kGoldColor)
                            : const Color(0xFFE4E7EC),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          hasFilter ? '1' : '0',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () => setState(() => _showAddForm = true),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(compact ? 'Add' : 'Add Vehicle'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(kGoldColor),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _summaryCards() {
    final cards = [
      _statCard(
        icon: Icons.directions_car_outlined,
        iconBg: const Color(0xFFFFF6E8),
        iconColor: const Color(0xFFBD7D00),
        count: _totalCount,
        title: 'Total Vehicles',
      ),
      _statCard(
        icon: Icons.check_circle_outline_rounded,
        iconBg: const Color(0xFFE8F7F0),
        iconColor: const Color(0xFF0F9D67),
        count: _activeCount,
        title: 'Active',
      ),
      _statCard(
        icon: Icons.handyman_outlined,
        iconBg: const Color(0xFFFFF5E9),
        iconColor: const Color(0xFFD9822F),
        count: _serviceCount,
        title: 'In Service',
      ),
      _statCard(
        icon: Icons.cancel_outlined,
        iconBg: const Color(0xFFFFEFEE),
        iconColor: const Color(0xFFE5484D),
        count: _inactiveCount,
        title: 'Inactive',
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: cards
              .map(
                (card) => Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: SizedBox(width: 126, child: card),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Widget _statCard({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required int count,
    required String title,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: 8),
              Text(
                '$count',
                style: const TextStyle(
                  color: Color(0xFF101828),
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF667085),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabs() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _tabPill(_VehicleTab.all, 'All Vehicles ($_totalCount)'),
          const SizedBox(width: 10),
          _tabPill(_VehicleTab.active, 'Active ($_activeCount)'),
          const SizedBox(width: 10),
          _tabPill(_VehicleTab.inService, 'In Service ($_serviceCount)'),
          const SizedBox(width: 10),
          _tabPill(_VehicleTab.inactive, 'Inactive ($_inactiveCount)'),
        ],
      ),
    );
  }

  Widget _tabPill(_VehicleTab value, String label) {
    final selected = _tab == value;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        setState(() => _tab = value);
        _applyFilters();
      },
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFF8EA) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? const Color(0xFFE7C987) : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: selected ? const Color(kGoldColor) : const Color(0xFF344054),
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _vehicleCard(Map row) {
    final make = (row['make'] ?? '').toString();
    final model = (row['model'] ?? '').toString();
    final year = (row['year'] ?? '').toString();
    final plate = (row['plate_no'] ?? row['plateNo'] ?? '-').toString();

    final String displayName = [
      make,
      model,
      year,
    ].where((e) => e.trim().isNotEmpty).join(' ').trim();

    final mileageRaw =
        row['mileage'] ?? row['odometer'] ?? row['distance'] ?? 0;
    final mileage = _kmString(mileageRaw);

    final fuel = (row['fuel_type'] ?? row['fuel'] ?? 'Fuel').toString();
    final transmission = (row['transmission'] ?? row['gearbox'] ?? 'Automatic')
        .toString();
    final type = (row['type'] ?? row['vehicle_type'] ?? 'SUV').toString();

    final status = _statusFromRow(row);
    final statusUi = _statusUi(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: Row(
        children: [
          Container(
            width: 120,
            height: 74,
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE4E7EC)),
            ),
            child: const Icon(
              Icons.directions_car_filled_rounded,
              size: 36,
              color: Color(0xFF98A2B3),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName.isEmpty ? 'Vehicle' : displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF101828),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F4F7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    plate,
                    style: const TextStyle(
                      color: Color(0xFF344054),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    _specItem(Icons.directions_car_outlined, type),
                    _specItem(Icons.local_gas_station_outlined, fuel),
                    _specItem(Icons.settings_outlined, transmission),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusUi.bg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: statusUi.dot,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      statusUi.label,
                      style: TextStyle(
                        color: statusUi.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                mileage,
                style: const TextStyle(
                  color: Color(0xFF1D2939),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              const Icon(
                Icons.more_vert_rounded,
                color: Color(0xFF667085),
                size: 22,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _specItem(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF667085)),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            color: Color(0xFF475467),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _emptyState() {
    return Container(
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.directions_car_outlined,
            size: 38,
            color: Color(0xFF98A2B3),
          ),
          SizedBox(height: 10),
          Text(
            'No vehicles found',
            style: TextStyle(
              color: Color(0xFF475467),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _kmString(dynamic raw) {
    final value = double.tryParse(raw.toString()) ?? 0;
    final formatted = value
        .toStringAsFixed(0)
        .replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},',
        );
    return '$formatted km';
  }

  _StatusKind _statusFromRow(Map row) {
    final s = (row['status'] ?? '').toString().toLowerCase().trim();
    if (s.contains('inactive') || s.contains('retired')) {
      return _StatusKind.inactive;
    }
    if (s.contains('service') ||
        s.contains('maintenance') ||
        s.contains('lease')) {
      return _StatusKind.inService;
    }
    return _StatusKind.active;
  }

  _StatusUi _statusUi(_StatusKind kind) {
    return switch (kind) {
      _StatusKind.active => const _StatusUi(
        label: 'Active',
        bg: Color(0xFFE9F8F0),
        text: Color(0xFF0F9D67),
        dot: Color(0xFF0F9D67),
      ),
      _StatusKind.inService => const _StatusUi(
        label: 'In Service',
        bg: Color(0xFFEFF6FF),
        text: Color(0xFF1570EF),
        dot: Color(0xFF1570EF),
      ),
      _StatusKind.inactive => const _StatusUi(
        label: 'Inactive',
        bg: Color(0xFFFFEFEE),
        text: Color(0xFFE5484D),
        dot: Color(0xFFE5484D),
      ),
    };
  }
}

class _StatusUi {
  const _StatusUi({
    required this.label,
    required this.bg,
    required this.text,
    required this.dot,
  });

  final String label;
  final Color bg;
  final Color text;
  final Color dot;
}
