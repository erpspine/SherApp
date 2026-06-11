import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'dart:io';
import '../config/app_config.dart';
import '../models/vehicle_checklist.dart';
import '../services/api_service.dart';

List<String> _extractInspectionImageUrls(Map<String, dynamic> source) {
  final urls = <String>[];
  final seen = <String>{};

  String? normalizeUrl(String raw) {
    final value = raw.trim().replaceAll('\\', '/');
    if (value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }

    if (value.startsWith('/public/storage/')) {
      return '$kBackendOrigin${value.replaceFirst('/public', '')}';
    }

    if (value.startsWith('public/storage/')) {
      return '$kBackendOrigin/${value.replaceFirst('public/', '')}';
    }

    if (value.startsWith('/storage/')) {
      return '$kBackendOrigin$value';
    }

    if (value.startsWith('storage/')) {
      return '$kBackendOrigin/$value';
    }

    if (value.startsWith('/inspection-images/')) {
      return '$kBackendOrigin/storage$value';
    }

    if (value.startsWith('inspection-images/')) {
      return '$kBackendOrigin/storage/$value';
    }

    final looksLikeImagePath = RegExp(
      r'\.(jpg|jpeg|png|webp|gif)(\?.*)?$',
      caseSensitive: false,
    ).hasMatch(value);

    if (looksLikeImagePath && !value.startsWith('/data/user/0/')) {
      final trimmed = value.startsWith('/') ? value.substring(1) : value;
      return '$kBackendOrigin/storage/$trimmed';
    }

    // Keep non-URL strings (for example local device paths) out of network rendering.
    return null;
  }

  void addUrl(dynamic value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) return;
    final normalized = normalizeUrl(raw);
    if (normalized == null) return;
    if (seen.add(normalized)) {
      urls.add(normalized);
    }
  }

  void collect(dynamic value) {
    if (value is String) {
      final raw = value.trim();
      if ((raw.startsWith('{') && raw.endsWith('}')) ||
          (raw.startsWith('[') && raw.endsWith(']'))) {
        try {
          collect(jsonDecode(raw));
        } catch (_) {
          // Ignore malformed JSON strings and fall back to URL/path parsing.
        }
      }
      addUrl(value);
      return;
    }

    if (value is List) {
      for (final entry in value) {
        collect(entry);
      }
      return;
    }

    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      addUrl(map['url']);
      addUrl(map['image_url']);
      addUrl(map['imageUrl']);
      addUrl(map['full_url']);
      addUrl(map['fullUrl']);
      addUrl(map['download_url']);
      addUrl(map['downloadUrl']);
      addUrl(map['file_url']);
      addUrl(map['fileUrl']);
      addUrl(map['image']);
      addUrl(map['file']);
      addUrl(map['src']);
      addUrl(map['path']);
      addUrl(map['image_path']);
      addUrl(map['imagePath']);
      addUrl(map['filepath']);
      addUrl(map['file_path']);

      // Traverse all nested values so wrapper keys like inspection/payload/meta are supported.
      for (final nested in map.values) {
        if (nested != null) {
          collect(nested);
        }
      }
    }
  }

  collect(source);
  return urls;
}

Future<Map<String, String>?> _inspectionImageHeaders() async {
  final token = await ApiService.getToken();
  if (token == null || token.isEmpty) return null;
  return {'Authorization': 'Bearer $token'};
}

String? _extractUploadedImagePath(Map<String, dynamic> response) {
  final direct =
      response['path'] ?? response['image_path'] ?? response['imagePath'];
  if (direct != null) {
    final value = direct.toString().trim().replaceAll('\\', '/');
    if (value.isNotEmpty) return value;
  }

  final image = response['image'];
  if (image is Map) {
    final path = image['path'] ?? image['image_path'] ?? image['imagePath'];
    if (path != null) {
      final value = path.toString().trim().replaceAll('\\', '/');
      if (value.isNotEmpty) return value;
    }
  }

  final data = response['data'];
  if (data is Map) {
    final path = data['path'] ?? data['image_path'] ?? data['imagePath'];
    if (path != null) {
      final value = path.toString().trim().replaceAll('\\', '/');
      if (value.isNotEmpty) return value;
    }
  }

  return null;
}

List<String> _inspectionImageCandidates(String url) {
  final candidates = <String>[];
  final seen = <String>{};

  void add(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return;
    if (seen.add(normalized)) {
      candidates.add(normalized);
    }
  }

  add(url);

  // Normalize accidental duplicate storage segment.
  if (url.contains('/storage/storage/')) {
    add(url.replaceAll('/storage/storage/', '/storage/'));
  }

  // Only generate alternate route when original starts from /storage/inspection-images.
  if (url.contains('/storage/inspection-images/')) {
    add(url.replaceAll('/storage/inspection-images/', '/inspection-images/'));
  }

  // Only generate /storage/ variant when original starts from /inspection-images.
  if (url.contains('/inspection-images/') &&
      !url.contains('/storage/inspection-images/')) {
    add(url.replaceAll('/inspection-images/', '/storage/inspection-images/'));
  }

  return candidates;
}

Future<void> _showImagePreviewDialog(
  BuildContext context, {
  required Widget child,
}) async {
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black.withOpacity(0.92),
    builder: (dialogContext) {
      return Dialog(
        insetPadding: const EdgeInsets.all(10),
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                margin: const EdgeInsets.only(top: 42),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(14),
                ),
                clipBehavior: Clip.antiAlias,
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  child: Center(child: child),
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: IconButton.filled(
                onPressed: () => Navigator.pop(dialogContext),
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _InspectionImageTile extends StatefulWidget {
  final String url;
  final Map<String, String>? headers;
  final BoxFit fit;

  const _InspectionImageTile({
    required this.url,
    this.headers,
    this.fit = BoxFit.cover,
  });

  @override
  State<_InspectionImageTile> createState() => _InspectionImageTileState();
}

class _InspectionImageTileState extends State<_InspectionImageTile> {
  late final List<String> _urls;
  int _attempt = 0;
  final List<String> _attemptLog = [];

  @override
  void initState() {
    super.initState();
    _urls = _inspectionImageCandidates(widget.url);
  }

  @override
  Widget build(BuildContext context) {
    final hasHeaders = widget.headers != null && widget.headers!.isNotEmpty;
    final attemptsPerRound = _urls.length;
    final totalAttempts = hasHeaders ? attemptsPerRound * 2 : attemptsPerRound;
    final isSecondRound = hasHeaders && _attempt >= attemptsPerRound;
    final urlIndex = isSecondRound ? _attempt - attemptsPerRound : _attempt;
    final currentUrl = _urls[urlIndex];
    final currentHeaders = isSecondRound ? null : widget.headers;
    if (_attemptLog.length <= _attempt) {
      _attemptLog.add('${isSecondRound ? 'no-auth' : 'auth'} => $currentUrl');
    }

    return Image.network(
      currentUrl,
      headers: currentHeaders,
      fit: widget.fit,
      errorBuilder: (_, error, __) {
        if (_attempt < totalAttempts - 1) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() => _attempt += 1);
          });
          return const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        debugPrint(
          'Inspection image failed to load after ${_attemptLog.length} attempt(s). '
          'Attempts: ${_attemptLog.join(' | ')} | Last error: $error',
        );
        return Icon(
          Icons.broken_image_outlined,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
      },
    );
  }
}

class VehicleChecklistScreen extends StatefulWidget {
  const VehicleChecklistScreen({super.key});

  @override
  State<VehicleChecklistScreen> createState() => _VehicleChecklistScreenState();
}

class _VehicleChecklistScreenState extends State<VehicleChecklistScreen> {
  List<dynamic> _checklists = [];
  bool _loading = true;
  int? _pdfInspectionId;
  int? _detailInspectionId;
  int? _editInspectionId;
  int? _deleteInspectionId;

  @override
  void initState() {
    super.initState();
    _loadChecklists();
  }

  Future<void> _loadChecklists() async {
    try {
      final data = await ApiService.fetchInspections();
      if (mounted) {
        setState(() {
          _checklists = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load inspections: $e')),
        );
      }
    }
  }

  void _openCreateForm() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.92,
        child: CreateChecklistForm(
          onSubmit: (_) {
            _loadChecklists();
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  int? _inspectionId(Map<String, dynamic> inspection) {
    final raw = inspection['id'] ?? inspection['inspection_id'];
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '');
  }

  String _inspectionRef(Map<String, dynamic> inspection) {
    return (inspection['inspection_no'] ??
            inspection['inspectionNo'] ??
            inspection['reference'] ??
            inspection['ref'] ??
            '')
        .toString();
  }

  List<dynamic> _inspectionItems(Map<String, dynamic> inspection) {
    for (final key in const [
      'items',
      'inspection_items',
      'inspectionItems',
      'checks',
      'checklist_items',
      'checklistItems',
    ]) {
      final value = inspection[key];
      if (value is List) return value;
    }

    final nested = inspection['data'];
    if (nested is Map<String, dynamic>) {
      final value = nested['items'];
      if (value is List) return value;
    }

    return const <dynamic>[];
  }

  Future<Map<String, dynamic>> _inspectionDetails(
    Map<String, dynamic> inspection,
  ) async {
    final id = _inspectionId(inspection);
    if (id == null) return inspection;

    final details = await ApiService.fetchInspection(id);
    final nested = details['inspection'];
    if (nested is Map<String, dynamic>) {
      return nested;
    }

    return details;
  }

  Future<void> _viewInspection(Map<String, dynamic> inspection) async {
    final id = _inspectionId(inspection);
    if (id != null) {
      setState(() => _detailInspectionId = id);
    }

    try {
      final details = await _inspectionDetails(inspection);
      final imageHeaders = await _inspectionImageHeaders();
      final merged = <String, dynamic>{...inspection, ...details};
      final rawType = details['checklistType'] ?? details['type'] ?? '';
      final type = checklistTypeLabel(rawType.toString());
      final lead = details['lead'];
      final vehicle = details['vehicle'];
      final items = _inspectionItems(details);
      final remarks = (details['remarks'] ?? details['notes'] ?? '').toString();
      final imageUrls = _extractInspectionImageUrls(merged);
      final leadName =
          (lead?['client_company'] ?? lead?['clientCompany'] ?? 'Lead')
              .toString();
      final leadRef = (lead?['booking_ref'] ?? lead?['bookingRef'] ?? '')
          .toString();
      final vehicleName = '${vehicle?['make'] ?? ''} ${vehicle?['model'] ?? ''}'
          .trim();
      final vehiclePlate = (vehicle?['plate_no'] ?? vehicle?['plateNo'] ?? '')
          .toString();
      final nokCount = items.where((raw) {
        if (raw is Map<String, dynamic>) {
          return (raw['status'] ?? '').toString().toUpperCase() == 'NOK';
        }

        if (raw is Map) {
          return (raw['status'] ?? '').toString().toUpperCase() == 'NOK';
        }

        return false;
      }).length;

      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) {
          final theme = Theme.of(sheetContext);

          return FractionallySizedBox(
            heightFactor: 0.92,
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.14),
                    blurRadius: 32,
                    offset: const Offset(0, -6),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 56,
                    height: 5,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.outline.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFEAF7F4), Color(0xFFFFF8E6)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _inspectionRef(details).isEmpty
                                      ? 'Inspection Details'
                                      : _inspectionRef(details),
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurface,
                                    fontSize: 28,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 7,
                                  ),
                                  decoration: BoxDecoration(
                                    color: type == 'Pre-Departure'
                                        ? const Color(0xFF0F7B45)
                                        : const Color(kGoldColor),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    type,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton.filledTonal(
                            onPressed: () => Navigator.pop(sheetContext),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _inspectionMetaCard(
                                  theme,
                                  icon: Icons.business_outlined,
                                  label: 'Lead',
                                  value: leadName,
                                  caption: leadRef.isEmpty ? null : leadRef,
                                  accent: theme.colorScheme.secondary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _inspectionMetaCard(
                                  theme,
                                  icon: Icons.directions_car_outlined,
                                  label: 'Vehicle',
                                  value: vehicleName.isEmpty
                                      ? '-'
                                      : vehicleName,
                                  caption: vehiclePlate.isEmpty
                                      ? null
                                      : vehiclePlate,
                                  accent: theme.colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: _inspectionStatCard(
                                  theme,
                                  label: 'Items',
                                  value: '${items.length}',
                                  accent: const Color(0xFF0F7B45),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _inspectionStatCard(
                                  theme,
                                  label: 'Issues',
                                  value: '$nokCount',
                                  accent: nokCount > 0
                                      ? theme.colorScheme.error
                                      : theme.colorScheme.secondary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Inspection Items',
                            style: TextStyle(
                              color: theme.colorScheme.onSurface,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (items.isEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: theme.colorScheme.outline.withOpacity(
                                    0.25,
                                  ),
                                ),
                              ),
                              child: Text(
                                'No inspection items found.',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            )
                          else
                            ...items.map((raw) {
                              final item = raw is Map<String, dynamic>
                                  ? raw
                                  : Map<String, dynamic>.from(raw as Map);
                              final name =
                                  (item['name'] ??
                                          item['text'] ??
                                          item['title'] ??
                                          '-')
                                      .toString();
                              final status = (item['status'] ?? 'OK')
                                  .toString()
                                  .toUpperCase();
                              final issue = (item['issue'] ?? '').toString();
                              final isProblem = status == 'NOK';

                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: isProblem
                                      ? const Color(0xFFFFF3F1)
                                      : const Color(0xFFF4FBF7),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: isProblem
                                        ? theme.colorScheme.error.withOpacity(
                                            0.22,
                                          )
                                        : const Color(
                                            0xFF0F7B45,
                                          ).withOpacity(0.18),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            name,
                                            style: TextStyle(
                                              color:
                                                  theme.colorScheme.onSurface,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isProblem
                                                ? theme.colorScheme.error
                                                : const Color(0xFF0F7B45),
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                          ),
                                          child: Text(
                                            status,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (issue.trim().isNotEmpty) ...[
                                      const SizedBox(height: 10),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                        child: Text(
                                          issue,
                                          style: TextStyle(
                                            color: theme.colorScheme.error,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            }),
                          if (remarks.trim().isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Remarks',
                              style: TextStyle(
                                color: theme.colorScheme.onSurface,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF8E6),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: const Color(
                                    kGoldColor,
                                  ).withOpacity(0.2),
                                ),
                              ),
                              child: Text(
                                remarks,
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface,
                                  height: 1.45,
                                ),
                              ),
                            ),
                          ],
                          if (imageUrls.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Text(
                              'Photos',
                              style: TextStyle(
                                color: theme.colorScheme.onSurface,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 10),
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    crossAxisSpacing: 10,
                                    mainAxisSpacing: 10,
                                  ),
                              itemCount: imageUrls.length,
                              itemBuilder: (_, i) {
                                return GestureDetector(
                                  onTap: () => _showImagePreviewDialog(
                                    sheetContext,
                                    child: _InspectionImageTile(
                                      url: imageUrls[i],
                                      headers: imageHeaders,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: theme.colorScheme.outline,
                                        width: 0.8,
                                      ),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(11),
                                      child: _InspectionImageTile(
                                        url: imageUrls[i],
                                        headers: imageHeaders,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load inspection: $e')));
    } finally {
      if (mounted && id != null) {
        setState(() => _detailInspectionId = null);
      }
    }
  }

  Future<void> _openEditForm(Map<String, dynamic> inspection) async {
    final id = _inspectionId(inspection);
    if (id == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invalid inspection ID')));
      return;
    }

    setState(() => _editInspectionId = id);
    try {
      final details = await _inspectionDetails(inspection);
      final merged = <String, dynamic>{...inspection, ...details};
      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => SizedBox(
          height: MediaQuery.of(context).size.height * 0.92,
          child: CreateChecklistForm(
            inspectionId: id,
            initialInspection: merged,
            onSubmit: (_) {
              _loadChecklists();
              Navigator.pop(context);
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to open edit form: $e')));
    } finally {
      if (mounted) {
        setState(() => _editInspectionId = null);
      }
    }
  }

  Future<void> _deleteInspection(Map<String, dynamic> inspection) async {
    final id = _inspectionId(inspection);
    if (id == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invalid inspection ID')));
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete inspection'),
        content: const Text(
          'Are you sure you want to delete this inspection submission?',
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

    setState(() => _deleteInspectionId = id);
    try {
      await ApiService.removeInspection(id);
      await _loadChecklists();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    } finally {
      if (mounted) {
        setState(() => _deleteInspectionId = null);
      }
    }
  }

  Future<void> _downloadInspectionPdf(Map<String, dynamic> inspection) async {
    final id = _inspectionId(inspection);
    if (id == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invalid inspection ID')));
      return;
    }

    setState(() => _pdfInspectionId = id);
    try {
      final bytes = await ApiService.downloadInspectionPdf(id);
      final dir = await getTemporaryDirectory();
      final ref = _inspectionRef(inspection);
      final safeName = (ref.isEmpty ? 'inspection-$id' : ref).replaceAll(
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
        setState(() => _pdfInspectionId = null);
      }
    }
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    Color? color,
    Widget? customIcon,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: customIcon ?? Icon(icon, size: 16, color: color),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(
          color: (color ?? Theme.of(context).colorScheme.outline).withOpacity(
            0.55,
          ),
          width: 1,
        ),
        visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _inspectionMetaCard(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required String value,
    String? caption,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (caption != null && caption.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              caption,
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _inspectionStatCard(
    ThemeData theme, {
    required String label,
    required String value,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: accent,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateForm,
        backgroundColor: theme.colorScheme.primary,
        icon: const Icon(Icons.add_circle_outline, color: Colors.white),
        label: const Text(
          'New Checklist',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(
                color: theme.colorScheme.primary,
              ),
            )
          : _checklists.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.checklist_outlined,
                    size: 64,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No Inspections',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create your first vehicle inspection checklist',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _checklists.length,
              itemBuilder: (_, i) => _checklistCard(_checklists[i]),
            ),
    );
  }

  Widget _checklistCard(Map<String, dynamic> checklist) {
    final theme = Theme.of(context);
    final inspectionId = _inspectionId(checklist);
    final rawType = (checklist['checklistType'] ?? checklist['type'] ?? '');
    final type = checklistTypeLabel(rawType.toString());
    final lead = checklist['lead'];
    final vehicle = checklist['vehicle'];
    final items = _inspectionItems(checklist);
    final nokCount = items
        .where(
          (item) =>
              (item['status'] ?? '').toString().toUpperCase() == 'NOK' ||
              item['isCompleted'] == false,
        )
        .length;
    final totalCount = items.length;

    final leadCompany =
        lead?['client_company'] ?? lead?['clientCompany'] ?? 'Lead';
    final leadRef = lead?['booking_ref'] ?? lead?['bookingRef'] ?? '';
    final vehicleName = '${vehicle?['make'] ?? ''} ${vehicle?['model'] ?? ''}'
        .trim();
    final vehiclePlate = vehicle?['plate_no'] ?? vehicle?['plateNo'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: nokCount > 0
              ? Color(kRedAccent).withOpacity(0.3)
              : Color(kTealColor).withOpacity(0.3),
          width: 1,
        ),
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
          // Header with type and status
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: type == 'Pre-Departure'
                      ? Color(0xFFEAF7F4)
                      : Color(0xFFFFF5DB),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: type == 'Pre-Departure'
                        ? Color(kTealColor).withOpacity(0.3)
                        : Color(kGoldColor).withOpacity(0.3),
                  ),
                ),
                child: Text(
                  type,
                  style: TextStyle(
                    color: type == 'Pre-Departure'
                        ? Color(kTealColor)
                        : Color(kGoldColor),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
              const Spacer(),
              if (nokCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Color(kRedAccent).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Color(kRedAccent).withOpacity(0.3),
                    ),
                  ),
                  child: Text(
                    '$nokCount Issues',
                    style: TextStyle(
                      color: Color(kRedAccent),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Color(kTealColor).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Color(kTealColor).withOpacity(0.3),
                    ),
                  ),
                  child: Text(
                    'OK',
                    style: TextStyle(
                      color: Color(kTealColor),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          // Lead info
          Text(
            leadCompany,
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            leadRef,
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          // Vehicle info
          Row(
            children: [
              Icon(
                Icons.directions_car_outlined,
                color: theme.colorScheme.secondary,
                size: 16,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  vehicleName,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                vehiclePlate,
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value:
                  (totalCount - nokCount) / (totalCount > 0 ? totalCount : 1),
              minHeight: 6,
              backgroundColor: theme.colorScheme.outline.withOpacity(0.2),
              valueColor: AlwaysStoppedAnimation<Color>(
                nokCount > 0
                    ? Color(kRedAccent).withOpacity(0.6)
                    : Color(kTealColor),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '$totalCount items checked',
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _actionButton(
                label: 'View',
                icon: Icons.visibility_outlined,
                color: theme.colorScheme.secondary,
                onPressed: inspectionId == null
                    ? null
                    : (_detailInspectionId == inspectionId
                          ? null
                          : () => _viewInspection(checklist)),
                customIcon: _detailInspectionId == inspectionId
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.secondary,
                        ),
                      )
                    : null,
              ),
              _actionButton(
                label: 'Edit',
                icon: Icons.edit_outlined,
                color: theme.colorScheme.primary,
                onPressed: inspectionId == null
                    ? null
                    : (_editInspectionId == inspectionId
                          ? null
                          : () => _openEditForm(checklist)),
                customIcon: _editInspectionId == inspectionId
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.primary,
                        ),
                      )
                    : null,
              ),
              _actionButton(
                label: 'PDF',
                icon: Icons.picture_as_pdf_outlined,
                color: const Color(kGoldColor),
                onPressed: inspectionId == null
                    ? null
                    : (_pdfInspectionId == inspectionId
                          ? null
                          : () => _downloadInspectionPdf(checklist)),
                customIcon: _pdfInspectionId == inspectionId
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
              ),
              _actionButton(
                label: 'Delete',
                icon: Icons.delete_outline,
                color: theme.colorScheme.error,
                onPressed: inspectionId == null
                    ? null
                    : (_deleteInspectionId == inspectionId
                          ? null
                          : () => _deleteInspection(checklist)),
                customIcon: _deleteInspectionId == inspectionId
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.error,
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Create Checklist Form Widget
class CreateChecklistForm extends StatefulWidget {
  final Function(VehicleChecklist) onSubmit;
  final int? inspectionId;
  final Map<String, dynamic>? initialInspection;

  const CreateChecklistForm({
    required this.onSubmit,
    this.inspectionId,
    this.initialInspection,
    super.key,
  });

  @override
  State<CreateChecklistForm> createState() => _CreateChecklistFormState();
}

class _CreateChecklistFormState extends State<CreateChecklistForm> {
  List<dynamic> _leads = [];
  List<dynamic> _checklistDefinitions = [];
  List<dynamic> _existingInspections = [];
  List<dynamic> _allocations = [];
  Map<int, Map<String, dynamic>> _vehiclesById = {};
  List<Map<String, dynamic>> _leadVehicles = [];
  Map<String, String> _groupNameByLeadId = {};
  bool _leadLoading = true;
  bool _checklistLoading = true;
  bool _vehicleLoading = false;
  bool _submitting = false;
  Map<String, String>? _imageHeaders;
  String? _checklistError;
  Map<String, dynamic>? _selectedLead;
  Map<String, dynamic>? _selectedVehicle;

  String _checklistType = kPreDepartureChecklistType;
  List<ChecklistItem> _items = [];
  List<String> _existingImageUrls = [];
  List<String> _imagePaths = [];
  List<Map<String, dynamic>> _submittedItems = const [];

  final _remarksCtrl = TextEditingController();
  final _odometerCtrl = TextEditingController();
  final _parkingLocationCtrl = TextEditingController();
  final _imagePicker = ImagePicker();

  bool get _isEditMode => widget.inspectionId != null;

  @override
  void initState() {
    super.initState();
    _seedInitialInspection();
    _loadImageHeaders();
    _loadLeads();
    _loadExistingInspections();
    _loadChecklistDefinitions();
    _loadAllocations();
  }

  Future<void> _loadImageHeaders() async {
    final headers = await _inspectionImageHeaders();
    if (!mounted) return;
    setState(() => _imageHeaders = headers);
  }

  void _seedInitialInspection() {
    final initial = widget.initialInspection;
    if (initial == null) return;

    final initialType = (initial['checklistType'] ?? initial['type'] ?? '')
        .toString();
    final normalizedType = _normalizeChecklistType(initialType);
    if (normalizedType.isNotEmpty) {
      _checklistType = normalizedType;
    }

    final lead = initial['lead'];
    if (lead is Map<String, dynamic>) {
      _selectedLead = lead;
    } else if (lead is Map) {
      _selectedLead = Map<String, dynamic>.from(lead);
    }

    final vehicle = initial['vehicle'];
    if (vehicle is Map<String, dynamic>) {
      _selectedVehicle = vehicle;
    } else if (vehicle is Map) {
      _selectedVehicle = Map<String, dynamic>.from(vehicle);
    }

    final remarks = (initial['remarks'] ?? initial['notes'] ?? '').toString();
    _remarksCtrl.text = remarks;
    _parkingLocationCtrl.text =
        (initial['parking_location'] ??
                initial['parkingLocation'] ??
                initial['parked_location'] ??
                initial['parkedLocation'] ??
                '')
            .toString();
    _odometerCtrl.text =
        (initial['odometer'] ??
                initial['odometer_reading'] ??
                initial['odometerOut'] ??
                initial['odometer_out'] ??
                initial['odometerIn'] ??
                initial['odometer_in'] ??
                initial['mileage'] ??
                '')
            .toString();
    _existingImageUrls = _extractInspectionImageUrls(initial);

    _submittedItems = _extractSubmittedItems(initial);
  }

  List<Map<String, dynamic>> _extractSubmittedItems(
    Map<String, dynamic> source,
  ) {
    for (final key in const [
      'items',
      'inspection_items',
      'inspectionItems',
      'checklist_items',
      'checklistItems',
      'checks',
    ]) {
      final value = source[key];
      if (value is List) {
        return value
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      }
    }

    return const [];
  }

  List<ChecklistItem> _mergeSubmittedValues(List<ChecklistItem> items) {
    if (_submittedItems.isEmpty) return items;

    final byId = <int, Map<String, dynamic>>{};
    final byName = <String, Map<String, dynamic>>{};

    for (final item in _submittedItems) {
      final rawId = item['id'] ?? item['item_id'] ?? item['checklist_item_id'];
      final id = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
      if (id != null) {
        byId[id] = item;
      }

      final name = (item['name'] ?? item['text'] ?? item['title'] ?? '')
          .toString();
      if (name.trim().isNotEmpty) {
        byName[name.trim().toLowerCase()] = item;
      }
    }

    for (final item in items) {
      final mapped = byId[item.id] ?? byName[item.name.trim().toLowerCase()];
      if (mapped == null) continue;

      item.status = (mapped['status'] ?? 'OK').toString().toUpperCase();
      item.issue = (mapped['issue'] ?? mapped['notes'] ?? '').toString();
    }

    return items;
  }

  @override
  void dispose() {
    _remarksCtrl.dispose();
    _odometerCtrl.dispose();
    _parkingLocationCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLeads() async {
    try {
      final results = await Future.wait([
        ApiService.fetchList('/leads'),
        ApiService.fetchList('/quotations').catchError((_) => <dynamic>[]),
      ]);

      final data = results[0];
      final quotationsData = results[1];

      // Build group name map from quotations (latest per lead)
      final groupMap = <String, String>{};
      for (final raw in quotationsData) {
        if (raw is! Map) continue;
        final q = Map<String, dynamic>.from(raw);
        final leadId = (q['lead_id'] ?? q['leadId'] ?? '').toString();
        final groupName = (q['group_name'] ?? q['groupName'] ?? '').toString();
        if (leadId.isEmpty || groupName.isEmpty) continue;
        // Keep any non-empty group name; last write wins (sorted by server)
        groupMap[leadId] = groupName;
      }

      Map<String, dynamic>? matchedLead;
      final selectedLeadId =
          (_selectedLead?['id'] ?? _selectedLead?['lead_id'] ?? '').toString();
      if (selectedLeadId.isNotEmpty) {
        for (final raw in data) {
          if (raw is! Map) continue;
          final lead = Map<String, dynamic>.from(raw);
          final leadId = (lead['id'] ?? lead['lead_id'] ?? '').toString();
          if (leadId == selectedLeadId) {
            matchedLead = lead;
            break;
          }
        }
      }

      if (mounted) {
        setState(() {
          _leads = data;
          _groupNameByLeadId = groupMap;
          if (matchedLead != null) {
            _selectedLead = matchedLead;
          }
          _leadLoading = false;
        });

        if (_selectedLead != null) {
          _refreshLeadVehicles(preserveSelection: true);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _leadLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load leads: $e')));
      }
    }
  }

  Future<void> _loadExistingInspections() async {
    try {
      final data = await ApiService.fetchInspections();
      if (!mounted) return;

      setState(() {
        _existingInspections = data;
      });

      if (_selectedLead != null) {
        _refreshLeadVehicles(preserveSelection: true);
      }
    } catch (_) {}
  }

  Future<void> _loadChecklistDefinitions() async {
    try {
      final response = await ApiService.get('/checklists');
      if (!mounted) return;

      var definitions = _extractChecklistDefinitions(response);

      // If API returns empty, use fallback defaults
      if (definitions.isEmpty) {
        definitions = _getDefaultChecklistDefinitions();
      }

      final resolvedType = _resolveInitialChecklistType(definitions);

      final resolvedItems = _buildItemsForType(
        resolvedType,
        sourceDefinitions: definitions,
      );
      final mergedItems = _mergeSubmittedValues(resolvedItems);

      setState(() {
        _checklistDefinitions = definitions;
        _checklistType = resolvedType;
        _items = mergedItems;
        _checklistError = null;
        _checklistLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _checklistDefinitions = [];
        _items = [];
        _checklistError = e.toString();
        _checklistLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load checklist templates: $e')),
      );
    }
  }

  List<dynamic> _getDefaultChecklistDefinitions() {
    return [
      {
        'id': 1,
        'title': 'Engine & Fluid Checks',
        'type': kPreDepartureChecklistType,
        'checklist_type': kPreDepartureChecklistType,
        'items': [
          {'id': 101, 'text': 'Check fuel level'},
          {'id': 102, 'text': 'Check engine oil'},
          {'id': 103, 'text': 'Check coolant level'},
          {'id': 104, 'text': 'Check brake fluid'},
        ],
      },
      {
        'id': 2,
        'title': 'Exterior Checks',
        'type': kPreDepartureChecklistType,
        'checklist_type': kPreDepartureChecklistType,
        'items': [
          {'id': 201, 'text': 'Check tire tread depth'},
          {'id': 202, 'text': 'Check tire pressure'},
          {'id': 203, 'text': 'Check all lights'},
          {'id': 204, 'text': 'Check windshield wipers'},
          {'id': 205, 'text': 'Inspect for dents/damage'},
        ],
      },
      {
        'id': 3,
        'title': 'Safety Features',
        'type': kPreDepartureChecklistType,
        'checklist_type': kPreDepartureChecklistType,
        'items': [
          {'id': 301, 'text': 'Test brakes'},
          {'id': 302, 'text': 'Check steering'},
          {'id': 303, 'text': 'Check seatbelts'},
          {'id': 304, 'text': 'Verify airbags functional'},
        ],
      },
      {
        'id': 4,
        'title': 'Post-Trip Inspection',
        'type': kPostDepartureChecklistType,
        'checklist_type': kPostDepartureChecklistType,
        'items': [
          {'id': 401, 'text': 'Check for new damage'},
          {'id': 402, 'text': 'Check fuel level'},
          {'id': 403, 'text': 'Inspect undercarriage'},
          {'id': 404, 'text': 'Document odometer reading'},
        ],
      },
    ];
  }

  List<dynamic> _extractChecklistDefinitions(dynamic response) {
    final definitions = _findChecklistList(response);
    if (definitions != null) {
      return definitions;
    }

    if (response is Map<String, dynamic>) {
      final message = response['message']?.toString();
      throw StateError(message ?? 'Checklist API did not return a list');
    }

    throw StateError('Unexpected checklist response format');
  }

  List<dynamic>? _findChecklistList(dynamic payload) {
    if (payload is List) {
      return payload.cast<dynamic>();
    }

    if (payload is! Map) {
      return null;
    }

    final map = payload is Map<String, dynamic>
        ? payload
        : Map<String, dynamic>.from(payload);

    for (final key in const [
      'checklists',
      'templates',
      'definitions',
      'inspection_checklists',
      'inspectionChecklists',
      'items',
      'data',
    ]) {
      final value = map[key];
      if (value is List) {
        return value.cast<dynamic>();
      }
    }

    for (final key in const [
      'data',
      'result',
      'results',
      'payload',
      'response',
    ]) {
      final nested = map[key];
      final found = _findChecklistList(nested);
      if (found != null) {
        return found;
      }
    }

    if (_looksLikeChecklistDefinition(map)) {
      return [map];
    }

    return null;
  }

  String _resolveInitialChecklistType(List<dynamic> definitions) {
    final availableTypes = definitions
        .map((definition) => _definitionChecklistType(definition))
        .where((type) => type.isNotEmpty)
        .toSet()
        .toList();

    if (availableTypes.contains(_checklistType)) {
      return _checklistType;
    }
    if (availableTypes.contains(kPreDepartureChecklistType)) {
      return kPreDepartureChecklistType;
    }
    if (availableTypes.contains(kPostDepartureChecklistType)) {
      return kPostDepartureChecklistType;
    }

    return _checklistType;
  }

  String _definitionChecklistType(dynamic definition) {
    if (definition is! Map) return '';
    final raw =
        definition['checklistType'] ??
        definition['checklist_type'] ??
        definition['inspection_type'] ??
        definition['inspectionType'] ??
        definition['type'] ??
        '';
    return _normalizeChecklistType(raw.toString());
  }

  String _normalizeChecklistType(String raw) {
    final normalized = raw
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');

    switch (normalized) {
      case 'predeparture':
      case 'pre_trip':
      case 'prereturn':
        return kPreDepartureChecklistType;
      case 'post_return':
      case 'postreturn':
      case 'post_trip':
      case 'posttrip':
        return kPostDepartureChecklistType;
      default:
        return normalized;
    }
  }

  bool _looksLikeChecklistDefinition(Map<String, dynamic> map) {
    return map.containsKey('title') ||
        map.containsKey('name') ||
        map.containsKey('items') ||
        map.containsKey('checklist_items') ||
        map.containsKey('checklistItems') ||
        map.containsKey('type') ||
        map.containsKey('checklist_type');
  }

  String _definitionTitle(Map<String, dynamic> definition) {
    return (definition['title'] ??
            definition['name'] ??
            definition['label'] ??
            definition['text'] ??
            '')
        .toString();
  }

  List<Map<String, dynamic>> _definitionItems(dynamic definition) {
    if (definition is! Map) return const [];

    for (final key in const [
      'items',
      'checklist_items',
      'checklistItems',
      'inspection_items',
      'inspectionItems',
      'checks',
      'definitions',
    ]) {
      final value = definition[key];
      if (value is List) {
        return value
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      }
    }

    final nestedData = definition['data'];
    if (nestedData is List) {
      return nestedData
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    return const [];
  }

  Future<void> _loadAllocations() async {
    try {
      final results = await Future.wait<dynamic>([
        ApiService.fetchList(
          '/safari-allocations',
        ).catchError((_) => <dynamic>[]),
        ApiService.fetchList('/vehicles').catchError((_) => <dynamic>[]),
      ]);

      if (!mounted) return;

      final vehiclesById = <int, Map<String, dynamic>>{};
      for (final raw in (results[1] as List).cast<dynamic>()) {
        if (raw is! Map) continue;
        final vehicle = Map<String, dynamic>.from(raw);
        final vehicleId = int.tryParse((vehicle['id'] ?? '').toString());
        if (vehicleId != null) {
          vehiclesById[vehicleId] = vehicle;
        }
      }

      setState(() {
        _allocations = (results[0] as List).cast<dynamic>();
        _vehiclesById = vehiclesById;
      });

      if (_selectedLead != null) {
        _refreshLeadVehicles(preserveSelection: true);
      }
    } catch (_) {}
  }

  List<ChecklistItem> _buildItemsForType(
    String type, {
    List<dynamic>? sourceDefinitions,
  }) {
    final allDefinitions = sourceDefinitions ?? _checklistDefinitions;

    final definitions = allDefinitions.where((definition) {
      return _definitionChecklistType(definition) == type;
    }).toList();

    final definitionsToRender = definitions.isNotEmpty
        ? definitions
        : allDefinitions;

    definitionsToRender.sort((a, b) {
      final titleA = _definitionTitle(
        Map<String, dynamic>.from(a as Map),
      ).toLowerCase();
      final titleB = _definitionTitle(
        Map<String, dynamic>.from(b as Map),
      ).toLowerCase();
      return titleA.compareTo(titleB);
    });

    final items = <ChecklistItem>[];
    for (final definition in definitionsToRender) {
      final definitionMap = Map<String, dynamic>.from(definition as Map);
      final definitionItems = _definitionItems(definitionMap);
      if (definitionItems.isEmpty) {
        items.add(ChecklistItem.fromChecklistDefinition(definitionMap, null));
        continue;
      }

      final sortedItems = List<Map<String, dynamic>>.from(definitionItems)
        ..sort((a, b) {
          final sortA = a['sortOrder'] is int
              ? a['sortOrder'] as int
              : int.tryParse(
                      '${a['sortOrder'] ?? a['sort_order'] ?? a['order'] ?? 0}',
                    ) ??
                    0;
          final sortB = b['sortOrder'] is int
              ? b['sortOrder'] as int
              : int.tryParse(
                      '${b['sortOrder'] ?? b['sort_order'] ?? b['order'] ?? 0}',
                    ) ??
                    0;
          return sortA.compareTo(sortB);
        });

      for (final item in sortedItems) {
        items.add(ChecklistItem.fromChecklistDefinition(definitionMap, item));
      }
    }

    return items;
  }

  Future<void> _selectLead(Map<String, dynamic> lead) async {
    setState(() {
      _selectedLead = lead;
      _selectedVehicle = null;
    });
    await _refreshLeadVehicles();
  }

  Future<void> _refreshLeadVehicles({bool preserveSelection = false}) async {
    final lead = _selectedLead;
    if (lead == null) {
      if (!mounted) return;
      setState(() {
        _leadVehicles = [];
        _selectedVehicle = null;
        _vehicleLoading = false;
      });
      return;
    }

    final currentLeadKey = _leadKey(lead);
    final localVehicles = _availableVehiclesForLead(
      lead,
      sourceVehicles: _vehiclesFromLead(lead),
    );

    if (!mounted) return;
    setState(() {
      _leadVehicles = localVehicles;
      _selectedVehicle = _resolveVehicleSelection(
        localVehicles,
        preferred: preserveSelection ? _selectedVehicle : null,
      );
      _vehicleLoading = true;
    });

    try {
      final leadId = lead['id'] ?? lead['lead_id'];
      final vehicleResponse = await ApiService.get('/leads/$leadId/vehicle');
      final mergedVehicles = _mergeVehicleLists(
        localVehicles,
        _extractVehicles(vehicleResponse),
      );

      if (!mounted ||
          _selectedLead == null ||
          _leadKey(_selectedLead!) != currentLeadKey) {
        return;
      }

      final availableVehicles = _availableVehiclesForLead(
        _selectedLead!,
        sourceVehicles: mergedVehicles,
      );
      setState(() {
        _leadVehicles = availableVehicles;
        _selectedVehicle = _resolveVehicleSelection(
          availableVehicles,
          preferred: _selectedVehicle,
        );
        _vehicleLoading = false;
      });
    } catch (e) {
      if (!mounted ||
          _selectedLead == null ||
          _leadKey(_selectedLead!) != currentLeadKey) {
        return;
      }

      setState(() {
        _leadVehicles = localVehicles;
        _selectedVehicle = _resolveVehicleSelection(
          localVehicles,
          preferred: _selectedVehicle,
        );
        _vehicleLoading = false;
      });

      if (localVehicles.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load vehicle list: $e')),
        );
      }
    }
  }

  Map<String, dynamic>? _extractVehicle(dynamic payload) {
    if (payload is List && payload.isNotEmpty) {
      final first = payload.first;
      return first is Map<String, dynamic>
          ? first
          : Map<String, dynamic>.from(first as Map);
    }

    if (payload is Map<String, dynamic>) {
      for (final key in ['vehicle', 'data', 'item']) {
        final value = payload[key];
        if (value is Map<String, dynamic>) return value;
        if (value is List && value.isNotEmpty) {
          final first = value.first;
          if (first is Map<String, dynamic>) return first;
          if (first is Map) return Map<String, dynamic>.from(first);
        }
      }

      if (_looksLikeVehicle(payload)) return payload;
    }

    if (payload is Map) {
      final casted = Map<String, dynamic>.from(payload);
      if (_looksLikeVehicle(casted)) return casted;
    }

    return null;
  }

  List<Map<String, dynamic>> _extractVehicles(dynamic payload) {
    final vehicles = <Map<String, dynamic>>[];

    void collect(dynamic value) {
      if (value == null) return;

      if (value is List) {
        for (final entry in value) {
          collect(entry);
        }
        return;
      }

      if (value is Map<String, dynamic>) {
        final directVehicle = _extractVehicle(value);
        if (directVehicle != null) {
          vehicles.add(directVehicle);
          return;
        }

        for (final key in const ['vehicles', 'items', 'data', 'results']) {
          collect(value[key]);
        }
        return;
      }

      if (value is Map) {
        collect(Map<String, dynamic>.from(value));
      }
    }

    collect(payload);
    return _mergeVehicleLists(const <Map<String, dynamic>>[], vehicles);
  }

  Map<String, dynamic>? _vehicleFromLead(Map<String, dynamic> lead) {
    for (final key in ['vehicle', 'car']) {
      final value = lead[key];
      if (value is Map<String, dynamic>) return value;
      if (value is Map) return Map<String, dynamic>.from(value);
    }

    if (_looksLikeVehicle(lead)) {
      return {
        'make': lead['make'],
        'model': lead['model'],
        'plate_no': lead['plate_no'] ?? lead['plateNo'],
        'vehicle_no': lead['vehicle_no'] ?? lead['vehicleNo'],
      };
    }

    return null;
  }

  Map<String, dynamic>? _vehicleFromAllocation(Map<String, dynamic> lead) {
    final leadId = int.tryParse(
      (lead['id'] ?? lead['lead_id'] ?? '').toString(),
    );
    if (leadId == null) return null;

    for (final raw in _allocations.reversed) {
      if (raw is! Map) continue;
      final allocation = Map<String, dynamic>.from(raw);
      final allocationLeadId = int.tryParse(
        (allocation['lead_id'] ?? allocation['leadId'] ?? '').toString(),
      );
      if (allocationLeadId != leadId) continue;

      final embeddedVehicle = allocation['vehicle'];
      if (embeddedVehicle is Map<String, dynamic>) return embeddedVehicle;
      if (embeddedVehicle is Map) {
        return Map<String, dynamic>.from(embeddedVehicle);
      }

      final vehicleId = int.tryParse(
        (allocation['vehicle_id'] ?? allocation['vehicleId'] ?? '').toString(),
      );
      if (vehicleId != null && _vehiclesById.containsKey(vehicleId)) {
        return _vehiclesById[vehicleId];
      }
    }

    return null;
  }

  List<Map<String, dynamic>> _vehiclesFromLead(Map<String, dynamic> lead) {
    final vehicles = <Map<String, dynamic>>[];

    void addCandidate(dynamic raw) {
      if (raw == null) return;
      if (raw is List) {
        for (final entry in raw) {
          addCandidate(entry);
        }
        return;
      }

      if (raw is Map<String, dynamic>) {
        final nestedVehicle = _extractVehicle(raw);
        if (nestedVehicle != null) {
          vehicles.add(nestedVehicle);
          return;
        }

        if (_looksLikeVehicle(raw)) {
          vehicles.add(raw);
        }
        return;
      }

      if (raw is Map) {
        addCandidate(Map<String, dynamic>.from(raw));
      }
    }

    addCandidate(_vehicleFromLead(lead));
    addCandidate(_vehicleFromAllocation(lead));
    for (final key in const [
      'vehicles',
      'allocated_vehicles',
      'allocatedVehicles',
      'vehicle_list',
      'vehicleList',
      'safari_allocations',
      'allocations',
    ]) {
      addCandidate(lead[key]);
    }

    final allocatedVehicles = <Map<String, dynamic>>[];
    final leadId = int.tryParse(
      (lead['id'] ?? lead['lead_id'] ?? '').toString(),
    );
    if (leadId != null) {
      for (final raw in _allocations) {
        if (raw is! Map) continue;
        final allocation = Map<String, dynamic>.from(raw);
        final allocationLeadId = int.tryParse(
          (allocation['lead_id'] ?? allocation['leadId'] ?? '').toString(),
        );
        if (allocationLeadId != leadId) continue;

        final vehicle = _extractVehicle(allocation);
        if (vehicle != null) {
          allocatedVehicles.add(vehicle);
        }
      }
    }

    return _mergeVehicleLists(vehicles, allocatedVehicles);
  }

  List<Map<String, dynamic>> _mergeVehicleLists(
    List<Map<String, dynamic>> base,
    List<Map<String, dynamic>> extra,
  ) {
    final merged = <Map<String, dynamic>>[];
    final seen = <String>{};

    void addAll(List<Map<String, dynamic>> values) {
      for (final vehicle in values) {
        final key = _vehicleKey(vehicle);
        if (key.isEmpty || seen.add(key)) {
          merged.add(vehicle);
        }
      }
    }

    addAll(base);
    addAll(extra);
    return merged;
  }

  String _vehicleKey(Map<String, dynamic> vehicle) {
    final id =
        (vehicle['id'] ?? vehicle['vehicle_id'] ?? vehicle['vehicleId'] ?? '')
            .toString()
            .trim();
    if (id.isNotEmpty) return 'id:$id';

    final plate = (vehicle['plate_no'] ?? vehicle['plateNo'] ?? '')
        .toString()
        .trim()
        .toUpperCase();
    if (plate.isNotEmpty) return 'plate:$plate';

    final vehicleNo = (vehicle['vehicle_no'] ?? vehicle['vehicleNo'] ?? '')
        .toString()
        .trim()
        .toUpperCase();
    if (vehicleNo.isNotEmpty) return 'no:$vehicleNo';

    final make = (vehicle['make'] ?? '').toString().trim().toLowerCase();
    final model = (vehicle['model'] ?? '').toString().trim().toLowerCase();
    if (make.isNotEmpty || model.isNotEmpty) {
      return 'name:$make|$model';
    }

    return '';
  }

  String _inspectionVehicleKey(dynamic inspection) {
    if (inspection is! Map) return '';

    final vehicle = inspection['vehicle'];
    if (vehicle is Map<String, dynamic>) return _vehicleKey(vehicle);
    if (vehicle is Map) return _vehicleKey(Map<String, dynamic>.from(vehicle));

    final vehicleId =
        (inspection['vehicle_id'] ?? inspection['vehicleId'] ?? '')
            .toString()
            .trim();
    if (vehicleId.isNotEmpty) return 'id:$vehicleId';

    return '';
  }

  bool _looksLikeVehicle(Map<String, dynamic> data) {
    return data.containsKey('make') ||
        data.containsKey('model') ||
        data.containsKey('plate_no') ||
        data.containsKey('plateNo') ||
        data.containsKey('vehicle_no') ||
        data.containsKey('vehicleNo');
  }

  void _changeChecklistType(String type) {
    setState(() {
      _checklistType = type;
      _items = _mergeSubmittedValues(_buildItemsForType(type));
    });

    if (_selectedLead != null) {
      _refreshLeadVehicles(preserveSelection: true);
    }
  }

  String _leadKey(Map<String, dynamic> lead) {
    final id = (lead['id'] ?? lead['lead_id'] ?? '').toString();
    if (id.isNotEmpty) return id;

    final bookingRef = (lead['booking_ref'] ?? lead['bookingRef'] ?? '')
        .toString();
    final company = (lead['client_company'] ?? lead['clientCompany'] ?? '')
        .toString();
    return '$bookingRef|$company';
  }

  int? _inspectionIdValue(dynamic inspection) {
    if (inspection is! Map) return null;
    final raw = inspection['id'] ?? inspection['inspection_id'];
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '');
  }

  String _inspectionLeadKey(dynamic inspection) {
    if (inspection is! Map) return '';

    final lead = inspection['lead'];
    if (lead is Map<String, dynamic>) return _leadKey(lead);
    if (lead is Map) return _leadKey(Map<String, dynamic>.from(lead));

    final leadId = (inspection['lead_id'] ?? inspection['leadId'] ?? '')
        .toString();
    if (leadId.isNotEmpty) return leadId;

    return '';
  }

  String _inspectionTypeValue(dynamic inspection) {
    if (inspection is! Map) return '';
    final raw =
        inspection['checklistType'] ??
        inspection['checklist_type'] ??
        inspection['inspection_type'] ??
        inspection['inspectionType'] ??
        inspection['type'] ??
        '';
    return _normalizeChecklistType(raw.toString());
  }

  bool _isVehicleUnavailableForCurrentType(
    Map<String, dynamic> lead,
    Map<String, dynamic> vehicle,
  ) {
    final leadKey = _leadKey(lead);
    final vehicleKey = _vehicleKey(vehicle);
    if (leadKey.isEmpty || vehicleKey.isEmpty) return false;

    if (_checklistType == kPostDepartureChecklistType) {
      final hasPre = _hasInspectionFor(
        lead,
        vehicle,
        kPreDepartureChecklistType,
      );
      final hasPost = _hasInspectionFor(
        lead,
        vehicle,
        kPostDepartureChecklistType,
      );
      return !hasPre || hasPost;
    }

    for (final inspection in _existingInspections) {
      if (_inspectionTypeValue(inspection) != _checklistType) continue;
      if (_inspectionLeadKey(inspection) != leadKey) continue;
      if (_inspectionVehicleKey(inspection) != vehicleKey) continue;

      if (_isEditMode &&
          _inspectionIdValue(inspection) == widget.inspectionId) {
        continue;
      }

      return true;
    }

    return false;
  }

  bool _hasInspectionFor(
    Map<String, dynamic> lead,
    Map<String, dynamic> vehicle,
    String type,
  ) {
    final leadKey = _leadKey(lead);
    final vehicleKey = _vehicleKey(vehicle);
    if (leadKey.isEmpty || vehicleKey.isEmpty) return false;

    for (final inspection in _existingInspections) {
      if (_inspectionTypeValue(inspection) != type) continue;
      if (_inspectionLeadKey(inspection) != leadKey) continue;
      if (_inspectionVehicleKey(inspection) != vehicleKey) continue;

      if (_isEditMode &&
          _inspectionIdValue(inspection) == widget.inspectionId) {
        continue;
      }

      return true;
    }

    return false;
  }

  bool _canCreatePostForSelection() {
    final lead = _selectedLead;
    final vehicle = _selectedVehicle;
    if (lead == null || vehicle == null) return false;

    if (_isEditMode && _checklistType == kPostDepartureChecklistType) {
      return true;
    }

    final hasPre = _hasInspectionFor(lead, vehicle, kPreDepartureChecklistType);
    final hasPost = _hasInspectionFor(
      lead,
      vehicle,
      kPostDepartureChecklistType,
    );
    return hasPre && !hasPost;
  }

  String? _selectedLeadKey() {
    final selectedLead = _selectedLead;
    if (selectedLead == null) return null;

    final key = _leadKey(selectedLead);
    for (final lead in _leadOptions()) {
      if (_leadKey(lead) == key) return key;
    }

    return null;
  }

  String? _selectedVehicleKey() {
    final selectedVehicle = _selectedVehicle;
    if (selectedVehicle == null) return null;

    final key = _vehicleKey(selectedVehicle);
    for (final vehicle in _leadVehicles) {
      if (_vehicleKey(vehicle) == key) return key;
    }

    return null;
  }

  List<Map<String, dynamic>> _leadOptions() {
    final seen = <String>{};
    final leads = <Map<String, dynamic>>[];

    for (final raw in _leads) {
      if (raw is! Map) continue;
      final lead = Map<String, dynamic>.from(raw);
      final key = _leadKey(lead);
      if (seen.add(key)) {
        leads.add(lead);
      }
    }

    return leads;
  }

  List<Map<String, dynamic>> _availableLeadOptions() {
    return _leadOptions().where(_leadHasPendingChecklist).toList();
  }

  bool _leadHasPendingChecklist(Map<String, dynamic> lead) {
    final vehicles = _vehiclesFromLead(lead);

    // Keep leads visible when no vehicle can be resolved yet; this avoids
    // accidentally hiding leads due to partial payloads.
    if (vehicles.isEmpty) return true;

    for (final vehicle in vehicles) {
      final hasPre = _hasInspectionFor(
        lead,
        vehicle,
        kPreDepartureChecklistType,
      );
      final hasPost = _hasInspectionFor(
        lead,
        vehicle,
        kPostDepartureChecklistType,
      );

      // If either inspection is missing, this lead still has pending work.
      if (!hasPre || !hasPost) {
        return true;
      }
    }

    // All vehicles on this lead already completed both pre and post.
    return false;
  }

  String _leadLabel(Map<String, dynamic> lead) {
    final company = (lead['client_company'] ?? lead['clientCompany'] ?? 'Lead')
        .toString();
    final bookingRef = (lead['booking_ref'] ?? lead['bookingRef'] ?? '')
        .toString();
    final leadId = (lead['id'] ?? lead['lead_id'] ?? '').toString();
    final groupName = _groupNameByLeadId[leadId] ?? '';
    final parts = <String>[company];
    if (bookingRef.isNotEmpty) parts.add(bookingRef);
    if (groupName.isNotEmpty) parts.add(groupName);
    return parts.join(' · ');
  }

  void _selectLeadByKey(String key) {
    for (final lead in _leadOptions()) {
      if (_leadKey(lead) == key) {
        _selectLead(lead);
        return;
      }
    }
  }

  List<Map<String, dynamic>> _availableVehiclesForLead(
    Map<String, dynamic> lead, {
    List<Map<String, dynamic>>? sourceVehicles,
  }) {
    final vehicles = sourceVehicles ?? _vehiclesFromLead(lead);
    return vehicles
        .where((vehicle) => !_isVehicleUnavailableForCurrentType(lead, vehicle))
        .toList();
  }

  Map<String, dynamic>? _resolveVehicleSelection(
    List<Map<String, dynamic>> vehicles, {
    Map<String, dynamic>? preferred,
  }) {
    if (vehicles.isEmpty) return null;
    if (preferred != null) {
      final preferredKey = _vehicleKey(preferred);
      for (final vehicle in vehicles) {
        if (_vehicleKey(vehicle) == preferredKey) return vehicle;
      }
    }
    if (vehicles.length == 1) return vehicles.first;
    return null;
  }

  void _selectVehicleByKey(String key) {
    for (final vehicle in _leadVehicles) {
      if (_vehicleKey(vehicle) == key) {
        setState(() => _selectedVehicle = vehicle);
        return;
      }
    }
  }

  Future<void> _pickImages() async {
    try {
      final pickedFiles = await _imagePicker.pickMultiImage(
        imageQuality: 85,
        maxWidth: 1080,
        maxHeight: 1920,
      );

      if (pickedFiles.isNotEmpty) {
        setState(() {
          _imagePaths.addAll(pickedFiles.map((f) => f.path).toList());
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to pick images: $e')));
    }
  }

  Future<void> _takePhoto() async {
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1080,
        maxHeight: 1920,
      );

      if (image != null) {
        setState(() {
          _imagePaths.add(image.path);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to take photo: $e')));
    }
  }

  void _removeImage(int index) {
    setState(() {
      _imagePaths.removeAt(index);
    });
  }

  Future<void> _showValidationMessage(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.45),
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 32,
            vertical: 24,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.18),
                  blurRadius: 40,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Red accent top bar
                Container(
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Color(kRedAccent),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Icon circle
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: const Color(kRedAccent).withOpacity(0.10),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.error_outline_rounded,
                          color: Color(kRedAccent),
                          size: 34,
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Action Required',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Color(kDarkBg),
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          color: const Color(kDarkBg).withOpacity(0.65),
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 26),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(kGoldColor),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          child: const Text('Got it'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _submitChecklist() async {
    if (_submitting) {
      return;
    }

    if (_selectedLead == null || _selectedVehicle == null) {
      await _showValidationMessage('Please select a lead and vehicle');
      return;
    }

    if (_checklistType == kPostDepartureChecklistType &&
        !_canCreatePostForSelection()) {
      await _showValidationMessage(
        'You must submit the Pre checklist first for this vehicle before creating the Post checklist.',
      );
      return;
    }

    if (_items.isEmpty) {
      await _showValidationMessage('No checklist items available to submit');
      return;
    }

    if (_odometerCtrl.text.trim().isEmpty) {
      await _showValidationMessage('Please enter the odometer reading');
      return;
    }

    final incompleteItems = _items
        .where((item) => item.status != 'OK' && item.status != 'NOK')
        .toList();

    if (incompleteItems.isNotEmpty) {
      await _showValidationMessage('Please complete all checklist items');
      return;
    }

    final nokWithoutIssues = _items
        .where((item) => item.status == 'NOK' && item.issue.trim().isEmpty)
        .toList();

    if (nokWithoutIssues.isNotEmpty) {
      await _showValidationMessage(
        'Please fill issues for all NOK items: ${nokWithoutIssues.map((i) => i.name).join(", ")}',
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      final checklist = VehicleChecklist(
        type: _checklistType,
        lead: _selectedLead!,
        vehicle: _selectedVehicle!,
        odometer: _odometerCtrl.text.trim(),
        parkingLocation: _parkingLocationCtrl.text.trim(),
        items: _items,
        remarks: _remarksCtrl.text,
        imagePaths: _imagePaths,
      );

      int inspectionId;
      if (_isEditMode) {
        await ApiService.updateInspection(
          widget.inspectionId!,
          checklist.toJson(),
        );
        inspectionId = widget.inspectionId!;
      } else {
        final result = await ApiService.createInspection(checklist.toJson());
        final idVal = result['id'] ?? result['inspection']?['id'];
        inspectionId = idVal is int ? idVal : int.parse('$idVal');
      }

      final uploadedDbPaths = <String>[];
      for (final path in _imagePaths) {
        final uploadResult = await ApiService.uploadInspectionImage(
          inspectionId,
          path,
        );
        final storedPath = _extractUploadedImagePath(uploadResult);
        if (storedPath != null && storedPath.isNotEmpty) {
          uploadedDbPaths.add(storedPath);
        }
      }

      if (uploadedDbPaths.isNotEmpty) {
        checklist.imagePaths = uploadedDbPaths;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEditMode
                  ? 'Inspection updated successfully'
                  : 'Inspection submitted successfully',
            ),
          ),
        );
        widget.onSubmit(checklist);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to submit checklist: $e')));
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              children: [
                Container(
                  width: 52,
                  height: 5,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outline.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Vehicle Checklist',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Pre & Post-Departure Inspection',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                16,
                20,
                16,
                MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionHeading(theme, 'Select Lead'),
                  const SizedBox(height: 10),
                  _buildLeadDropdown(theme),
                  if (_selectedLead != null) ...[
                    const SizedBox(height: 12),
                    _buildLeadSummaryCard(theme),
                  ],
                  if (!_leadLoading && _availableLeadOptions().isEmpty) ...[
                    const SizedBox(height: 10),
                    _buildMessageCard(
                      theme,
                      message:
                          'No leads are currently available for inspection.',
                    ),
                  ],
                  if (_selectedLead != null) ...[
                    const SizedBox(height: 18),
                    _sectionHeading(theme, 'Vehicle'),
                    const SizedBox(height: 10),
                    _buildVehicleSection(theme),
                  ],
                  const SizedBox(height: 22),
                  _sectionHeading(theme, 'Checklist Type'),
                  const SizedBox(height: 10),
                  _buildChecklistTypeCards(theme),
                  const SizedBox(height: 12),
                  _buildChecklistInfoBanner(theme),
                  if (_checklistError != null) ...[
                    const SizedBox(height: 10),
                    _buildMessageCard(
                      theme,
                      message: 'Checklist API error: $_checklistError',
                      isError: true,
                    ),
                  ],
                  const SizedBox(height: 22),
                  _sectionHeading(theme, 'Odometer Reading'),
                  const SizedBox(height: 10),
                  _buildOdometerCard(theme),
                  const SizedBox(height: 22),
                  _sectionHeading(theme, 'Parking Location'),
                  const SizedBox(height: 10),
                  _buildParkingLocationCard(theme),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      _sectionHeading(theme, 'Checklist Items'),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF7F4),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${_items.length} Items',
                          style: TextStyle(
                            color: theme.colorScheme.secondary,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_checklistLoading)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: CircularProgressIndicator(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    )
                  else if (_items.isEmpty)
                    _buildMessageCard(
                      theme,
                      message:
                          'No checklist items found for ${checklistTypeLabel(_checklistType)}.',
                    )
                  else
                    ..._items.asMap().entries.map((entry) {
                      final index = entry.key;
                      final item = entry.value;
                      return _checklistItemWidget(item, index, theme);
                    }),
                  const SizedBox(height: 22),
                  _sectionHeading(theme, 'Remarks & Photos'),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _remarksCtrl,
                    maxLines: 5,
                    style: TextStyle(color: theme.colorScheme.onSurface),
                    decoration: InputDecoration(
                      hintText: 'Write any additional remarks or issues...',
                      hintStyle: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(
                          color: theme.colorScheme.outline.withOpacity(0.35),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(
                          color: theme.colorScheme.outline.withOpacity(0.35),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(
                          color: Color(kGoldColor),
                          width: 1.2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_existingImageUrls.isNotEmpty || _imagePaths.isNotEmpty)
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                      itemCount: _existingImageUrls.length + _imagePaths.length,
                      itemBuilder: (_, i) {
                        final isExisting = i < _existingImageUrls.length;
                        final localIndex = i - _existingImageUrls.length;

                        return Stack(
                          children: [
                            GestureDetector(
                              onTap: () => _showImagePreviewDialog(
                                context,
                                child: isExisting
                                    ? _InspectionImageTile(
                                        url: _existingImageUrls[i],
                                        headers: _imageHeaders,
                                        fit: BoxFit.contain,
                                      )
                                    : Image.file(
                                        File(_imagePaths[localIndex]),
                                        fit: BoxFit.contain,
                                      ),
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: theme.colorScheme.outline
                                        .withOpacity(0.35),
                                    width: 0.8,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(15),
                                  child: isExisting
                                      ? _InspectionImageTile(
                                          url: _existingImageUrls[i],
                                          headers: _imageHeaders,
                                        )
                                      : Image.file(
                                          File(_imagePaths[localIndex]),
                                          fit: BoxFit.cover,
                                        ),
                                ),
                              ),
                            ),
                            if (isExisting)
                              Positioned(
                                left: 6,
                                bottom: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.55),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'Saved',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            if (!isExisting)
                              Positioned(
                                top: -8,
                                right: -8,
                                child: CircleAvatar(
                                  backgroundColor: const Color(kRedAccent),
                                  radius: 14,
                                  child: GestureDetector(
                                    onTap: () => _removeImage(localIndex),
                                    child: const Icon(
                                      Icons.close,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _takePhoto,
                          icon: Icon(
                            Icons.camera_alt_outlined,
                            color: theme.colorScheme.secondary,
                          ),
                          label: Text(
                            'Take Photo',
                            style: TextStyle(
                              color: theme.colorScheme.secondary,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: theme.colorScheme.secondary.withOpacity(
                                0.35,
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickImages,
                          icon: Icon(
                            Icons.add_photo_alternate_outlined,
                            color: theme.colorScheme.secondary,
                          ),
                          label: Text(
                            'Gallery',
                            style: TextStyle(
                              color: theme.colorScheme.secondary,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: theme.colorScheme.secondary.withOpacity(
                                0.35,
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 90),
                ],
              ),
            ),
          ),
          _buildFooter(theme),
        ],
      ),
    );
  }

  Widget _vehicleDetailsCard(ThemeData theme) {
    if (_selectedVehicle == null) return const SizedBox();

    final make = _selectedVehicle!['make'] ?? '-';
    final model = _selectedVehicle!['model'] ?? '';
    final plate =
        _selectedVehicle!['plate_no'] ?? _selectedVehicle!['plateNo'] ?? '-';
    final vehicleNo =
        _selectedVehicle!['vehicle_no'] ?? _selectedVehicle!['vehicleNo'] ?? '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outline, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFEAF7F4), Color(0xFFFFFFFF)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.directions_car_outlined,
                  color: theme.colorScheme.secondary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '$make $model',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _detailChip(plate, Icons.confirmation_number_outlined, theme),
              if (vehicleNo.isNotEmpty)
                _detailChip('#$vehicleNo', Icons.pin_outlined, theme),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionHeading(ThemeData theme, String title) {
    return Text(
      title.toUpperCase(),
      style: theme.textTheme.labelLarge?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.5,
      ),
    );
  }

  void _showLeadSearchSheet() {
    final allLeads = _availableLeadOptions();
    final searchCtrl = TextEditingController();
    var filtered = List<Map<String, dynamic>>.from(allLeads);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            void onSearch(String query) {
              final q = query.toLowerCase();
              setSheetState(() {
                filtered = q.isEmpty
                    ? List.from(allLeads)
                    : allLeads.where((lead) {
                        return _leadLabel(lead).toLowerCase().contains(q);
                      }).toList();
              });
            }

            return DraggableScrollableSheet(
              initialChildSize: 0.75,
              minChildSize: 0.4,
              maxChildSize: 0.95,
              expand: false,
              builder: (_, scrollCtrl) {
                return Container(
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.surface,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Theme.of(
                            ctx,
                          ).colorScheme.onSurface.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TextField(
                          controller: searchCtrl,
                          autofocus: true,
                          onChanged: onSearch,
                          decoration: InputDecoration(
                            hintText: 'Search leads...',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: searchCtrl.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      searchCtrl.clear();
                                      onSearch('');
                                    },
                                  )
                                : null,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: filtered.isEmpty
                            ? Center(
                                child: Text(
                                  'No leads found',
                                  style: TextStyle(
                                    color: Theme.of(
                                      ctx,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                controller: scrollCtrl,
                                itemCount: filtered.length,
                                itemBuilder: (_, i) {
                                  final lead = filtered[i];
                                  final leadId =
                                      (lead['id'] ?? lead['lead_id'] ?? '')
                                          .toString();
                                  final company =
                                      (lead['client_company'] ??
                                              lead['clientCompany'] ??
                                              'Lead')
                                          .toString();
                                  final bookingRef =
                                      (lead['booking_ref'] ??
                                              lead['bookingRef'] ??
                                              '')
                                          .toString();
                                  final groupName =
                                      _groupNameByLeadId[leadId] ?? '';
                                  final isSelected =
                                      _selectedLeadKey() == _leadKey(lead);
                                  return ListTile(
                                    selected: isSelected,
                                    selectedColor: Theme.of(
                                      ctx,
                                    ).colorScheme.primary,
                                    title: Text(
                                      company,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Row(
                                      children: [
                                        if (bookingRef.isNotEmpty) ...[
                                          const Icon(
                                            Icons.confirmation_number_outlined,
                                            size: 13,
                                          ),
                                          const SizedBox(width: 3),
                                          Text(bookingRef),
                                        ],
                                        if (bookingRef.isNotEmpty &&
                                            groupName.isNotEmpty)
                                          const Text('  ·  '),
                                        if (groupName.isNotEmpty) ...[
                                          const Icon(
                                            Icons.group_outlined,
                                            size: 13,
                                          ),
                                          const SizedBox(width: 3),
                                          Flexible(child: Text(groupName)),
                                        ],
                                      ],
                                    ),
                                    trailing: isSelected
                                        ? Icon(
                                            Icons.check_circle,
                                            color: Theme.of(
                                              ctx,
                                            ).colorScheme.primary,
                                          )
                                        : null,
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      _selectLeadByKey(_leadKey(lead));
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildLeadDropdown(ThemeData theme) {
    if (_leadLoading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: CircularProgressIndicator(color: theme.colorScheme.primary),
        ),
      );
    }

    final selected = _selectedLead;
    final leadId = selected != null
        ? (selected['id'] ?? selected['lead_id'] ?? '').toString()
        : '';
    final groupName = leadId.isNotEmpty
        ? (_groupNameByLeadId[leadId] ?? '')
        : '';

    return GestureDetector(
      onTap: _showLeadSearchSheet,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: theme.colorScheme.outline.withOpacity(0.35),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: selected == null
                  ? Text(
                      'Choose a lead...',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          (selected['client_company'] ??
                                  selected['clientCompany'] ??
                                  'Lead')
                              .toString(),
                          style: TextStyle(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if ((selected['booking_ref'] ??
                                    selected['bookingRef'] ??
                                    '')
                                .toString()
                                .isNotEmpty) ...[
                              Icon(
                                Icons.confirmation_number_outlined,
                                size: 12,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                (selected['booking_ref'] ??
                                        selected['bookingRef'] ??
                                        '')
                                    .toString(),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                            if ((selected['booking_ref'] ??
                                        selected['bookingRef'] ??
                                        '')
                                    .toString()
                                    .isNotEmpty &&
                                groupName.isNotEmpty)
                              Text(
                                '  ·  ',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            if (groupName.isNotEmpty) ...[
                              Icon(
                                Icons.group_outlined,
                                size: 12,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  groupName,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
            ),
            Icon(
              Icons.search,
              color: theme.colorScheme.onSurfaceVariant,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeadSummaryCard(ThemeData theme) {
    final lead = _selectedLead!;
    final bookingRef = (lead['booking_ref'] ?? lead['bookingRef'] ?? '-')
        .toString();
    final company = (lead['client_company'] ?? lead['clientCompany'] ?? 'Lead')
        .toString();
    final vehicleCount = _leadVehicles.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF7F4),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.business_center_outlined,
              color: theme.colorScheme.secondary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  company,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Lead reference',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _detailChip(
                      bookingRef,
                      Icons.confirmation_number_outlined,
                      theme,
                    ),
                    _detailChip(
                      '$vehicleCount vehicle${vehicleCount == 1 ? '' : 's'}',
                      Icons.directions_car_outlined,
                      theme,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleSection(ThemeData theme) {
    if (_vehicleLoading && _leadVehicles.isEmpty) {
      return _buildMessageCard(
        theme,
        message: 'Loading vehicles assigned to this lead...',
        isLoading: true,
      );
    }

    if (_leadVehicles.isEmpty) {
      return _buildMessageCard(
        theme,
        message:
            'No available vehicle was found for this lead and checklist type.',
      );
    }

    return Column(
      children: _leadVehicles.map((vehicle) {
        final isSelected = _selectedVehicleKey() == _vehicleKey(vehicle);
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GestureDetector(
            onTap: () => _selectVehicleByKey(_vehicleKey(vehicle)),
            child: _vehicleOptionCard(theme, vehicle, isSelected: isSelected),
          ),
        );
      }).toList(),
    );
  }

  Widget _vehicleOptionCard(
    ThemeData theme,
    Map<String, dynamic> vehicle, {
    required bool isSelected,
  }) {
    final make = (vehicle['make'] ?? 'Vehicle').toString();
    final model = (vehicle['model'] ?? '').toString();
    final plate = (vehicle['plate_no'] ?? vehicle['plateNo'] ?? '-').toString();
    final vehicleNo = (vehicle['vehicle_no'] ?? vehicle['vehicleNo'] ?? '')
        .toString();
    final normalizedPlate = plate.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]'),
      '',
    );
    final normalizedVehicleNo = vehicleNo.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]'),
      '',
    );
    final showVehicleNoChip =
        vehicleNo.isNotEmpty && normalizedVehicleNo != normalizedPlate;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isSelected
              ? const Color(kGoldColor)
              : theme.colorScheme.outline.withOpacity(0.25),
          width: isSelected ? 1.4 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFF6FBF9), Color(0xFFFFFFFF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              Icons.directions_car_filled_outlined,
              color: theme.colorScheme.secondary,
              size: 30,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$make $model'.trim(),
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isSelected
                      ? 'Selected vehicle'
                      : 'Tap to choose this vehicle',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _detailChip(
                      plate,
                      Icons.confirmation_number_outlined,
                      theme,
                    ),
                    if (showVehicleNoChip)
                      _detailChip('#$vehicleNo', Icons.pin_outlined, theme),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isSelected
                  ? theme.colorScheme.secondary
                  : Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected
                    ? theme.colorScheme.secondary
                    : theme.colorScheme.outline.withOpacity(0.5),
              ),
            ),
            child: isSelected
                ? const Icon(Icons.check, color: Colors.white, size: 18)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildChecklistTypeCards(ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: _typeOptionCard(
            theme,
            title: 'Pre-Departure',
            subtitle: 'Before vehicle is used',
            icon: Icons.directions_car_filled_outlined,
            selected: _checklistType == kPreDepartureChecklistType,
            onTap: () => _changeChecklistType(kPreDepartureChecklistType),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _typeOptionCard(
            theme,
            title: 'Post-Departure',
            subtitle: 'After vehicle is returned',
            icon: Icons.assignment_turned_in_outlined,
            selected: _checklistType == kPostDepartureChecklistType,
            onTap: () => _changeChecklistType(kPostDepartureChecklistType),
          ),
        ),
      ],
    );
  }

  Widget _typeOptionCard(
    ThemeData theme, {
    required String title,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? const Color(kGoldColor)
                : theme.colorScheme.outline.withOpacity(0.25),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: selected
                  ? const Color(kGoldColor)
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChecklistInfoBanner(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF1FBF8), Color(0xFFEAF8F4)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: theme.colorScheme.secondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _checklistLoading
                  ? 'Loading checklist items from API...'
                  : '${_items.length} checklist item(s) loaded from ${_checklistDefinitions.length} checklist definition(s)',
              style: TextStyle(
                color: theme.colorScheme.secondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOdometerCard(ThemeData theme) {
    final isPreDeparture = _checklistType == kPreDepartureChecklistType;
    final title = isPreDeparture ? 'Odometer Out' : 'Odometer In';
    final subtitle = isPreDeparture
        ? 'Record at start of trip'
        : 'Record after vehicle return';

    Widget odometerField() {
      return TextField(
        controller: _odometerCtrl,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        textAlign: TextAlign.right,
        decoration: InputDecoration(
          hintText: 'Enter odometer',
          suffixText: 'km',
          filled: true,
          fillColor: const Color(0xFFFFFCF4),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(kGoldColor)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(kGoldColor), width: 0.8),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(kGoldColor), width: 1.2),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.25)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 430;
          final header = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF7F4),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.speed_outlined,
                  color: theme.colorScheme.secondary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                header,
                const SizedBox(height: 16),
                SizedBox(width: double.infinity, child: odometerField()),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(flex: 5, child: header),
              const SizedBox(width: 14),
              Expanded(flex: 4, child: odometerField()),
            ],
          );
        },
      ),
    );
  }

  Widget _buildParkingLocationCard(ThemeData theme) {
    final hint = _checklistType == kPreDepartureChecklistType
        ? 'Where will this vehicle be parked after return?'
        : 'Confirm where this vehicle is now parked';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF7F4),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.local_parking_outlined,
              color: theme.colorScheme.secondary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: TextField(
              controller: _parkingLocationCtrl,
              decoration: InputDecoration(
                labelText: 'Parking location',
                hintText: hint,
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: theme.colorScheme.outline.withOpacity(0.25),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: theme.colorScheme.outline.withOpacity(0.25),
                  ),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(16)),
                  borderSide: BorderSide(color: Color(kGoldColor), width: 1.2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(ThemeData theme) {
    final completedCount = _items
        .where((item) => item.status == 'OK' || item.status == 'NOK')
        .length;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 24,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Container(
              width: 88,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: theme.colorScheme.outline.withOpacity(0.3),
                        width: 4,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$completedCount/${_items.length}',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Items Checked',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _submitting ? null : _submitChecklist,
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : Icon(_isEditMode ? Icons.save_outlined : Icons.save_alt),
                label: Text(
                  _submitting
                      ? (_isEditMode ? 'Updating...' : 'Submitting...')
                      : (_isEditMode ? 'Update Checklist' : 'Save Checklist'),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(kGoldColor),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageCard(
    ThemeData theme, {
    required String message,
    bool isError = false,
    bool isLoading = false,
  }) {
    final borderColor = isError
        ? const Color(kRedAccent).withOpacity(0.25)
        : theme.colorScheme.outline.withOpacity(0.25);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          if (isLoading)
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            )
          else
            Icon(
              isError ? Icons.error_outline : Icons.info_outline,
              color: isError
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurfaceVariant,
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: isError
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailChip(String value, IconData icon, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outline, width: 0.6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _checklistItemWidget(ChecklistItem item, int index, ThemeData theme) {
    final showSectionHeader =
        item.checklistTitle.isNotEmpty &&
        (index == 0 || _items[index - 1].checklistId != item.checklistId);
    final isOk = item.status == 'OK';
    final isNok = item.status == 'NOK';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isNok
              ? const Color(kRedAccent).withOpacity(0.28)
              : isOk
              ? const Color(kTealColor).withOpacity(0.28)
              : theme.colorScheme.outline.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showSectionHeader) ...[
            Text(
              item.checklistTitle,
              style: TextStyle(
                color: theme.colorScheme.secondary,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF7F4),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  _checklistItemIcon(item.name),
                  color: theme.colorScheme.secondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Mark this item as OK or NOK.',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _statusButton(
                  theme,
                  label: 'OK',
                  icon: Icons.check_circle_outline,
                  selected: isOk,
                  selectedColor: const Color(kTealColor),
                  onTap: () {
                    setState(() {
                      _items[index].status = 'OK';
                      _items[index].issue = '';
                    });
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _statusButton(
                  theme,
                  label: 'NOK',
                  icon: Icons.close,
                  selected: isNok,
                  selectedColor: const Color(kRedAccent),
                  onTap: () {
                    setState(() {
                      _items[index].status = 'NOK';
                    });
                  },
                ),
              ),
            ],
          ),
          if (item.status == 'NOK') ...[
            const SizedBox(height: 12),
            TextFormField(
              key: ValueKey('issue-${item.id}-${item.status}'),
              initialValue: item.issue,
              onChanged: (value) {
                setState(() {
                  _items[index].issue = value;
                });
              },
              maxLines: 3,
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 13,
              ),
              decoration: InputDecoration(
                hintText: 'Describe the issue...',
                hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                filled: true,
                fillColor: const Color(0xFFFFF6F4),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: const Color(kRedAccent).withOpacity(0.35),
                    width: 1,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: const Color(kRedAccent).withOpacity(0.35),
                    width: 0.8,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: Color(kRedAccent),
                    width: 1.2,
                  ),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusButton(
    ThemeData theme, {
    required String label,
    required IconData icon,
    required bool selected,
    required Color selectedColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? selectedColor : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? selectedColor
                : theme.colorScheme.outline.withOpacity(0.3),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected
                  ? Colors.white
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : theme.colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _checklistItemIcon(String label) {
    final lower = label.toLowerCase();
    if (lower.contains('wind') || lower.contains('wiper')) {
      return Icons.cleaning_services_outlined;
    }
    if (lower.contains('mirror')) {
      return Icons.crop_square_outlined;
    }
    if (lower.contains('light') || lower.contains('head')) {
      return Icons.lightbulb_outline;
    }
    if (lower.contains('fluid') ||
        lower.contains('oil') ||
        lower.contains('washer')) {
      return Icons.opacity_outlined;
    }
    if (lower.contains('tire') || lower.contains('wheel')) {
      return Icons.tire_repair_outlined;
    }
    return Icons.fact_check_outlined;
  }
}
