# Travel Desk

Private AI assistant for travel agency owners (Flutter, Android 11+, 64-bit).

After login the whole app is one chat with an on-device language model.
The model runs on the phone after a one-time download; chats never leave the device.

- `lib/ai/brain.dart`   on-device model (flutter_edge_ai + LiteRT-LM): install, load, chat
- `lib/ai/agent.dart`   system prompt (agency settings, saved prices, remembered notes), tool-call loop
- `lib/ai/tools.dart`   exact tools: quote, flight/hotel search, save price, settings, memory, account
- `lib/services/flight_fares.dart`, `hotel_rates.dart`  DEMO feeds behind provider interfaces

Prices are never written by the model: they come from the planner and the rate feeds.

## Build
Upload all files to the repo root and run "Build APK". Secrets: KEYSTORE_BASE64, KEYSTORE_PASSWORD.
Optional: SUPABASE_URL, SUPABASE_ANON_KEY (encrypted backup), MODEL_URL (your own hosted
Gemma-family .litertlm file), HUGGINGFACE_TOKEN (if the chosen model is gated).
