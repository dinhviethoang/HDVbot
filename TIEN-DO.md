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

## Đang dở
- Build #1 trên GitHub Actions đã kích hoạt khi push, chưa biết kết quả (Claude không đọc được Actions của repo riêng tư: không có gh, trình duyệt trong app chưa đăng nhập GitHub).

## Việc tiếp theo
1. Xem kết quả build ở https://github.com/dinhviethoang/HDVbot/actions; nếu lỗi thì lấy log, sửa, push lại.
2. Tải artifact hdvbot-apk-release, cài app-armeabi-v7a-release.apk lên J2 Pro, kích hoạt mã 6 số trên xiaozhi.me.
3. Người dùng góp ý mắt robot/giao diện.
