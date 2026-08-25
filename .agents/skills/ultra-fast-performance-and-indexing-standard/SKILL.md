---
name: ultra-fast-performance-and-indexing-standard
description: Mandatory architectural standard for 60fps ultra-fast UI performance, lazy on-demand tab loading, RepaintBoundary animation isolation, server-side scoped Firestore queries, O(1) memoized computation caching, and composite indexing in Flutter & Firebase.
version: 1.0.0
---

# Ultra-Fast Performance, Lazy Loading & Firestore Indexing Standard (معيار السرعة الفائقة والتحميل الكسول وفهرسة الاستعلامات)

This skill defines the **mandatory 5-layer architectural and performance standard** for building ultra-fast, responsive, and resource-efficient applications across Flutter (Web, Desktop, Mobile) and Google Cloud Firestore.

Whenever developing, modifying, or reviewing any portal, dashboard, reporting screen, data table, or real-time query in the project, you **MUST strictly follow these 5 mandatory performance pillars**.

---

## 🏛️ The 5 Mandatory Performance Pillars (البنود الخمسة القياسية للأداء الفائق)

```
[ منظومة الأداء والسرعة الفائقة الشاملة ]
├── 1. التحميل الكسول المخصص (Lazy On-Demand Tab Loading + Offstage Caching)
├── 2. عزل إطارات الأنيميشن والقوائم (RepaintBoundary Isolation for 60 FPS)
├── 3. الفلترة السحابية المباشرة من السيرفر (Server-Side Scoped Firestore Queries)
├── 4. التخزين المؤقت للحسابات الثقيلة (O(1) Memoized Computation Caching)
└── 5. الفهارس السحابية المركبة (Google Cloud Firestore Composite Indexing)
```

---

### 1️⃣ Pillar 1: Lazy On-Demand Tab Loading with Offstage Caching (التحميل الكسول عند الطلب)
* **The Anti-Pattern (ما يُمنع منعاً باتاً):**
  - Using standard `IndexedStack` to mount multiple heavy screens simultaneously. `IndexedStack` executes `build()`, initializes state, and opens real-time Firestore `.snapshots()` streams for **ALL children on frame 0**, wasting CPU, memory, and network bandwidth for tabs the user has not visited.
* **The Mandatory Standard (المعيار المعتمد):**
  - Track visited tabs using `final Set<int> _loadedTabs = {0};`.
  - Use a high-performance `Stack` with `Offstage` + `TickerMode(enabled: _selectedTab == i)`.
  - Only construct and mount a tab widget when its index exists in `_loadedTabs`.
  - Keep visited tabs cached in memory so scroll position and form inputs are preserved without re-mounting.
  - Disable tickers and background animations on inactive tabs (`TickerMode(enabled: false)`).

```dart
// Standard Implementation Pattern:
Stack(
  fit: StackFit.expand,
  children: [
    for (int i = 0; i < tabCount; i++)
      Offstage(
        offstage: _selectedTab != i,
        child: TickerMode(
          enabled: _selectedTab == i,
          child: _loadedTabs.contains(i)
              ? _buildTabContent(tabIndex: i, ...)
              : const SizedBox.shrink(),
        ),
      ),
  ],
)
```

---

### 2️⃣ Pillar 2: `RepaintBoundary` Isolation for 60 FPS Animations (عزل إطارات الرسم)
* **The Anti-Pattern:**
  - Animating sidebars (`AnimatedContainer`), drawers, or headers without isolating them from the main viewport, forcing Flutter to rasterize and repaint complex charts, KPI cards, and data tables on every frame of the animation.
* **The Mandatory Standard:**
  - Wrap collapsible sidebars, bottom sheets, floating toolbars, and heavy content views inside independent `RepaintBoundary` widgets.
  - Guarantees constant **60 FPS** smooth transitions with zero frame drops or UI stutter during collapse/expand interactions.

```dart
Row(
  children: [
    if (!isMobile)
      RepaintBoundary(
        child: _buildDesktopSidebar(...),
      ),
    Expanded(
      child: RepaintBoundary(
        child: _buildMainContentView(...),
      ),
    ),
  ],
)
```

---

### 3️⃣ Pillar 3: Server-Side Scoped Firestore Querying (`.where()`) (الفلترة السحابية المباشرة)
* **The Anti-Pattern:**
  - Streaming entire database collections (`firestore.collection('receipts_transactions').snapshots()`) and filtering docs on the client side using `.where((doc) => doc['companySlug'] == slug)`. This transfers megabytes of unneeded raw data and OCR text over the network.
* **The Mandatory Standard:**
  - Filter by company, event, or tenant directly on the server before data leaves Google Cloud:
    ```dart
    Query query = firestore.collection('receipts_transactions');
    if (campaignId != null && campaignId != 'all') {
      query = query.where('campaignId', isEqualTo: campaignId);
    } else if (companySlug.isNotEmpty) {
      query = query.where('companySlug', isEqualTo: companySlug);
    }
    ```
  - Reduces network payload, memory footprint, and initialization latency by **>85%**.

---

### 4️⃣ Pillar 4: O(1) Memoized Aggregation & Computation Caching (تخزين الحسابات الثقيلة)
* **The Anti-Pattern:**
  - Running synchronous heavy loops, branch normalization regexes, item aggregations, and sorting algorithms (`.sort()`) directly inside `build()` or `builder()` callbacks on every frame, scroll event, or hover action.
* **The Mandatory Standard:**
  - Encapsulate calculation results in an immutable data structure (e.g. `_ReportAggregationResult`).
  - Cache results using lightweight cache keys (`${docs.length}_${firstDocId}_${filterState}`).
  - Return the cached instance in **O(1) time (0.001 ms)** during rebuilds. Only recompute when the underlying Firestore document snapshot hash or user filter actually changes.

```dart
_ReportAggregationResult _computeMetrics({
  required List<QueryDocumentSnapshot> transactions,
  required String sortBy,
  required bool filterCompanyOnly,
}) {
  final firstId = transactions.isNotEmpty ? transactions.first.id : '';
  final lastId = transactions.isNotEmpty ? transactions.last.id : '';
  final cacheKey = '${transactions.length}_${firstId}_${lastId}_${sortBy}_$filterCompanyOnly';

  if (_cachedMetrics != null && _lastMetricsCacheKey == cacheKey) {
    return _cachedMetrics!; // O(1) Instant Return
  }

  // Execute heavy loops only on genuine data update
  ...
  _cachedMetrics = _ReportAggregationResult(...);
  _lastMetricsCacheKey = cacheKey;
  return _cachedMetrics!;
}
```

---

### 5️⃣ Pillar 5: Google Cloud Firestore Composite Indexing (فهارس الفايربيز المركبة)
* **The Mandatory Standard:**
  - All compound queries combining equality filters with inequality or sort orders (`.where('companySlug', isEqualTo: ...).orderBy('createdAt', descending: true)`) MUST be declared in [firestore.indexes.json](file:///Users/fathalla/Development/Tashil%20Gift/firestore.indexes.json) and linked in [firebase.json](file:///Users/fathalla/Development/Tashil%20Gift/firebase.json).
  - Ensures queries return in single-digit milliseconds directly from Google Cloud index trees.

```json
{
  "indexes": [
    {
      "collectionGroup": "receipts_transactions",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "companySlug", "order": "ASCENDING" },
        { "fieldPath": "createdAt", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "receipts_transactions",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "campaignId", "order": "ASCENDING" },
        { "fieldPath": "createdAt", "order": "DESCENDING" }
      ]
    }
  ]
}
```

---

## 🛑 Golden Invariants Summary (ملخص الثوابت الذهبية)
1. **No Unbounded Eager Stacks**: Always use lazy `_loadedTabs` for multi-tab portals.
2. **Zero Animation Jank**: Always wrap animated sidebars and viewports in `RepaintBoundary`.
3. **No Un-Scoped Full Collection Streams**: Always use server-side `.where()` for tenant data.
4. **No Heavy Loops in `build()`**: Always memoize aggregations with O(1) cache keys.
5. **Declared Composite Indexes**: Always define composite indexes in `firestore.indexes.json`.
