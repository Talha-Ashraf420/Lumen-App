import 'package:flutter/foundation.dart';
import 'catalog_cache.dart';
import 'epg_cache.dart';

/// Bumped whenever the user refreshes content. Screens that cache catalog data
/// (Home, Search) listen to this and re-fetch.
final ValueNotifier<int> contentRefresh = ValueNotifier<int>(0);

/// Clear cached catalogs/EPG and signal screens to reload.
void refreshContent() {
  CatalogCache.instance.clear();
  EpgCache.instance.clear();
  contentRefresh.value++;
}
