import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../services/api_service.dart';
import '../widgets/status_badge.dart';

class FuelRequisitionsScreen extends StatefulWidget {
  const FuelRequisitionsScreen({super.key});

  @override
  State<FuelRequisitionsScreen> createState() => _FuelRequisitionsScreenState();
}

class _FuelRequisitionsScreenState extends State<FuelRequisitionsScreen> {
  final _searchCtrl = TextEditingController();
  List<dynamic> _items = <dynamic>[];
  List<dynamic> _leads = <dynamic>[];
  bool _loading = true;
  int? _editingId;
  int? _deletingId;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    try {
      final results = await Future.wait([
        ApiService.fetchFuelRequisitions().catchError((_) => <dynamic>[]),
        ApiService.fetchList('/leads').catchError((_) => <dynamic>[]),
      ]);

      if (!mounted) return;
      setState(() {
        _items = List<dynamic>.from(results[0]);
        _leads = List<dynamic>.from(results[1]);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load fuel requisitions: $e')),
      );
    }
  }

  int? _idOf(Map<String, dynamic> row) {
    final raw =
        row['id'] ?? row['fuel_requisition_id'] ?? row['fuelRequisitionId'];
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '');
  }

  String _leadLabel(dynamic rawLead) {
    if (rawLead is! Map) return '-';
    final lead = Map<String, dynamic>.from(rawLead);
    final company = (lead['client_company'] ?? lead['clientCompany'] ?? 'Lead')
        .toString();
    final bookingRef = (lead['booking_ref'] ?? lead['bookingRef'] ?? '')
        .toString();
    if (bookingRef.trim().isEmpty) return company;
    return '$company - $bookingRef';
  }

  String _leadIdValue(dynamic rawLead) {
    if (rawLead is! Map) return '';
    final lead = Map<String, dynamic>.from(rawLead);
    final id = lead['id'] ?? lead['lead_id'] ?? lead['leadId'] ?? '';
    return id.toString();
  }

  String _rowLeadLabel(Map<String, dynamic> row) {
    final leadRaw = row['lead'];
    if (leadRaw is Map) {
      return _leadLabel(leadRaw);
    }

    final leadId = (row['lead_id'] ?? row['leadId'] ?? row['leadID'] ?? '')
        .toString();
    if (leadId.isEmpty) return '-';

    for (final raw in _leads) {
      if (raw is! Map) continue;
      final lead = Map<String, dynamic>.from(raw);
      if (_leadIdValue(lead) == leadId) {
        return _leadLabel(lead);
      }
    }

    return 'Lead #$leadId';
  }

  double _litresValue(Map<String, dynamic> row) {
    final raw = row['litres'] ?? row['liters'] ?? row['fuel_litres'] ?? 0;
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw.toString()) ?? 0;
  }

  String _reasonValue(Map<String, dynamic> row) {
    return (row['reason'] ?? row['purpose'] ?? '').toString();
  }

  String _statusValue(Map<String, dynamic> row) {
    return (row['status'] ?? row['state'] ?? 'Pending').toString();
  }

  String _formatDateTime(String value) {
    if (value.trim().isEmpty) return '-';
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    final month = parsed.month.toString().padLeft(2, '0');
    final day = parsed.day.toString().padLeft(2, '0');
    final hour = parsed.hour.toString().padLeft(2, '0');
    final minute = parsed.minute.toString().padLeft(2, '0');
    return '${parsed.year}-$month-$day $hour:$minute';
  }

  List<dynamic> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _items;

    return _items.where((raw) {
      if (raw is! Map) return false;
      final row = Map<String, dynamic>.from(raw);
      final lead = _rowLeadLabel(row).toLowerCase();
      final reason = _reasonValue(row).toLowerCase();
      final litres = _litresValue(row).toStringAsFixed(2).toLowerCase();
      return lead.contains(q) || reason.contains(q) || litres.contains(q);
    }).toList();
  }

  Future<void> _viewDetails(Map<String, dynamic> row) async {
    final id = _idOf(row);
    if (id == null) return;

    try {
      final details = await ApiService.fetchFuelRequisition(id);
      if (!mounted) return;

      final leadLabel = _rowLeadLabel(details);
      final litres = _litresValue(details);
      final reason = _reasonValue(details);
      final status = _statusValue(details);
      final createdAt = (details['created_at'] ?? details['createdAt'] ?? '')
          .toString();

      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Fuel Requisition Details'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Lead: $leadLabel'),
              const SizedBox(height: 8),
              Text('Litres: ${litres.toStringAsFixed(2)} L'),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Status: '),
                  StatusBadge(status: status),
                ],
              ),
              const SizedBox(height: 8),
              Text('Reason: ${reason.isEmpty ? '-' : reason}'),
              if (createdAt.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Created: ${_formatDateTime(createdAt)}'),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load requisition details: $e')),
      );
    }
  }

  Future<void> _openCreateDialog({Map<String, dynamic>? initial}) async {
    if (_leads.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No leads available to select')),
      );
      return;
    }

    final initialLeadId =
        (initial?['lead_id'] ??
                initial?['leadId'] ??
                initial?['lead']?['id'] ??
                '')
            .toString();
    final initialLitres = _litresValue(initial ?? <String, dynamic>{});
    final initialReason = _reasonValue(initial ?? <String, dynamic>{});
    final editId = initial == null ? null : _idOf(initial);

    final formKey = GlobalKey<FormState>();
    String? selectedLeadId = initialLeadId.isEmpty ? null : initialLeadId;
    String litresText = initialLitres <= 0 ? '' : initialLitres.toString();
    String reasonText = initialReason;
    var submitting = false;

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocalState) => AlertDialog(
            title: Text(
              editId == null ? 'New Fuel Requisition' : 'Edit Fuel Requisition',
            ),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: selectedLeadId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Lead'),
                      items: _leads.whereType<Map>().map((raw) {
                        final lead = Map<String, dynamic>.from(raw);
                        final id = _leadIdValue(lead);
                        return DropdownMenuItem<String>(
                          value: id,
                          child: Text(_leadLabel(lead)),
                        );
                      }).toList(),
                      onChanged: (value) {
                        selectedLeadId = value;
                      },
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Lead is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      initialValue: litresText,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Litres',
                        hintText: 'e.g. 40',
                      ),
                      onChanged: (value) {
                        litresText = value;
                      },
                      validator: (value) {
                        final v = double.tryParse((value ?? '').trim());
                        if (v == null || v <= 0) {
                          return 'Litres must be greater than 0';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      initialValue: reasonText,
                      decoration: const InputDecoration(labelText: 'Reason'),
                      maxLines: 3,
                      onChanged: (value) {
                        reasonText = value;
                      },
                      validator: (value) {
                        if ((value ?? '').trim().isEmpty) {
                          return 'Reason is required';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: submitting ? null : () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: submitting
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;

                        setLocalState(() => submitting = true);
                        try {
                          final payload = {
                            'leadId': int.parse(selectedLeadId!),
                            'litres': double.parse(litresText.trim()),
                            'reason': reasonText.trim(),
                          };

                          if (editId == null) {
                            await ApiService.createFuelRequisition(payload);
                          } else {
                            await ApiService.updateFuelRequisition(
                              editId,
                              payload,
                            );
                          }

                          if (!mounted || !ctx.mounted) return;
                          Navigator.of(ctx).pop(true);
                        } catch (e) {
                          if (!mounted || !ctx.mounted) return;
                          final msg = e.toString().toLowerCase();
                          final routeMissing =
                              msg.contains('404') || msg.contains('405');
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                routeMissing
                                    ? 'Edit/Delete route is not enabled on backend yet.'
                                    : 'Failed to save fuel requisition: $e',
                              ),
                            ),
                          );
                        } finally {
                          if (ctx.mounted) {
                            setLocalState(() => submitting = false);
                          }
                        }
                      },
                child: submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(editId == null ? 'Create' : 'Save'),
              ),
            ],
          ),
        );
      },
    );

    if (created == true) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            editId == null
                ? 'Fuel requisition created successfully'
                : 'Fuel requisition updated successfully',
          ),
        ),
      );
    }
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    final id = _idOf(row);
    if (id == null) return;

    setState(() => _editingId = id);
    try {
      final details = await ApiService.fetchFuelRequisition(id);
      if (!mounted) return;
      await _openCreateDialog(initial: details);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to open edit form: $e')));
    } finally {
      if (mounted) {
        setState(() => _editingId = null);
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final id = _idOf(row);
    if (id == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete fuel requisition'),
        content: const Text(
          'Are you sure you want to delete this fuel requisition?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Delete',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _deletingId = id);
    try {
      await ApiService.removeFuelRequisition(id);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fuel requisition deleted successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().toLowerCase();
      final routeMissing = msg.contains('404') || msg.contains('405');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            routeMissing
                ? 'Delete route is not enabled on backend yet.'
                : 'Delete failed: $e',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _deletingId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateDialog,
        backgroundColor: theme.colorScheme.primary,
        icon: const Icon(Icons.local_gas_station, color: Colors.white),
        label: const Text('New Request', style: TextStyle(color: Colors.white)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: TextField(
              controller: _searchCtrl,
              style: TextStyle(color: theme.colorScheme.onSurface),
              decoration: InputDecoration(
                hintText: 'Search fuel requisitions...',
                prefixIcon: Icon(
                  Icons.search,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? Center(
                    child: CircularProgressIndicator(
                      color: theme.colorScheme.primary,
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    color: theme.colorScheme.primary,
                    child: _filtered.isEmpty
                        ? ListView(
                            children: [
                              const SizedBox(height: 100),
                              Center(
                                child: Text(
                                  'No fuel requisitions found',
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 2, 16, 90),
                            itemCount: _filtered.length,
                            itemBuilder: (_, i) {
                              final row = _filtered[i] as Map;
                              return _card(Map<String, dynamic>.from(row));
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _card(Map<String, dynamic> row) {
    final theme = Theme.of(context);
    final lead = _rowLeadLabel(row);
    final litres = _litresValue(row);
    final reason = _reasonValue(row);
    final status = _statusValue(row);
    final createdAt = (row['created_at'] ?? row['createdAt'] ?? '').toString();

    return GestureDetector(
      onTap: () => _viewDetails(row),
      child: Container(
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
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: const Color(kGoldColor).withOpacity(0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.local_gas_station,
                    color: Color(kGoldColor),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    lead,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                StatusBadge(status: status),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF7F1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${litres.toStringAsFixed(2)} L',
                    style: const TextStyle(
                      color: Color(0xFF0F7B45),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              reason.isEmpty ? '-' : reason,
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            if (createdAt.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _formatDateTime(createdAt),
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => _viewDetails(row),
                  icon: const Icon(Icons.visibility_outlined, size: 15),
                  label: const Text('View'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _editingId == _idOf(row) ? null : () => _edit(row),
                  icon: _editingId == _idOf(row)
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.edit_outlined, size: 15),
                  label: const Text('Edit'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _deletingId == _idOf(row)
                      ? null
                      : () => _delete(row),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  icon: _deletingId == _idOf(row)
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.error,
                          ),
                        )
                      : const Icon(Icons.delete_outline, size: 15),
                  label: const Text('Delete'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
