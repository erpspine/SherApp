import 'package:flutter/material.dart';
import '../config/app_config.dart';

class PaginationFooter extends StatelessWidget {
  final int currentPage;
  final int lastPage;
  final bool loadingMore;
  final VoidCallback onLoadMore;

  const PaginationFooter({
    super.key,
    required this.currentPage,
    required this.lastPage,
    required this.loadingMore,
    required this.onLoadMore,
  });

  @override
  Widget build(BuildContext context) {
    if (currentPage >= lastPage) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
      child: OutlinedButton.icon(
        onPressed: loadingMore ? null : onLoadMore,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(kDarkBorder)),
          foregroundColor: const Color(kGoldColor),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        icon: loadingMore
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.expand_more),
        label: Text('Load more (${currentPage + 1}/$lastPage)'),
      ),
    );
  }
}
