import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../models/paged_result.dart';
import '../services/api_service.dart';
import '../widgets/pagination_footer.dart';
import '../widgets/resource_form_dialog.dart';
import '../widgets/status_badge.dart';

class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({super.key, this.proforma = false});

  final bool proforma;

  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  final _searchCtrl = TextEditingController();
  List<dynamic> _items = <dynamic>[];
  bool _loading = true;
  bool _loadingMore = false;
  bool _fromCache = false;
  int _page = 1;
  int _lastPage = 1;

  String get _resourcePath =>
      widget.proforma ? '/proforma-invoices' : '/invoices';
  String get _cacheKey => widget.proforma ? 'proforma_invoices' : 'invoices';
  String get _resourceLabelPlural =>
      widget.proforma ? 'proforma invoices' : 'invoices';
  String get _numberPrefix => widget.proforma ? 'PFI' : 'INV';

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
    return _items.where((inv) {
      final num = (inv['invoice_no'] ?? inv['invoiceNo'] ?? '')
          .toString()
          .toLowerCase();
      final client = (inv['client'] ?? inv['client_name'] ?? '')
          .toString()
          .toLowerCase();
      final status = (inv['status'] ?? '').toString().toLowerCase();
      return num.contains(q) || client.contains(q) || status.contains(q);
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
        _resourcePath,
        page: nextPage,
        perPage: 20,
        cacheKey: _cacheKey,
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load $_resourceLabelPlural: $e')),
      );
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
        title: initial == null
            ? 'Add ${widget.proforma ? 'Proforma Invoice' : 'Invoice'}'
            : 'Edit ${widget.proforma ? 'Proforma Invoice' : 'Invoice'}',
        initialValues: initial,
        fields: const [
          ResourceFormField(keyName: 'invoiceNo', label: 'Invoice Number'),
          ResourceFormField(keyName: 'quickbooksRef', label: 'QuickBooks Ref'),
          ResourceFormField(
            keyName: 'client',
            label: 'Client Name',
            requiredField: true,
          ),
          ResourceFormField(
            keyName: 'issueDate',
            label: 'Issue Date',
            type: ResourceFieldType.date,
          ),
          ResourceFormField(
            keyName: 'dueDate',
            label: 'Due Date',
            type: ResourceFieldType.date,
          ),
          ResourceFormField(
            keyName: 'total',
            label: 'Total Amount',
            type: ResourceFieldType.number,
          ),
          ResourceFormField(keyName: 'notes', label: 'Notes'),
        ],
      ),
    );

    if (payload == null) return;

    try {
      if (initial == null) {
        await ApiService.post(_resourcePath, payload);
      } else {
        await ApiService.put('$_resourcePath/${initial['id']}', payload);
      }
      await _load(reset: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }

  Future<void> _recordPayment(Map<String, dynamic> inv) async {
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => ResourceFormDialog(
        title: 'Record Payment',
        initialValues: {
          'date': DateTime.now().toIso8601String().split('T').first,
          'method': 'Bank Transfer',
        },
        fields: const [
          ResourceFormField(
            keyName: 'date',
            label: 'Payment Date',
            type: ResourceFieldType.date,
          ),
          ResourceFormField(
            keyName: 'amount',
            label: 'Amount',
            type: ResourceFieldType.number,
            requiredField: true,
          ),
          ResourceFormField(
            keyName: 'method',
            label: 'Method',
            type: ResourceFieldType.select,
            options: [
              'Cash',
              'Bank Transfer',
              'Card',
              'Mobile Money',
              'Cheque',
            ],
          ),
          ResourceFormField(keyName: 'reference', label: 'Reference'),
        ],
      ),
    );

    if (payload == null) return;

    try {
      await ApiService.post('/invoices/${inv['id']}/payments', payload);
      await _load(reset: true);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Payment recorded.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Payment failed: $e')));
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(kDarkCard),
        title: const Text(
          'Delete invoice',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to delete this invoice?',
          style: TextStyle(color: Color(0xFF94A3B8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await ApiService.delete('$_resourcePath/${item['id']}');
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
      floatingActionButton: widget.proforma
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openForm(),
              backgroundColor: Theme.of(context).colorScheme.primary,
              icon: Icon(
                Icons.add,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
              label: Text(
                'Add Invoice',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: TextField(
              controller: _searchCtrl,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              decoration: const InputDecoration(
                hintText: 'Search by number, client, or status...',
                prefixIcon: Icon(Icons.search, color: Color(0xFF64748B)),
              ),
            ),
          ),
          if (_fromCache)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Offline mode: showing cached results',
                  style: TextStyle(color: Color(kGoldColor), fontSize: 12),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(kGoldColor)),
                  )
                : RefreshIndicator(
                    onRefresh: () => _load(reset: true),
                    color: const Color(kGoldColor),
                    child: _filtered.isEmpty
                        ? ListView(
                            children: [
                              SizedBox(height: 100),
                              Center(
                                child: Text(
                                  'No ${widget.proforma ? 'proforma invoices' : 'invoices'} found',
                                  style: TextStyle(color: Color(0xFF64748B)),
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

  Widget _card(Map<String, dynamic> inv) {
    final theme = Theme.of(context);
    final num = inv['invoice_no'] ?? inv['invoiceNo'] ?? '-';
    final client = inv['client'] ?? inv['client_name'] ?? '-';
    final status = inv['status'] ?? 'Open';
    final total = inv['total'] ?? inv['total_amount'] ?? '0';

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
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$_numberPrefix-$num',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      client.toString(),
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              StatusBadge(status: status.toString()),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFF5DB), Color(0xFFFFFFFF)],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: theme.colorScheme.outline, width: 0.6),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.attach_money_outlined,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  'USD $total',
                  style: const TextStyle(
                    color: Color(kGoldColor),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.end,
            runAlignment: WrapAlignment.end,
            spacing: 6,
            runSpacing: 6,
            children: [
              if (!widget.proforma)
                ElevatedButton.icon(
                  onPressed: () => _recordPayment(inv),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDDF6E9),
                    foregroundColor: const Color(0xFF0F7B45),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: const VisualDensity(
                      horizontal: -1,
                      vertical: -1,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.payment_outlined, size: 15),
                  label: const Text('Payment'),
                ),
              ElevatedButton.icon(
                onPressed: () => _openForm(initial: inv),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.secondaryContainer,
                  foregroundColor: theme.colorScheme.onSecondaryContainer,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: const VisualDensity(
                    horizontal: -1,
                    vertical: -1,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.edit_outlined, size: 15),
                label: const Text('Edit'),
              ),
              ElevatedButton.icon(
                onPressed: () => _delete(inv),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.errorContainer,
                  foregroundColor: theme.colorScheme.onErrorContainer,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: const VisualDensity(
                    horizontal: -1,
                    vertical: -1,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.delete_outline, size: 15),
                label: const Text('Delete'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
