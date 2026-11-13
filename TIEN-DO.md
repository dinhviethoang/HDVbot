# xiaozhi-rieng — app Xiaozhi AI cá nhân cho Samsung J2 Pro (Android 7.1.1)

Clone từ https://github.com/TOM88812/xiaozhi-android-client (Flutter, giấy phép Apache 2.0 — giữ file LICENSE và ghi nguồn gốc).
Nhánh làm việc: `rieng` (nhánh `main` giữ nguyên bản gốc).

## Đã xong
- 14/11/2026: clone mã nguồn (commit gốc 18/09/2026), tạo nhánh `rieng`.
- Đã xem: minSdk 24 (chạy được Android 7.1.1), applicationId gốc `com.lhht.ai_assistant`, 28 file Dart trong `lib/`
  (screens: home, chat, voice_call, settings; services: xiaozhi_service, xiaozhi_websocket_manager, dify, minimax).

## Đang dở
- Chưa build được: máy chưa có Flutter, Java, Android SDK, gh. Chờ người dùng chọn cách build
  (cài công cụ trên máy, hoặc đẩy lên GitHub và build bằng Actions như rustdesk-rieng).
- Chưa chốt danh sách tùy chỉnh (tên app, icon, giao diện, tính năng).

## Việc tiếp theo
1. Người dùng chọn cách build + nêu các tùy chỉnh mong muốn.
2. Build APK gốc, cài thử trên J2 Pro để chắc bản gốc chạy trước khi sửa.
3. Giao codex/agy tùy chỉnh theo danh sách, build lại, cài thử.
