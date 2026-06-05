import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../models/paged_result.dart';
import '../services/api_service.dart';
import '../widgets/pagination_footer.dart';
import '../widgets/resource_form_dialog.dart';

class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  final _searchCtrl = TextEditingController();
  List<dynamic> _items = <dynamic>[];
  bool _loading = true;
  bool _loadingMore = false;
  bool _fromCache = false;
  int _page = 1;
  int _lastPage = 1;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() {}));
    _load(reset: true);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<dynamic> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _items;
    return _items.where((c) {
      final name = (c['name'] ?? '').toString().toLowerCase();
      final company = (c['company'] ?? '').toString().toLowerCase();
      final email = (c['email'] ?? '').toString().toLowerCase();
      final phone = (c['phone'] ?? '').toString().toLowerCase();
      return name.contains(q) ||
          company.contains(q) ||
          email.contains(q) ||
          phone.contains(q);
    }).toList();
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
      final nextPage = reset ? 1 : _page + 1;
      final PagedResult result = await ApiService.fetchPaged(
        '/clients',
        page: nextPage,
        perPage: 20,
        cacheKey: 'clients',
      );

      if (!mounted) return;
      setState(() {
        _page = result.currentPage;
        _lastPage = result.lastPage;
        _fromCache = result.fromCache;
        _items = reset ? result.items : <dynamic>[..._items, ...result.items];
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load clients: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _openForm({Map<String, dynamic>? initial}) async {
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => ResourceFormDialog(
        title: initial == null ? 'Add Client' : 'Edit Client',
        initialValues: initial,
        fields: const [
          ResourceFormField(
            keyName: 'name',
            label: 'Name',
            requiredField: true,
          ),
          ResourceFormField(keyName: 'company', label: 'Company'),
          ResourceFormField(keyName: 'email', label: 'Email'),
          ResourceFormField(keyName: 'phone', label: 'Phone'),
          ResourceFormField(keyName: 'address', label: 'Address', maxLines: 2),
        ],
      ),
    );

    if (payload == null) return;

    try {
      if (initial == null) {
        await ApiService.post('/clients', payload);
      } else {
        await ApiService.put('/clients/${initial['id']}', payload);
      }
      await _load(reset: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(kDarkCard),
        title: const Text(
          'Delete client',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to delete this client?',
          style: TextStyle(color: Color(0xFF94A3B8)),
        ),
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

    try {
      await ApiService.delete('/clients/${item['id']}');
      await _load(reset: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        backgroundColor: Theme.of(context).colorScheme.primary,
        icon: Icon(Icons.add, color: Theme.of(context).colorScheme.onPrimary),
        label: Text(
          'Add Client',
          style: TextStyle(color: Theme.of(context).colorScheme.onPrimary),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: TextField(
              controller: _searchCtrl,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              decoration: InputDecoration(
                hintText: 'Search clients...',
                prefixIcon: Icon(
                  Icons.search,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          if (_fromCache)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Offline mode: showing cached results',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: () => _load(reset: true),

                    child: _filtered.isEmpty
                        ? ListView(
                            children: [
                              const SizedBox(height: 100),
                              Center(
                                child: Text(
                                  'No clients found',
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _filtered.length + 1,
                            itemBuilder: (_, i) {
                              if (i == _filtered.length) {
                                return PaginationFooter(
                                  currentPage: _page,
                                  lastPage: _lastPage,
                                  loadingMore: _loadingMore,
                                  onLoadMore: () => _load(reset: false),
                                );
                              }
                              return _card(
                                _filtered[i] as Map<String, dynamic>,
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _card(Map<String, dynamic> c) {
    final theme = Theme.of(context);
    final name = c['name']?.toString() ?? '-';
    final company = c['company']?.toString() ?? '';
    final email = c['email']?.toString() ?? '';
    final phone = c['phone']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outline, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFEAF7F4), Color(0xFFFFFFFF)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: theme.colorScheme.outline,
                    width: 0.6,
                  ),
                ),
                child: Icon(
                  Icons.people_outline,
                  color: theme.colorScheme.secondary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    if (company.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        company,
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (email.isNotEmpty) _contactChip(Icons.email_outlined, email),
              if (phone.isNotEmpty) _contactChip(Icons.phone_outlined, phone),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ElevatedButton.icon(
                onPressed: () => _openForm(initial: c),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.secondaryContainer,
                  foregroundColor: theme.colorScheme.onSecondaryContainer,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Edit'),
              ),
              const SizedBox(width: 6),
              ElevatedButton.icon(
                onPressed: () => _delete(c),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.errorContainer,
                  foregroundColor: theme.colorScheme.onErrorContainer,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Delete'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _contactChip(IconData icon, String value) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF8FAFC), Color(0xFFFFFFFF)],
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outline, width: 0.6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            value,
            style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
