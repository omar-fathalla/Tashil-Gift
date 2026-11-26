# منظومة تسهيل جفت الذكية - Tashil Gift

حلول الترويج والتحقق الذكي متعدد الشركات.

منصة Flutter Web على Firebase: المندوب بيصوّر فاتورة العميل، Gemini بيقراها ويتأكد من شروط الحملة، والعميل بيكسب هدية من خلال لعبة، والسيرفر بيخصم من رصيد الفرع.

* الإنتاج: https://tashil-gift.web.app
* Firebase: `tashil-gift`
* Linear: فريق **Tashil Gift** (`TAG`)

## ابدأ من هنا

* [docs/README.md](docs/README.md): فهرس التوثيق كله (المعمارية، البيانات، رحلة الفاتورة، الـ functions، الـ AI، التشغيل، النشر، القواعد، النواقص، والخطة).
* [docs/07-dev-setup.md](docs/07-dev-setup.md): تجهيز الجهاز والتشغيل والاختبارات.
* [AGENTS.md](AGENTS.md): القواعد الإلزامية (ممنوع push أو deploy من غير طلب صريح).

## تشغيل سريع

```bash
fvm install && fvm flutter pub get        # Flutter 3.44.5 من .fvmrc
(cd functions && npm ci && npm test)      # Node 22
fvm flutter run -d chrome --web-port 8080 # تحذير: متوصّل بالإنتاج، شوف docs/07-dev-setup.md للـ emulators
```
