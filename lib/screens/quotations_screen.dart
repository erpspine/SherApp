import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../config/app_config.dart';
import '../models/paged_result.dart';
import '../services/api_service.dart';
import '../widgets/pagination_footer.dart';
import '../widgets/status_badge.dart';
import 'invoices_screen.dart';
import 'quotation_create_screen.dart';

class QuotationsScreen extends StatefulWidget {
  const QuotationsScreen({super.key});

  @override
  State<QuotationsScreen> createState() => _QuotationsScreenState();
}

class _QuotationsScreenState extends State<QuotationsScreen> {
  final _searchCtrl = TextEditingController();
  List<dynamic> _items = <dynamic>[];
  bool _loading = true;
  bool _loadingMore = false;
  bool _fromCache = false;
  int? _downloadingId;
  int? _markingSentId;
  int? _convertingId;
  bool _exporting = false;
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

  String _stringValue(Map<String, dynamic> item, String snake, String camel) {
    final value = item[snake] ?? item[camel] ?? '';
    return value?.toString() ?? '';
  }

  double _doubleValue(Map<String, dynamic> item, String snake, String camel) {
    final value = item[snake] ?? item[camel];
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  int _lineItemCount(Map<String, dynamic> item) {
    final lineItems = item['line_items'] ?? item['lineItems'];
    if (lineItems is List) return lineItems.length;

    final daySections = item['day_sections'] ?? item['daySections'];
    if (daySections is List) {
      var count = 0;
      for (final section in daySections) {
        if (section is Map && section['items'] is List) {
          count += (section['items'] as List).length;
        } else if (section is Map && section['line_items'] is List) {
          count += (section['line_items'] as List).length;
        }
      }
      return count;
    }

    return 0;
  }

  String _serviceSummary(Map<String, dynamic> item) {
    final summary = _stringValue(item, 'service_summary', 'serviceSummary');
    if (summary.isNotEmpty) return summary;

    final lineItems = item['line_items'] ?? item['lineItems'];
    if (lineItems is List && lineItems.isNotEmpty) {
      final first = lineItems.first;
      if (first is Map<String, dynamic>) {
        return _stringValue(first, 'description', 'description');
      }
      if (first is Map) {
        final value =
            first['description'] ??
            first['service_description'] ??
            first['serviceDescription'] ??
            '';
        return value.toString();
      }
    }

    return '';
  }

  String _formatAmount(double value) {
    final fixed = value.toStringAsFixed(
      value.truncateToDouble() == value ? 0 : 2,
    );
    return 'USD $fixed';
  }

  Future<void> _downloadPdf(Map<String, dynamic> quotation) async {
    final idValue = quotation['id'];
    final id = idValue is int ? idValue : int.tryParse(idValue.toString());
    if (id == null) return;

    setState(() => _downloadingId = id);

    try {
      final bytes = await ApiService.downloadBytes('/quotations/$id/pdf');
      final dir = await getTemporaryDirectory();
      final quoteNo = _stringValue(quotation, 'quote_no', 'quoteNo');
      final safeName = (quoteNo.isEmpty ? 'quotation-$id' : quoteNo).replaceAll(
        RegExp(r'[^A-Za-z0-9._-]'),
        '_',
      );
      final file = File('${dir.path}${Platform.pathSeparator}$safeName.pdf');
      await file.writeAsBytes(bytes, flush: true);

      final result = await OpenFilex.open(file.path, type: 'application/pdf');
      if (!mounted) return;
      if (result.type != ResultType.done) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('PDF saved to ${file.path}')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('PDF download failed: $e')));
    } finally {
      if (mounted) {
        setState(() => _downloadingId = null);
      }
    }
  }

  Future<void> _markSent(Map<String, dynamic> quotation) async {
    final idValue = quotation['id'];
    final id = idValue is int ? idValue : int.tryParse(idValue.toString());
    if (id == null) return;

    setState(() => _markingSentId = id);
    try {
      await ApiService.patch('/quotations/$id/mark-sent', <String, dynamic>{});
      await _load(reset: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quotation marked as sent.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Mark sent failed: $e')));
    } finally {
      if (mounted) {
        setState(() => _markingSentId = null);
      }
    }
  }

  Future<void> _convertToPi(
    Map<String, dynamic> quotation, {
    required bool regenerate,
  }) async {
    final idValue = quotation['id'];
    final id = idValue is int ? idValue : int.tryParse(idValue.toString());
    if (id == null) return;

    setState(() => _convertingId = id);
    try {
      final body = regenerate
          ? <String, dynamic>{}
          : <String, dynamic>{
              'allocationMode': 'later',
              'allocationRanges': [],
            };

      await ApiService.post('/quotations/$id/convert-to-pi', body);
      await _load(reset: true);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            regenerate
                ? 'PI regenerated from quotation.'
                : 'Quotation converted to PI.',
          ),
        ),
      );

      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const InvoicesScreen(proforma: true)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Convert failed: $e')));
    } finally {
      if (mounted) {
        setState(() => _convertingId = null);
      }
    }
  }

  Future<void> _exportQuotations(String type) async {
    setState(() => _exporting = true);
    try {
      final bytes = await ApiService.downloadBytes('/quotations/export/$type');
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}${Platform.pathSeparator}quotations_export_$type.${type == 'pdf' ? 'pdf' : 'xlsx'}',
      );
      await file.writeAsBytes(bytes, flush: true);
      final result = await OpenFilex.open(
        file.path,
        type: type == 'pdf'
            ? 'application/pdf'
            : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      if (!mounted) return;
      if (result.type != ResultType.done) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export saved to ${file.path}')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  List<dynamic> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _items;
    return _items.where((qt) {
      final quoteNo = (qt['quote_no'] ?? qt['quoteNo'] ?? '')
          .toString()
          .toLowerCase();
      final client = (qt['client'] ?? qt['client_name'] ?? '')
          .toString()
          .toLowerCase();
      final status = (qt['status'] ?? '').toString().toLowerCase();
      final summary = (qt['service_summary'] ?? qt['serviceSummary'] ?? '')
          .toString()
          .toLowerCase();
      return quoteNo.contains(q) ||
          client.contains(q) ||
          status.contains(q) ||
          summary.contains(q);
    }).toList();
  }

  Map<String, int> get _stats {
    int countStatus(String status) {
      return _items.where((qt) {
        if (qt is! Map) return false;
        final value = (qt['status'] ?? '').toString().trim().toLowerCase();
        return value == status.toLowerCase();
      }).length;
    }

    return <String, int>{
      'Total': _items.length,
      'Pending': countStatus('Pending'),
      'Sent': countStatus('Sent'),
      'Approved': countStatus('Approved'),
      'Converted': countStatus('Converted'),
    };
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
        '/quotations',
        page: nextPage,
        perPage: 20,
        cacheKey: 'quotations',
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
      ).showSnackBar(SnackBar(content: Text('Failed to load quotations: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(kDarkCard),
        title: const Text(
          'Delete quotation',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to delete this quotation?',
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
      await ApiService.delete('/quotations/${item['id']}');
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
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final created = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const QuotationCreateScreen()),
          );
          if (created == true) {
            await _load(reset: true);
          }
        },
        backgroundColor: const Color(kGoldColor),
        foregroundColor: Colors.white,
        child: const Text(
          '+',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: TextField(
              controller: _searchCtrl,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              decoration: const InputDecoration(
                hintText: 'Search quotations...',
                prefixIcon: Icon(Icons.search, color: Color(0xFF64748B)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _statTile(
                    label: 'Total',
                    value: _stats['Total'] ?? 0,
                    valueColor: const Color(0xFF0F172A),
                    icon: Icons.receipt_long_rounded,
                    iconColor: const Color(0xFF1D4ED8),
                    iconBg: const Color(0xFFDBEAFE),
                    gradient: const [Color(0xFFF8FAFF), Color(0xFFFFFFFF)],
                    width: 156,
                  ),
                  const SizedBox(width: 8),
                  _statTile(
                    label: 'Pending',
                    value: _stats['Pending'] ?? 0,
                    valueColor: const Color(0xFFB54708),
                    icon: Icons.schedule_rounded,
                    iconColor: const Color(0xFFB54708),
                    iconBg: const Color(0xFFFFF4E5),
                    gradient: const [Color(0xFFFFFBF5), Color(0xFFFFFFFF)],
                    width: 156,
                  ),
                  const SizedBox(width: 8),
                  _statTile(
                    label: 'Sent',
                    value: _stats['Sent'] ?? 0,
                    valueColor: const Color(0xFF175CD3),
                    icon: Icons.send_rounded,
                    iconColor: const Color(0xFF175CD3),
                    iconBg: const Color(0xFFEAF2FF),
                    gradient: const [Color(0xFFF5F9FF), Color(0xFFFFFFFF)],
                    width: 156,
                  ),
                  const SizedBox(width: 8),
                  _statTile(
                    label: 'Approved',
                    value: _stats['Approved'] ?? 0,
                    valueColor: const Color(0xFF067647),
                    icon: Icons.verified_rounded,
                    iconColor: const Color(0xFF067647),
                    iconBg: const Color(0xFFE9F9F1),
                    gradient: const [Color(0xFFF4FCF7), Color(0xFFFFFFFF)],
                    width: 156,
                  ),
                  const SizedBox(width: 8),
                  _statTile(
                    label: 'Converted',
                    value: _stats['Converted'] ?? 0,
                    valueColor: const Color(0xFF7A5AF8),
                    icon: Icons.swap_horiz_rounded,
                    iconColor: const Color(0xFF7A5AF8),
                    iconBg: const Color(0xFFF3EEFF),
                    gradient: const [Color(0xFFFAF8FF), Color(0xFFFFFFFF)],
                    width: 156,
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _exporting ? null : () => _exportQuotations('pdf'),
                  icon: _exporting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.file_download_outlined, size: 16),
                  label: const Text('Export PDF'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _exporting
                      ? null
                      : () => _exportQuotations('excel'),
                  icon: const Icon(Icons.grid_on_outlined, size: 16),
                  label: const Text('Export Excel'),
                ),
              ],
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
                            children: const [
                              SizedBox(height: 100),
                              Center(
                                child: Text(
                                  'No quotations found',
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

  /// Returns a formatted quotation number, falling back to QT-{year}-{id}.
  String _quoteNumber(Map<String, dynamic> qt) {
    final raw =
        (qt['quote_no'] ??
                qt['quoteNo'] ??
                qt['quotation_no'] ??
                qt['quotationNo'] ??
                qt['reference_no'] ??
                qt['referenceNo'] ??
                '')
            .toString()
            .trim();
    if (raw.isNotEmpty) return raw;

    final idValue = qt['id'];
    final id = idValue is int ? idValue : int.tryParse(idValue.toString());
    if (id == null || id <= 0) return '';

    final quoteDateRaw =
        (qt['quote_date'] ??
                qt['quoteDate'] ??
                qt['created_at'] ??
                qt['createdAt'] ??
                '')
            .toString()
            .trim();
    final year = quoteDateRaw.length >= 4
        ? quoteDateRaw.substring(0, 4)
        : DateTime.now().year.toString();
    return 'QT-$year-${id.toString().padLeft(4, '0')}';
  }

  Widget _card(Map<String, dynamic> qt) {
    final theme = Theme.of(context);
    final quoteNo = _quoteNumber(qt);
    final idValue = qt['id'];
    final quotationId = idValue is int
        ? idValue
        : int.tryParse(idValue.toString());
    final client = _stringValue(qt, 'client_name', 'client');
    final attention = _stringValue(qt, 'attention', 'attention');
    final quoteDate = _stringValue(qt, 'quote_date', 'quoteDate');
    final status = _stringValue(qt, 'status', 'status');
    final statusLower = status.toLowerCase();
    final total = _doubleValue(qt, 'total_amount', 'total');
    final summary = _serviceSummary(qt);
    final lineItems = _lineItemCount(qt);

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
                    if (quoteNo.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F0FF),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFD6BBFB)),
                        ),
                        child: Text(
                          quoteNo,
                          style: const TextStyle(
                            color: Color(0xFF6941C6),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    Text(
                      client.isEmpty ? '-' : client,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
              StatusBadge(status: status.isEmpty ? 'Draft' : status),
            ],
          ),
          const SizedBox(height: 10),
          if (attention.isNotEmpty)
            _gradientPanel(
              colors: const [Color(0xFFEAF7F4), Color(0xFFFFFFFF)],
              child: _detailRow(Icons.person_outline, 'Attention', attention),
            ),
          if (attention.isNotEmpty) const SizedBox(height: 8),
          _gradientPanel(
            colors: const [Color(0xFFFFF5DB), Color(0xFFFFFFFF)],
            child: _detailRow(
              Icons.description_outlined,
              'Service Summary',
              summary.isEmpty ? '-' : summary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _detailChip(
                  Icons.calendar_today_outlined,
                  quoteDate.isEmpty ? '-' : quoteDate,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _detailChip(
                  Icons.format_list_bulleted_outlined,
                  '$lineItems line item${lineItems == 1 ? '' : 's'}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _gradientPanel(
            colors: const [Color(0xFFF2EEFF), Color(0xFFFFFFFF)],
            child: _detailRow(
              Icons.attach_money_outlined,
              'Total Amount',
              _formatAmount(total),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.end,
            runAlignment: WrapAlignment.end,
            spacing: 6,
            runSpacing: 6,
            children: [
              ElevatedButton.icon(
                onPressed: _downloadingId == quotationId
                    ? null
                    : () => _downloadPdf(qt),
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
                icon: _downloadingId == quotationId
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.picture_as_pdf_outlined, size: 15),
                label: Text(
                  _downloadingId == quotationId ? 'Downloading' : 'PDF',
                ),
              ),
              ElevatedButton.icon(
                onPressed:
                    quotationId == null ||
                        _markingSentId == quotationId ||
                        statusLower == 'sent' ||
                        statusLower == 'converted'
                    ? null
                    : () => _markSent(qt),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEAF2FF),
                  foregroundColor: const Color(0xFF175CD3),
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
                icon: _markingSentId == quotationId
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined, size: 15),
                label: const Text('Mark Sent'),
              ),
              ElevatedButton.icon(
                onPressed: quotationId == null || _convertingId == quotationId
                    ? null
                    : () => _convertToPi(
                        qt,
                        regenerate: statusLower == 'converted',
                      ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF3EEFF),
                  foregroundColor: const Color(0xFF6941C6),
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
                icon: _convertingId == quotationId
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.transform_outlined, size: 15),
                label: Text(
                  statusLower == 'converted' ? 'Regenerate PI' : 'Convert PI',
                ),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  if (quotationId == null) return;
                  final updated = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) =>
                          QuotationCreateScreen(editId: quotationId),
                    ),
                  );
                  if (updated == true) {
                    await _load(reset: true);
                  }
                },
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
                onPressed: () => _delete(qt),
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

  Widget _detailChip(IconData icon, String value) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF8FAFC), Color(0xFFFFFFFF)],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outline, width: 0.6),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            icon,
            size: 14,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _gradientPanel({required List<Color> colors, required Widget child}) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outline, width: 0.6),
      ),
      child: child,
    );
  }

  Widget _statTile({
    required String label,
    required int value,
    required Color valueColor,
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required List<Color> gradient,
    required double width,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 9),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E7EC)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A101828),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            '$value',
            style: TextStyle(
              color: valueColor,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              height: 1.0,
            ),
          ),
          Text(
            'quotations',
            style: TextStyle(
              color: valueColor.withOpacity(0.85),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
