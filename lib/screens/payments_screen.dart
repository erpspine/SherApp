import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../models/paged_result.dart';
import '../services/api_service.dart';
import '../widgets/pagination_footer.dart';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
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
    return _items.where((p) {
      final inv =
          (p['invoice']?['invoice_no'] ??
                  p['invoice']?['invoiceNo'] ??
                  p['invoiceNo'] ??
                  '')
              .toString()
              .toLowerCase();
      final client = (p['invoice']?['client'] ?? p['client'] ?? '')
          .toString()
          .toLowerCase();
      final method = (p['method'] ?? p['payment_method'] ?? '')
          .toString()
          .toLowerCase();
      final ref = (p['reference'] ?? p['transaction_ref'] ?? '')
          .toString()
          .toLowerCase();
      return inv.contains(q) ||
          client.contains(q) ||
          method.contains(q) ||
          ref.contains(q);
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
        '/invoice-payments',
        page: nextPage,
        perPage: 20,
        cacheKey: 'invoice_payments',
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
      ).showSnackBar(SnackBar(content: Text('Failed to load payments: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: TextField(
              controller: _searchCtrl,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              decoration: InputDecoration(
                hintText: 'Search payments...',
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Payments are recorded via the Invoices screen.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: _loading
                ? Center(
                    child: CircularProgressIndicator(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () => _load(reset: true),
                    color: Theme.of(context).colorScheme.primary,
                    child: _filtered.isEmpty
                        ? ListView(
                            children: [
                              const SizedBox(height: 100),
                              Center(
                                child: Text(
                                  'No payments found',
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

  Widget _card(Map<String, dynamic> p) {
    final theme = Theme.of(context);
    final invNo =
        p['invoice']?['invoice_no'] ??
        p['invoice']?['invoiceNo'] ??
        p['invoiceNo'] ??
        '-';
    final client =
        p['invoice']?['client'] ??
        p['invoice']?['client_name'] ??
        p['client'] ??
        '-';
    final method = p['method'] ?? p['payment_method'] ?? '-';
    final reference = p['reference'] ?? p['transaction_ref'] ?? '';
    final amount = p['amount'] ?? '0';
    final date = p['date'] ?? p['paid_at'] ?? p['created_at'] ?? '';

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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      invNo.toString(),
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
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFEAF7F4), Color(0xFFFFFFFF)],
                  ),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: theme.colorScheme.outline,
                    width: 0.6,
                  ),
                ),
                child: Text(
                  method.toString(),
                  style: TextStyle(
                    color: theme.colorScheme.secondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
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
                  'USD $amount',
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
            spacing: 8,
            runSpacing: 8,
            children: [
              if (reference.toString().isNotEmpty)
                _infoChip(Icons.tag_outlined, 'Ref: $reference'),
              if (date.toString().isNotEmpty)
                _infoChip(
                  Icons.calendar_today_outlined,
                  date.toString().split('T').first,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String value) {
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
