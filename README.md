# CarMain

App de gestión de mantenimientos preventivos de vehículos con investigación IA + web, soporte para swaps y comunicación dueño ↔ mecánico.

## Stack

- **Mobile**: Flutter (Dart) — Drift (SQLite local), Riverpod, dio
- **Backend**: Go — gin (REST), gorilla/websocket (relay), Claude API

## Estructura

```
CarMain/
├── app/              ← Flutter app (móvil del dueño)
│   └── lib/
│       ├── models/       ← Modelos de dominio (freezed)
│       ├── database/     ← Drift (SQLite local-first)
│       ├── data/         ← Repositorio (DB ↔ modelos)
│       ├── providers/    ← Riverpod (estado)
│       ├── services/     ← API client, relay WebSocket
│       └── screens/      ← UI (dashboard, crear, detalle, registrar)
└── servidor-go/     ← Backend Go
    ├── relay/            ← WebSocket relay (ruteo dueño↔mecánico)
    ├── biblioteca/       ← API de planes (cache + Claude IA)
    └── shared/           ← Modelos compartidos
```

## Setup

### Flutter (mobile)
```bash
cd app
flutter pub get
dart run build_runner build  # generar freezed + drift
flutter run
```

### Go (backend)
```bash
cd servidor-go
cp .env.example .env  # configurar ANTHROPIC_API_KEY
go mod tidy
go run .
```

## Plan completo
Ver `C:\Users\David\.claude\plans\enchanted-plotting-sutton.md`
