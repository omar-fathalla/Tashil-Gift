---
name: pagination-infinite-scroll-standard
description: Mandatory architectural and UI standard for Infinite Scrolling, Lazy Loading, Cursor-based Firestore Pagination, and Virtual Windowing across large datasets and tables in Flutter.
version: 1.0.0
---

# Infinite Scrolling & Lazy Loading Standard (معيار التجزيء والتحميل الكسول)

This skill defines the **mandatory architectural and performance standard** for handling large datasets (product catalogs, receipts log, audit trails, user transactions, and large tables) across Flutter (Web, Mobile, Desktop) and Cloud Firestore.

Whenever creating, modifying, or reviewing any screen, table, catalog, or list that displays scalable or user-generated data, you **MUST** strictly adhere to this standard to prevent UI freezing, high memory consumption, and unnecessary database reads.

---

## 1. Scientific & Engineering Foundations (الأسس العلمية والهندسية)

### أ. Cursor-based Pagination vs. Offset Pagination (الترقيم بالمؤشر)
- **Offset Pagination (التقليدي والمضر):** `SELECT * FROM items LIMIT 20 OFFSET 800`.
  - *المشكلة:* قاعدة البيانات تقوم بقراءة ومسح أول 800 سطر وتتجاهلهم لتعيد لك 20 سطراً فقط ($O(N)$). في Firestore، هذا يستهلك قراءات مضاعفة ويزيد زمن الاستجابة.
- **Cursor-based Pagination (المعيار المعتمد):** `collection.orderBy('createdAt', descending: true).startAfterDocument(lastDoc).limit(20)`.
  - *الميزة:* الانتقال المباشر للموقع المطلوب ($O(1)$) باستخدام مؤشر الوثيقة السابقة، مما يضمن سرعة ثابتة سواء كنت في الصفحة الأولى أو الصفحة المئة.

### ب. Lazy Loading & Infinite Scrolling (التحميل عند الطلب)
- لا يتم استدعاء البيانات إلا عندما يقترب المستخدم من نهاية القائمة الحالية (`maxScrollExtent - 200px`).
- يقلل استهلاك الباندويث (Network Bandwidth) بنسبة تزيد عن 95% عند فتح الشاشات الكبيرة.

### ج. DOM / Widget Virtualization & Windowing (إعادة تدوير العناصر)
- عند وجود 1,000 منتج، لا يتم بناء 1,000 عنصر في شجرة الـ RenderTree أو الـ DOM.
- استخدام `ListView.builder` أو `SliverList` يقوم فقط برسم العناصر المرئية في نافذة العرض (Viewport) + مخزن مؤقت صغير (`cacheExtent: 300`)، مما يجعل استهلاك الذاكرة (RAM) ثابتاً ومستقراً تماماً.

---

## 2. Mandatory Architectural Rules (القواعد الإلزامية)

### القاعدة 1: حظر الجلب الجماعي غير المحدود (`snapshots()` بدون `limit`)
- **يُمنع منعاً باتاً** عمل `firestore.collection('large_table').snapshots()` أو `.get()` بدون تحديد سقف أولي (`limit(20)` أو `limit(30)`).
- في القوائم الضخمة، يُستخدم `.limit(pageSize).get()` مع دعم زر أو مستشعر "تحميل المزيد" (`loadMore()`).

### القاعدة 2: حظر `shrinkWrap: true` في القوائم الضخمة داخل شاشات التمرير
- `shrinkWrap: true` يجبر Flutter على حساب أبعاد ورسم كل العناصر فوراً في الذاكرة مما يقتل ميزة الـ Virtualization.
- البديل: استخدام `SliverList` داخل `CustomScrollView` أو تثبيت ارتفاع الحاوية واستخدام `ListView.builder`.

### القاعدة 3: مراقبة التمرير الذكية (Smart ScrollController Debouncing)
- عند ربط مستشعر التمرير `_scrollController.addListener(...)`، يجب حماية دالة `_loadMore()` بحاجز منع التكرار (`_isLoadingMore` و `_hasMore`) لمنع إرسال طلبات متعددة لنفس الصفحة.

### القاعدة 4: مؤشرات بصرية واضحة لحالات التحميل والانتهاء
- **جاري التحميل الأولي:** عرض Skeleton Shimmer أو Shimmer Cards (أو دائرة تحميل مركزية نظيفة).
- **جاري تحميل الصفحة التالية:** عرض `LinearProgressIndicator` أو Spinner مصغر أسفل القائمة أثناء التمرير.
- **نهاية البيانات:** إظهار وسم أنيق (مثال: `"تم عرض كافة المنتجات (854 منتج)"`).

---

## 3. Standard Implementation Template (النموذج البرمجي القياسي)

```dart
class PaginatedListViewState extends State<PaginatedListView> {
  static const int _pageSize = 20;
  final ScrollController _scrollController = ScrollController();
  
  final List<DocumentSnapshot> _docs = [];
  bool _isLoadingInitial = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  DocumentSnapshot? _lastDocument;

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _isLoadingMore || _isLoadingInitial) return;
    
    // Trigger when user is within 200 pixels from the bottom
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _fetchMoreData();
    }
  }

  Future<void> _fetchInitialData() async {
    setState(() {
      _isLoadingInitial = true;
      _docs.clear();
      _hasMore = true;
      _lastDocument = null;
    });

    try {
      final query = FirebaseFirestore.instance
          .collection('items')
          .orderBy('createdAt', descending: true)
          .limit(_pageSize);

      final snapshot = await query.get();
      if (snapshot.docs.isNotEmpty) {
        _docs.addAll(snapshot.docs);
        _lastDocument = snapshot.docs.last;
        _hasMore = snapshot.docs.length == _pageSize;
      } else {
        _hasMore = false;
      }
    } catch (e) {
      // Handle error
    } finally {
      if (mounted) setState(() => _isLoadingInitial = false);
    }
  }

  Future<void> _fetchMoreData() async {
    if (_lastDocument == null) return;
    setState(() => _isLoadingMore = true);

    try {
      final query = FirebaseFirestore.instance
          .collection('items')
          .orderBy('createdAt', descending: true)
          .startAfterDocument(_lastDocument!)
          .limit(_pageSize);

      final snapshot = await query.get();
      if (snapshot.docs.isNotEmpty) {
        _docs.addAll(snapshot.docs);
        _lastDocument = snapshot.docs.last;
        _hasMore = snapshot.docs.length == _pageSize;
      } else {
        _hasMore = false;
      }
    } catch (e) {
      // Handle error
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingInitial) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_docs.isEmpty) {
      return const Center(child: Text('لا توجد بيانات متاحة'));
    }

    return ListView.builder(
      controller: _scrollController,
      itemCount: _docs.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _docs.length) {
          return const Padding(
            padding: EdgeInsets.all(16.0),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }

        final doc = _docs[index];
        return ListTile(
          title: Text(doc['name'] ?? ''),
        );
      },
    );
  }
}
```
