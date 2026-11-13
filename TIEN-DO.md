# xiaozhi-rieng — app Xiaozhi AI cá nhân cho Samsung J2 Pro (Android 7.1.1)

Clone từ https://github.com/TOM88812/xiaozhi-android-client (Flutter, giấy phép Apache 2.0 — giữ file LICENSE và ghi nguồn gốc).
Nhánh làm việc: `rieng` (nhánh `main` giữ nguyên bản gốc).

## Đã xong
- 14/11/2026: clone mã nguồn (commit gốc 18/09/2026), tạo nhánh `rieng`.
- Đã xem: minSdk 24 (chạy được Android 7.1.1), applicationId gốc `com.lhht.ai_assistant`, 28 file Dart trong `lib/`
  (screens: home, chat, voice_call, settings; services: xiaozhi_service, xiaozhi_websocket_manager, dify, minimax).

- 14/11: tùy chỉnh thành HDVbot (commit 9be26e7): tên + applicationId com.king.hdvbot, logo KinG làm icon, mắt robot mecha (lib/widgets/robot_eyes.dart) + theme HUD,
  Việt hóa, bỏ Dify/MiniMax, mở app vào thẳng VoiceCallScreen, giữ màn hình sáng khi sạc (MainActivity.kt), workflow .github/workflows/build-apk.yml.
  Toàn bộ do agy làm bằng Gemini Flash High (codex + Opus hết quota tới 17–18/11). CHƯA biên dịch lần nào.
- Remote: origin = https://github.com/dinhviethoang/HDVbot (riêng tư), upstream = bản gốc TOM88812. Đã push nhánh `rieng`.

- 14/11: Build #4 trên GitHub Actions THÀNH CÔNG (commit 1d45b05, run 43482093414, 10m58s) → artifact `hdvbot-apk-release` 65.4 MB (giữ 7 ngày).
  Đã sửa 2 lỗi build: (1) plugin flutter_pcm_player còn `package=` trong AndroidManifest → workflow xóa thuộc tính + đặt namespace;
  (2) R8 thiếu lớp Play Core → thêm `-dontwarn com.google.android.play.core.**` vào android/app/proguard-rules.pro. Claude tự sửa (vài dòng).
- Xem Actions: repo riêng tư, Claude đọc qua Claude in Chrome (trình duyệt "DESKTOP-068OM6B" đã đăng nhập GitHub); không có gh.

- 14/11: workflow tự đăng `HDVbot.apk` (bản armeabi-v7a) lên Releases mỗi lần build (tag build-N). Build #5 OK → link cố định bản mới nhất:
  https://github.com/dinhviethoang/HDVbot/releases/latest/download/HDVbot.apk (repo riêng tư: điện thoại phải đăng nhập GitHub).

## Đang dở
- APK CHƯA cài thử trên J2 Pro: chưa biết app có chạy, mắt robot/giao diện trông ra sao, nối được xiaozhi.me không.

## Việc tiếp theo
1. Người dùng đăng nhập GitHub trên Chrome của J2 Pro, tải HDVbot.apk từ link Releases ở trên, cài.
2. Mở app → nhập cấu hình (OTA đã điền sẵn) → lấy mã 6 số → kích hoạt trên xiaozhi.me.
3. Người dùng góp ý mắt robot/giao diện/lỗi → giao codex/agy sửa (quota: codex về 17/11, agy Opus ~18/11) → push là tự build.
