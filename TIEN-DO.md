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

- 14/11: build 10: ký APK bằng khóa cố định android/app/hdvbot-release.p12 (mật khẩu trong build.gradle.kts, repo PHẢI riêng tư),
  versionCode = số lần build → từ build 10 cài đè được (trước đó phải gỡ bản cũ: chữ ký khác làm Samsung treo "Đang cài đặt").
- 14/11: người dùng cài được trên 1 máy, kích hoạt OK, nói chuyện được nhưng tiếng Trung → hướng dẫn đổi ngôn ngữ/giọng/vai trò trên xiaozhi.me.
- 14/11: build 11 OK (commit 25f2912): app luôn nền tối (bỏ công tắc), màn hình luôn sáng khi mở app (MainActivity.kt),
  biểu cảm theo từng câu nói: lib/utils/emotion_detector.dart (từ khóa tiếng Việt có/không dấu + emoji) + cảm xúc server; mặc định neutral.

- 14/11: người dùng báo trạng thái nhảy liên tục + màn hình khuôn mặt không nghe (chat nhấn giữ thì được). Claude đọc code xác định:
  2 WebSocketManager song song cùng Device-Id (connectVoiceCall tạo mới không hủy cũ) + disconnect() vẫn tự reconnect; voice screen gọi
  listen start trước 'hello' và không mở lại mic sau reconnect/sau TTS stop. agy sửa (1 kết nối, _manualClose, backoff 2-30s, nghe sau hello,
  tạm dừng gửi audio khi robot nói, resumeListeningCall sau tts stop, debounce 2s). Build 12 OK (commit 1dd81cd).
- APK build 11/12 đã tải về thư mục Downloads (HDVbot-build11.apk, HDVbot-build12.apk); người dùng chuyển sang điện thoại.

- 14/11: build 12 trên máy: chỉ chạy 1 lượt rồi server chào tạm biệt (kết thúc phiên), không đánh thức lại được, mic không vào chat.
  agy làm: máy trạng thái phiên (sleeping khi server đóng / 20s im lặng), đánh thức bằng chạm hoặc độ to giọng nói (AudioUtil.amplitudeStream,
  bật/tắt + độ nhạy trong Cài đặt), nút mic lớn, lưu stt/tts vào lịch sử chat, sửa mic chat sau khi rời màn hình khuôn mặt,
  nhật ký trong app lib/utils/app_log.dart + lib/screens/log_screen.dart (giữ 2s vào mặt). Build 13 bị GitHub hủy (không phải lỗi code),
  build 14 OK (commit 3161327, cùng code 3bea658). APK: Downloads/HDVbot-build14.apk.

## Đang dở
- Chưa thử build 14 trên máy. Phần kết nối/nghe đã sửa 2 lần đều dựa trên đọc code, chưa có log thật.
- branding/hdvbot-release.p12 là bản copy thừa của khóa ký (có thể xóa).

## Việc tiếp theo
1. Người dùng cài đè build 14, thử: nói ở mặt → robot ngủ → chạm/nói to để đánh thức → nói tiếp; xem chat có lưu lời thoại.
2. Có lỗi thì giữ 2s vào mặt → Nhật ký → Sao chép/chụp gửi Claude.
3. Từ 17/11 15:23 dùng codex cho phần sửa logic (Gemini Flash hay đoán sai).
