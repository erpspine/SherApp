import 'package:flutter/material.dart';
import '../models/paged_result.dart';
import '../services/api_service.dart';
import '../widgets/pagination_footer.dart';
import '../widgets/resource_form_dialog.dart';

class LeadsScreen extends StatefulWidget {
  const LeadsScreen({super.key});

  @override
  State<LeadsScreen> createState() => _LeadsScreenState();
}

class _LeadsScreenState extends State<LeadsScreen> {
  final _searchCtrl = TextEditingController();
  List<dynamic> _items = <dynamic>[];
  bool _loading = true;
  bool _loadingMore = false;
  bool _fromCache = false;
  int _page = 1;
  int _lastPage = 1;
  String _statusFilter = 'All';
  List<String> _clientCompanyOptions = <String>[];
  Map<String, Map<String, String>> _clientPrefillByCompany =
      <String, Map<String, String>>{};

  static const _statuses = [
    'All',
    'Pending',
    'Confirmed',
    'Cancelled',
    'Completed',
    'Quotation Sent',
    'PI Sent',
  ];

  static const _countries = [
    'Tanzania',
    'Kenya',
    'Uganda',
    'Rwanda',
    'Zambia',
    'South Africa',
    'UAE',
    'UK',
    'USA',
    'Germany',
    'France',
  ];

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() {}));
    _load(reset: true);
    _loadClientCompanies();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _sv(dynamic item, String snake, String camel) {
    if (item is! Map) return '';
    return (item[snake] ?? item[camel] ?? '')?.toString() ?? '';
  }

  int _iv(dynamic item, String snake, String camel) {
    if (item is! Map) return 0;
    final v = item[snake] ?? item[camel];
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  String _formatDate(String value) {
    if (value.trim().isEmpty) return '-';
    final d = DateTime.tryParse(value);
    if (d == null) return value;
    const m = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${d.day.toString().padLeft(2, '0')} ${m[d.month - 1]}, ${d.year}';
  }

  String _formatDateTime(String value) {
    if (value.trim().isEmpty) return '-';
    final d = DateTime.tryParse(value);
    if (d == null) return value;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  List<dynamic> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    return _items.where((l) {
      final matchSearch =
          q.isEmpty ||
          _sv(l, 'client_company', 'clientCompany').toLowerCase().contains(q) ||
          _sv(l, 'booking_ref', 'bookingRef').toLowerCase().contains(q) ||
          _sv(l, 'agent_contact', 'agentContact').toLowerCase().contains(q) ||
          _sv(l, 'route_parks', 'routeParks').toLowerCase().contains(q) ||
          _sv(l, 'client_country', 'clientCountry').toLowerCase().contains(q);
      final status = _sv(l, 'booking_status', 'bookingStatus');
      return matchSearch && (_statusFilter == 'All' || status == _statusFilter);
    }).toList();
  }

  int _count(String status) => _items
      .where((l) => _sv(l, 'booking_status', 'bookingStatus') == status)
      .length;

  Future<void> _loadClientCompanies() async {
    try {
      final response = await ApiService.get('/clients');
      final raw = response['data'] ?? response['clients'] ?? response;
      if (raw is! List) return;

      final byCompany = <String, Map<String, String>>{};
      for (final c in raw.whereType<Map>()) {
        final company = (c['company'] ?? c['company_name'] ?? c['name'] ?? '')
            .toString()
            .trim();
        if (company.isEmpty) continue;

        final country = (c['country'] ?? c['client_country'] ?? '')
            .toString()
            .trim();
        final contact =
            (c['name'] ?? c['contact_person'] ?? c['client_name'] ?? '')
                .toString()
                .trim();
        final phone = (c['phone'] ?? c['phone_number'] ?? '').toString().trim();
        final email = (c['email'] ?? '').toString().trim();

        byCompany[company.toLowerCase()] = {
          'company': company,
          'country': country,
          'contact': contact,
          'phone': phone,
          'email': email,
        };
      }

      final values =
          byCompany.values
              .map((m) => m['company'] ?? '')
              .where((s) => s.isNotEmpty)
              .toSet()
              .toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      if (!mounted) return;
      setState(() {
        _clientCompanyOptions = values;
        _clientPrefillByCompany = byCompany;
      });
    } catch (_) {
      // Suggestions are optional; manual typing remains available.
    }
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _page = 1;
      });
    } else {
      if (_page >= _lastPage) return;
      setState(() => _loadingMore = true);
    }
    try {
      final r = await ApiService.fetchPaged(
        '/leads',
        page: reset ? 1 : _page + 1,
        perPage: 100,
        cacheKey: 'leads',
      );
      if (!mounted) return;
      setState(() {
        _page = r.currentPage;
        _lastPage = r.lastPage;
        _fromCache = r.fromCache;
        _items = reset ? r.items : <dynamic>[..._items, ...r.items];
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load leads: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  String _generateBookingRef() {
    final year = DateTime.now().year;
    return 'BK-$year-${1000 + (DateTime.now().millisecondsSinceEpoch % 9000)}';
  }

  Map<String, dynamic> _formValues(Map<String, dynamic> item) => {
    'id': item['id'],
    'booking_ref': _sv(item, 'booking_ref', 'bookingRef'),
    'client_company': _sv(item, 'client_company', 'clientCompany'),
    'client_country': _sv(item, 'client_country', 'clientCountry'),
    'agent_contact': _sv(item, 'agent_contact', 'agentContact'),
    'agent_phone': _sv(item, 'agent_phone', 'agentPhone'),
    'agent_email': _sv(item, 'agent_email', 'agentEmail'),
    'start_date': _sv(item, 'start_date', 'startDate'),
    'end_date': _sv(item, 'end_date', 'endDate'),
    'route_parks': _sv(item, 'route_parks', 'routeParks'),
    'pax_adults': _sv(item, 'pax_adults', 'paxAdults'),
    'pax_children': _sv(item, 'pax_children', 'paxChildren'),
    'no_of_vehicles': _sv(item, 'no_of_vehicles', 'noOfVehicles'),
    'special_requirements': _sv(
      item,
      'special_requirements',
      'specialRequirements',
    ),
    'booking_status': _sv(item, 'booking_status', 'bookingStatus'),
  };

  Future<void> _openEdit(Map<String, dynamic> item) async {
    _showLoading();
    try {
      final res = await ApiService.get('/leads/${item['id']}');
      final payload = res['data'] ?? res['lead'] ?? res;
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      await _openForm(
        initial: _formValues(Map<String, dynamic>.from(payload as Map)),
      );
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).maybePop();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load lead: $e')));
    }
  }

  Future<void> _openForm({Map<String, dynamic>? initial}) async {
    if (_clientCompanyOptions.isEmpty) {
      await _loadClientCompanies();
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => ResourceFormDialog(
        title: initial == null ? 'New Lead' : 'Edit Lead',
        initialValues: initial,
        onAutocompleteSelected: (fieldKey, selectedValue, setValue) {
          if (fieldKey != 'client_company') return;
          final client = _clientPrefillByCompany[selectedValue.toLowerCase()];
          if (client == null) return;

          final country = client['country'] ?? '';
          final contact = client['contact'] ?? '';
          final phone = client['phone'] ?? '';
          final email = client['email'] ?? '';

          if (country.isNotEmpty) setValue('client_country', country);
          if (contact.isNotEmpty) setValue('agent_contact', contact);
          if (phone.isNotEmpty) setValue('agent_phone', phone);
          if (email.isNotEmpty) setValue('agent_email', email);
        },
        fields: [
          ResourceFormField(
            keyName: 'client_company',
            label: 'Client Company',
            requiredField: true,
            options: _clientCompanyOptions,
          ),
          ResourceFormField(
            keyName: 'client_country',
            label: 'Client Country',
            type: ResourceFieldType.select,
            options: _countries,
          ),
          const ResourceFormField(
            keyName: 'agent_contact',
            label: 'Agent Contact',
            requiredField: true,
          ),
          const ResourceFormField(keyName: 'agent_phone', label: 'Agent Phone'),
          const ResourceFormField(keyName: 'agent_email', label: 'Agent Email'),
          const ResourceFormField(
            keyName: 'start_date',
            label: 'Start Date',
            type: ResourceFieldType.date,
            requiredField: true,
          ),
          const ResourceFormField(
            keyName: 'end_date',
            label: 'End Date',
            type: ResourceFieldType.date,
          ),
          const ResourceFormField(
            keyName: 'route_parks',
            label: 'Route / Parks',
            type: ResourceFieldType.textarea,
            maxLines: 3,
          ),
          const ResourceFormField(
            keyName: 'pax_adults',
            label: 'Pax Adults',
            type: ResourceFieldType.number,
          ),
          const ResourceFormField(
            keyName: 'pax_children',
            label: 'Pax Children',
            type: ResourceFieldType.number,
          ),
          const ResourceFormField(
            keyName: 'no_of_vehicles',
            label: 'No. of Vehicles',
            type: ResourceFieldType.number,
          ),
          const ResourceFormField(
            keyName: 'special_requirements',
            label: 'Special Requirements',
            type: ResourceFieldType.textarea,
            maxLines: 3,
          ),
          const ResourceFormField(
            keyName: 'booking_status',
            label: 'Booking Status',
            type: ResourceFieldType.select,
            options: [
              'Pending',
              'Confirmed',
              'Cancelled',
              'Completed',
              'Quotation Sent',
              'PI Sent',
            ],
          ),
        ],
      ),
    );
    if (result == null) return;

    final body = {
      'bookingRef':
          initial?['booking_ref'] ??
          initial?['bookingRef'] ??
          _generateBookingRef(),
      'clientCompany': result['client_company'] ?? '',
      'agentContact': result['agent_contact'] ?? '',
      'agentEmail': result['agent_email'] ?? '',
      'agentPhone': result['agent_phone'] ?? '',
      'clientCountry': result['client_country'] ?? '',
      'startDate': result['start_date'] ?? '',
      'endDate': result['end_date'] ?? '',
      'routeParks': result['route_parks'] ?? '',
      'paxAdults': int.tryParse(result['pax_adults']?.toString() ?? '0') ?? 0,
      'paxChildren':
          int.tryParse(result['pax_children']?.toString() ?? '0') ?? 0,
      'noOfVehicles':
          int.tryParse(result['no_of_vehicles']?.toString() ?? '1') ?? 1,
      'specialRequirements': result['special_requirements'],
      'bookingStatus': result['booking_status'] ?? 'Pending',
    };

    _showLoading();
    try {
      if (initial == null) {
        await ApiService.post('/leads', body);
      } else {
        await ApiService.put('/leads/${initial['id']}', body);
      }
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (mounted) await _load(reset: true);
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save lead: $e')));
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete lead'),
        content: const Text('Are you sure you want to delete this lead?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Delete',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;

    _showLoading();
    try {
      await ApiService.delete('/leads/${item['id']}');
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (mounted) await _load(reset: true);
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).maybePop();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  void _showLoading() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
  }

  void _showCardActions(Map<String, dynamic> item) {
    final company = _sv(item, 'client_company', 'clientCompany');
    final ref = _sv(item, 'booking_ref', 'bookingRef');
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E8EE),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                company.isEmpty ? ref : company,
                style: const TextStyle(
                  color: Color(0xFF0F1F3D),
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (ref.isNotEmpty)
                Text(
                  ref,
                  style: const TextStyle(
                    color: Color(0xFF4F46E5),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF5E2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.edit_outlined,
                    color: Color(0xFFB88910),
                    size: 18,
                  ),
                ),
                title: const Text(
                  'Edit Lead',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                subtitle: const Text(
                  'Update lead details',
                  style: TextStyle(fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _openEdit(item);
                },
              ),
              const Divider(height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1F2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.delete_outline,
                    color: Color(0xFFE11D48),
                    size: 18,
                  ),
                ),
                title: const Text(
                  'Delete Lead',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Color(0xFFE11D48),
                  ),
                ),
                subtitle: const Text(
                  'This action cannot be undone',
                  style: TextStyle(fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _delete(item);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(),
        backgroundColor: const Color(0xFFB88910),
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        color: const Color(0xFFB88910),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _statsSection(),
                    const SizedBox(height: 14),
                    _searchRow(),
                    const SizedBox(height: 12),
                    _statusTabs(),
                    if (_fromCache) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF5E2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFFFDC82)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.wifi_off_rounded,
                              size: 13,
                              color: Color(0xFFB88910),
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Offline - showing cached results',
                              style: TextStyle(
                                color: Color(0xFFB88910),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                  ],
                ),
              ),
            ),
            if (_loading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (list.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.inbox_outlined,
                        size: 56,
                        color: Color(0xFFCBD5E1),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'No leads found',
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _statusFilter == 'All'
                            ? 'Tap + to add your first lead'
                            : 'No "$_statusFilter" leads',
                        style: const TextStyle(
                          color: Color(0xFFCBD5E1),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, i) {
                    if (i == list.length) {
                      return PaginationFooter(
                        currentPage: _page,
                        lastPage: _lastPage,
                        loadingMore: _loadingMore,
                        onLoadMore: () => _load(reset: false),
                      );
                    }
                    return _card(list[i] as Map<String, dynamic>);
                  }, childCount: list.length + 1),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _statsSection() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          SizedBox(
            width: 132,
            child: _statTile(
              label: 'Total',
              value: _items.length,
              icon: Icons.people_outline_rounded,
              iconBg: const Color(0xFFEDE9FE),
              iconColor: const Color(0xFF7C3AED),
              valueColor: const Color(0xFF0F1F3D),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 132,
            child: _statTile(
              label: 'Pending',
              value: _count('Pending'),
              icon: Icons.schedule_rounded,
              iconBg: const Color(0xFFFFF5E2),
              iconColor: const Color(0xFFB88910),
              valueColor: const Color(0xFFB88910),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 132,
            child: _statTile(
              label: 'Confirmed',
              value: _count('Confirmed'),
              icon: Icons.check_circle_outline_rounded,
              iconBg: const Color(0xFFECFDF5),
              iconColor: const Color(0xFF059669),
              valueColor: const Color(0xFF059669),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 132,
            child: _statTile(
              label: 'Completed',
              value: _count('Completed'),
              icon: Icons.task_alt_rounded,
              iconBg: const Color(0xFFEFF6FF),
              iconColor: const Color(0xFF2563EB),
              valueColor: const Color(0xFF2563EB),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 132,
            child: _statTile(
              label: 'Quotation Sent',
              value: _count('Quotation Sent'),
              icon: Icons.description_outlined,
              iconBg: const Color(0xFFF5F3FF),
              iconColor: const Color(0xFF7C3AED),
              valueColor: const Color(0xFF7C3AED),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 132,
            child: _statTile(
              label: 'PI Sent',
              value: _count('PI Sent'),
              icon: Icons.send_outlined,
              iconBg: const Color(0xFFF5F3FF),
              iconColor: const Color(0xFF6D28D9),
              valueColor: const Color(0xFF6D28D9),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 132,
            child: _statTile(
              label: 'Cancelled',
              value: _count('Cancelled'),
              icon: Icons.cancel_outlined,
              iconBg: const Color(0xFFFFF1F2),
              iconColor: const Color(0xFFE11D48),
              valueColor: const Color(0xFFE11D48),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statTile({
    required String label,
    required int value,
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required Color valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E8EE)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 14, color: iconColor),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$value',
            style: TextStyle(
              color: valueColor,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchRow() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5E8EE)),
            ),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: Color(0xFF0F1F3D), fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'Search by ref, company, agent...',
                hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: Color(0xFF94A3B8),
                  size: 20,
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 13),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E8EE)),
          ),
          child: const Row(
            children: [
              Icon(Icons.tune_rounded, size: 16, color: Color(0xFF475467)),
              SizedBox(width: 6),
              Text(
                'Filter',
                style: TextStyle(
                  color: Color(0xFF475467),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statusTabs() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: _statuses.map((s) {
          final active = _statusFilter == s;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _statusFilter = s),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: active ? const Color(0xFFB88910) : Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: active
                        ? const Color(0xFFB88910)
                        : const Color(0xFFE5E8EE),
                  ),
                ),
                child: Text(
                  s,
                  style: TextStyle(
                    color: active ? Colors.white : const Color(0xFF475467),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _card(Map<String, dynamic> l) {
    final company = _sv(l, 'client_company', 'clientCompany');
    final ref = _sv(l, 'booking_ref', 'bookingRef');
    final contact = _sv(l, 'agent_contact', 'agentContact');
    final email = _sv(l, 'agent_email', 'agentEmail');
    final country = _sv(l, 'client_country', 'clientCountry');
    final startDate = _sv(l, 'start_date', 'startDate');
    final status = _sv(l, 'booking_status', 'bookingStatus');

    return GestureDetector(
      onTap: () => _showCardActions(l),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEEF0F4)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                  color: Color(0xFFEDE9FE),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_outline_rounded,
                  color: Color(0xFF7C3AED),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ref.isEmpty ? '-' : ref,
                          style: const TextStyle(
                            color: Color(0xFF4F46E5),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        _statusBadge(status.isEmpty ? 'Pending' : status),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      company.isEmpty ? '-' : company,
                      style: const TextStyle(
                        color: Color(0xFF0F1F3D),
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                    if (contact.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        contact,
                        style: const TextStyle(
                          color: Color(0xFF667085),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(
                            Icons.email_outlined,
                            size: 13,
                            color: Color(0xFFB88910),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFB88910),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.public_rounded,
                          size: 13,
                          color: Color(0xFF94A3B8),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          country.isEmpty ? '-' : country,
                          style: const TextStyle(
                            color: Color(0xFF667085),
                            fontSize: 12,
                          ),
                        ),
                        const Spacer(),
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 12,
                          color: Color(0xFF94A3B8),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatDate(startDate),
                          style: const TextStyle(
                            color: Color(0xFF667085),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: Color(0xFFCBD5E1),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusBadge(String status) {
    Color bg, border, fg;
    switch (status.toLowerCase()) {
      case 'confirmed':
        bg = const Color(0xFFECFDF5);
        border = const Color(0xFF6EE7B7);
        fg = const Color(0xFF065F46);
        break;
      case 'completed':
        bg = const Color(0xFFEFF6FF);
        border = const Color(0xFF93C5FD);
        fg = const Color(0xFF1E40AF);
        break;
      case 'quotation sent':
        bg = const Color(0xFFFFFBEB);
        border = const Color(0xFFFDE68A);
        fg = const Color(0xFF92400E);
        break;
      case 'pi sent':
        bg = const Color(0xFFF5F3FF);
        border = const Color(0xFFC4B5FD);
        fg = const Color(0xFF4C1D95);
        break;
      case 'cancelled':
        bg = const Color(0xFFFFF1F2);
        border = const Color(0xFFFDA4AF);
        fg = const Color(0xFF9F1239);
        break;
      default:
        bg = const Color(0xFFFFFBEB);
        border = const Color(0xFFFCD34D);
        fg = const Color(0xFF92400E);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        status,
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}
