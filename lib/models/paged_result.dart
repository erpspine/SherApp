class PagedResult {
  final List<dynamic> items;
  final int currentPage;
  final int lastPage;
  final int perPage;
  final int total;
  final bool fromCache;

  const PagedResult({
    required this.items,
    required this.currentPage,
    required this.lastPage,
    required this.perPage,
    required this.total,
    this.fromCache = false,
  });

  bool get hasMore => currentPage < lastPage;
}
