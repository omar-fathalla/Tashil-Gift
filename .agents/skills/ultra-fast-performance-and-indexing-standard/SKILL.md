---
name: ultra-fast-performance-and-indexing-standard
description: Mandatory architectural standard for 60fps ultra-fast UI performance, lazy on-demand tab loading, RepaintBoundary animation isolation, server-side scoped Firestore queries, O(1) persistent in-memory computation caching, zero-wipe invariants, stream memoization outside build(), and composite indexing in Flutter & Firebase.
version: 2.0.0
---

# Ultra-Fast Performance, Lazy Loading & Firestore Indexing Standard (معيار السرعة الفائقة والتحميل الكسول وفهرسة الاستعلامات)

This skill defines the **mandatory 7-pillar architectural and performance standard** for building ultra-fast, responsive, and resource-efficient applications across Flutter (Web, Desktop, Mobile) and Google Cloud Firestore.

Whenever developing, modifying, or reviewing any portal, dashboard, reporting screen, data table, or real-time query in the project, you **MUST strictly follow these 7 mandatory performance pillars**.

---

## 🏛️ The 7 Mandatory Performance Pillars (البنود السبعة القياسية للأداء الفائق)

```
[ منظومة الأداء والسرعة الفائقة الشاملة ]
├── 1. التحميل الكسول المخصص (Lazy On-Demand Tab Loading + Offstage Caching)
├── 2. عزل إطارات الأنيميشن والقوائم (RepaintBoundary Isolation for 60 FPS)
├── 3. الفلترة السحابية المباشرة من السيرفر (Server-Side Scoped Firestore Queries)
├── 4. التخزين المؤقت المستمر في الذاكرة (Stale-While-Revalidate Persistent In-Memory Caching & Zero-Wipe Invariant)
├── 5. تثبيت تدفقات الفايربيز خارج البناء (Stream Lifecycle Memoization Outside build())
├── 6. المطابقة المعيارية للأحرف العربية (Multi-Variant Arabic Normalization & Event Attribution)
└── 7. الفهارس السحابية المركبة (Google Cloud Firestore Composite Indexing)
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
  - Use stable portal tab keys (e.g. `'1-comparison-$effectiveSlug'`) for screens that aggregate portfolio-wide data, so changing a single-campaign header filter does not needlessly destroy and remount cross-campaign comparison screens.

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

### 4️⃣ Pillar 4: Stale-While-Revalidate Persistent In-Memory Caching & Zero-Wipe Invariant (الذاكرة المستمرة ومنع تصفير الكاش)
* **The Anti-Pattern:**
  - Storing calculation results solely in transient State variables (`_cachedMetrics`) that get wiped when navigating to another tab or rebuilding the widget.
  - Clearing cache (`_metricsCache.clear()`) when receiving an empty snapshot during stream reconnection, causing KPI cards and chart bars to flash `0` or disappear.
* **The Mandatory Standard:**
  - Maintain **static persistent in-memory caches** keyed by tenant/company:
    ```dart
    static final Map<String, Map<String, CampaignMetricsSummary>> _persistentMetricsCache = {};
    static final Map<String, List<EventModel>> _persistentEventsCache = {};
    static final Map<String, List<QueryDocumentSnapshot>> _persistentInvoicesCache = {};
    static final Map<String, String> _savedCampaignA = {};
    static final Map<String, String> _savedCampaignB = {};
    static final Map<String, ComparisonDimension> _savedDimension = {};
    ```
  - **Zero-Latency Instant Render (0ms)**: When opening a screen or returning from another tab, render immediately from `_persistentMetricsCache` or `_persistentEventsCache`. Never display a full-screen loading spinner (`CircularProgressIndicator`) when cached data exists.
  - **Zero-Wipe Invariant**: When an incoming Firestore snapshot is empty or waiting, NEVER wipe existing valid cached data:
    ```dart
    final cached = _persistentMetricsCache[slug];
    if (invoiceDocs.isEmpty && cached != null && cached.isNotEmpty) {
      return cached; // Retain existing valid metrics!
    }
    ```
  - **Silent Background Sync**: Fresh Firestore snapshots seamlessly update the persistent cache and trigger a quiet redraw without UI flicker.

---

### 5️⃣ Pillar 5: Stream Lifecycle Memoization Outside `build()` (تثبيت الـ Streams ومنع إعادة الاشتراك)
* **The Anti-Pattern:**
  - Calling `.snapshots()` directly inside the `build()` or `builder()` methods. Every local UI update (e.g. clicking a `ChoiceChip`, switching a `SegmentedButton`, hovering or scrolling) calls `setState()`, forcing `StreamBuilder` to cancel the existing Firestore subscription, wait, and open a new subscription, resulting in temporary empty states or stream lag.
* **The Mandatory Standard:**
  - Hold `Stream<QuerySnapshot>?` instances on the State object and initialize them via an idempotent helper:
    ```dart
    Stream<QuerySnapshot>? _eventsStream;
    Stream<QuerySnapshot>? _transactionsStream;
    String? _lastStreamCompanySlug;

    void _ensureStreams(FirebaseFirestore firestore) {
      final slug = widget.lockedCompanySlug;
      if (_eventsStream != null && _lastStreamCompanySlug == slug) return;
      _lastStreamCompanySlug = slug;
      _eventsStream = firestore.collection('events').where('companySlug', isEqualTo: slug).snapshots();
      _transactionsStream = firestore.collection('receipts_transactions').where('companySlug', isEqualTo: slug).snapshots();
    }
    ```
  - Inside `build()`, invoke `_ensureStreams(activeFirestore);` and pass the memoized streams to `StreamBuilder`. Switching dimensions or filter chips now executes in **0.001 ms** without touching network streams!

---

### 6️⃣ Pillar 6: Multi-Variant Arabic Title & Phonetic Normalization (المطابقة المعيارية للأحرف العربية)
* **The Anti-Pattern:**
  - Matching campaign receipts purely on exact string equality (`inv['eventName'] == event.eventName`). POS systems, promoters, and OCR outputs frequently vary in Arabic Alef forms (`أ / إ / آ`), Teh Marbuta (`ة / ه`), Tashkeel diacritics, and dashes (`-` vs `–` vs `—`), causing valid receipts to be dropped and campaign values to fall to `0`.
* **The Mandatory Standard:**
  - Normalize Arabic strings before indexing and comparison:
    ```dart
    static String normalizeTitle(String input) {
      if (input.isEmpty) return '';
      return input
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '') // remove Arabic diacritics / tashkeel
          .replaceAll(RegExp(r'[إأآا]'), 'ا') // normalize alef
          .replaceAll('ة', 'ه') // normalize teh marbuta
          .replaceAll('ى', 'ي') // normalize alef maksura
          .replaceAll(RegExp(r'[\-_–—\s]+'), ' ') // normalize hyphens, en-dashes, em-dashes and spaces
          .trim();
    }
    ```
  - Map transactions using a dual lookup: first against direct `event.id`, and fallback against `normalizeTitle(doc['eventName'])` matching `normalizeTitle(event.eventName)`.

---

### 7️⃣ Pillar 7: Google Cloud Firestore Composite Indexing (فهارس الفايربيز المركبة)
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
1. **No Unbounded Eager Stacks**: Always use lazy `_loadedTabs` for multi-tab portals with stable keys.
2. **Zero Animation Jank**: Always wrap animated sidebars and viewports in `RepaintBoundary`.
3. **No Un-Scoped Full Collection Streams**: Always use server-side `.where()` for tenant data.
4. **Instant 0ms Stale-While-Revalidate**: Always maintain static/memory persistent caches across tab transitions.
5. **Zero-Wipe Cache Invariant**: Never clear or zero-out cached metrics upon receiving empty or transient snapshots.
6. **No Streams in `build()`**: Always memoize Firestore `.snapshots()` outside `build()` to prevent resubscription lag.
7. **Phonetic Arabic Matching**: Always normalize Arabic strings when attributing receipts across POS systems.
8. **Declared Composite Indexes**: Always define composite indexes in `firestore.indexes.json`.
