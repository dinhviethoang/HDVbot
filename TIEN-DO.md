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

- 14/11: người dùng báo không hiện mã 6 số → nguyên nhân: app gốc nối thẳng WebSocket với test-token, không qua OTA.
  agy viết lib/services/xiaozhi_ota_service.dart (checkVersion + /activate như firmware xiaozhi-esp32, giả lập ESP32-S3), MAC 02:xx… + Client-Id UUID
  cố định (SharedPreferences hdvbot_mac / hdvbot_client_id), lớp phủ hiện mã 6 số, lần đầu mở tự tạo cấu hình mặc định.
- 14/11: giao diện mới: lib/widgets/robot_face.dart (2 mắt + miệng, 12 cảm xúc, 6 trạng thái) toàn màn hình nền đen, xoay ngang
  (sensorLandscape), chạm để hiện nút; cảm xúc từ server qua XiaozhiService.emotionNotifier (tin 'emotion' và 'llm').
- Build #9 OK (commit dd43f90) = bản mới nhất trên Releases. (Build #7 lỗi thiếu import, Claude sửa 1 dòng.)

## Đang dở
- Chưa thử trên máy: luồng kích hoạt OTA (server có nhận thiết bị giả lập không), khuôn mặt, cảm xúc.

## Việc tiếp theo
1. Người dùng tải lại HDVbot.apk (link Releases latest), mở app → phải hiện mã 6 số → nhập trên xiaozhi.me.
2. Nếu lỗi: lớp phủ lỗi hiện HTTP code + nội dung → người dùng chụp gửi.
3. Góp ý khuôn mặt/cảm xúc → sửa (codex có lại 17/11, agy Opus ~18/11).
