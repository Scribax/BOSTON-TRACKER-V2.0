# 🚚 Boston Tracker

Sistema de rastreo GPS en tiempo real para repartidores. Permite a un administrador monitorear la ubicación, velocidad y métricas de sus deliveries en vivo desde un dashboard web, mientras los repartidores usan una app Android.

> **Estado actual:** Producción en VPS `186.64.123.15`
> **Repo:** `github.com/Scribax/BOSTON-TRACKER-V2.0` (branch `main`)
> **Futuro:** Base preparada para migración a SaaS multitenant (DeliveryPlus)

---

## 📁 Estructura del repositorio

```
BOSTON TRACKER/
├── backend/          # API REST + Socket.IO (Node.js + TypeScript)
├── dashboard/        # Panel admin web (Next.js 14)
├── flutter_app/      # App Android para repartidores (Flutter/Dart)
├── ecosystem.config.js  # Configuración PM2 para producción
├── deploy.sh         # Script de deploy al VPS
└── .gitignore
```

---

## 🏗️ Arquitectura del sistema

```
┌─────────────────┐         HTTP/WebSocket          ┌─────────────────────┐
│   Flutter App   │ ──────────────────────────────▶ │   Backend (:5000)   │
│  (Android APK)  │ ◀────────────────────────────── │  Express + Socket.IO│
└─────────────────┘                                  │  + PostgreSQL       │
                                                     └────────┬────────────┘
┌─────────────────┐         HTTP/WebSocket                    │
│  Dashboard Web  │ ──────────────────────────────▶           │
│  Next.js (:3000)│ ◀────────────────────────────── ──────────┘
└─────────────────┘
```

### Flujo completo de un viaje

```
1. Delivery abre la app → login con usuario/contraseña
2. Delivery presiona "INICIAR VIAJE"
   → POST /api/deliveries/:id/start
   → Backend crea Trip con status: 'active'
   → Backend emite socket 'tripStarted' al room 'admins'
   → Dashboard agrega pin en el mapa

3. App inicia GPS tracking (foreground service Android)
   → Cada movimiento > 10m: POST /api/deliveries/:id/location
   → Heartbeat cada 30s si está quieto: POST /api/deliveries/:id/location
   → Cada 5s: POST /api/deliveries/:id/metrics
   → Backend emite 'locationUpdate' y 'metricsUpdate' por socket a admins

4. Dashboard recibe updates por Socket.IO O por polling HTTP cada 10s
   → Mueve pin en mapa en tiempo real
   → Actualiza métricas en sidebar

5. Admin presiona "DETENER VIAJE" en dashboard
   → POST /api/deliveries/:id/stop (solo admins)
   → Backend calcula métricas finales, marca Trip como 'completed'
   → Emite 'tripCompleted' a admins y 'tripStopped' al delivery
   → App detecta el stop por socket o por polling HTTP cada 10s
   → App muestra dialog y detiene el GPS

6. Viaje aparece en /history del dashboard
```

---

## 🔧 Stack tecnológico

### Backend (`/backend`)
| Tecnología | Versión | Uso |
|---|---|---|
| Node.js | 18+ | Runtime |
| TypeScript | 5.x | Lenguaje |
| Express | 4.x | API REST |
| Socket.IO | 4.x | Tiempo real |
| Sequelize | 6.x | ORM |
| PostgreSQL | 14+ | Base de datos |
| JWT | — | Autenticación |
| PM2 | — | Process manager |

**Path aliases configurados en `tsconfig.json`:**
- `@config` → `src/config`
- `@controllers` → `src/controllers`
- `@models` → `src/models`
- `@middleware` → `src/middleware`
- `@utils` → `src/utils`

### Dashboard (`/dashboard`)
| Tecnología | Versión | Uso |
|---|---|---|
| Next.js | 14 | Framework React |
| TypeScript | 5.x | Lenguaje |
| TailwindCSS | 3.x | Estilos |
| Leaflet | — | Mapa interactivo |
| Socket.IO Client | 4.x | Tiempo real |
| Axios | — | HTTP client |
| js-cookie | — | Gestión de token JWT |
| Lucide React | — | Iconos |

### Flutter App (`/flutter_app`)
| Tecnología | Versión | Uso |
|---|---|---|
| Flutter | 3.x | Framework |
| Dart | 3.x | Lenguaje |
| flutter_bloc | — | State management |
| geolocator | — | GPS |
| flutter_foreground_task | — | Foreground service Android |
| socket_io_client | — | Socket.IO |
| dio | — | HTTP client |
| go_router | — | Navegación |
| shared_preferences | — | Storage local |
| logger | — | Logs |

---

## 🗄️ Modelos de base de datos

### User
```typescript
{
  id: UUID (PK),
  name: string,
  email: string (unique, nullable),
  employeeId: string (unique),  // Ej: "DEL001"
  password: string (hashed bcrypt),
  role: 'admin' | 'delivery',
  phone: string (nullable),
  isActive: boolean (default: true),
  lastLogin: Date (nullable),
  createdAt: Date,
  updatedAt: Date,
}
```

### Trip
```typescript
{
  id: UUID (PK),
  deliveryId: UUID (FK → User),
  status: 'active' | 'completed',
  startTime: Date,
  endTime: Date (nullable),
  mileage: float (km, default: 0),
  duration: integer (segundos, default: 0),
  averageSpeed: float (km/h, default: 0),
  createdAt: Date,
  updatedAt: Date,
  // Métodos del modelo:
  getDuration(): number       // segundos desde startTime
  getAverageSpeed(): number   // calculado desde locations
  getRealTimeMetrics(): object
}
```

### Location
```typescript
{
  id: UUID (PK),
  tripId: UUID (FK → Trip),
  latitude: float,
  longitude: float,
  accuracy: float (metros),
  speed: float (km/h),
  heading: float (grados),
  timestamp: Date,
  createdAt: Date,
}
```

**Asociaciones:**
- `User hasMany Trip` (as: 'trips')
- `Trip belongsTo User` (as: 'delivery')
- `Trip hasMany Location` (as: 'tripLocations')
- `Location belongsTo Trip`

---

## 🌐 API REST endpoints

### Auth (`/api/auth`)
| Método | Ruta | Auth | Descripción |
|---|---|---|---|
| POST | `/login` | No | Login, devuelve JWT |
| GET | `/me` | JWT | Perfil del usuario autenticado |
| GET | `/users` | Admin | Listar todos los usuarios |
| POST | `/users` | Admin | Crear usuario |
| PUT | `/users/:id` | Admin | Editar usuario |
| DELETE | `/users/:id` | Admin | Eliminar usuario (fuerza logout en app) |

### Deliveries (`/api/deliveries`)
| Método | Ruta | Auth | Descripción |
|---|---|---|---|
| GET | `/` | Admin | Listar deliveries activos con última ubicación |
| GET | `/my-trip` | Delivery | Viaje activo del delivery autenticado |
| POST | `/:id/start` | Delivery/Admin | Iniciar viaje |
| POST | `/:id/stop` | **Admin only** | Detener viaje |
| POST | `/:id/location` | Delivery/Admin | Actualizar ubicación GPS |
| POST | `/:id/metrics` | Delivery/Admin | Actualizar métricas |
| GET | `/:id/history` | Delivery/Admin | Historial de viajes del delivery |

### Trips (`/api/trips`)
| Método | Ruta | Auth | Descripción |
|---|---|---|---|
| GET | `/history` | Admin | Historial paginado de viajes completados |
| GET | `/details/:id` | Admin | Detalle de viaje + todas las locations |
| DELETE | `/:id` | Admin | Eliminar viaje |

---

## 🔌 Socket.IO eventos

### Servidor → Cliente

| Evento | Room destino | Payload | Descripción |
|---|---|---|---|
| `tripStarted` | `admins` | `{deliveryId, deliveryName, tripId, startTime}` | Nuevo viaje iniciado |
| `tripStopped` | `admins` | `{deliveryId, tripId}` | Viaje detenido |
| `tripCompleted` | `admins` | `{deliveryId, tripId, metrics}` | Viaje completado con métricas |
| `locationUpdate` | `admins` | `{deliveryId, latitude, longitude, speed, heading, accuracy}` | Update de posición |
| `metricsUpdate` | `admins` | `{deliveryId, currentSpeed, averageSpeed, maxSpeed, totalDistance, totalTime}` | Update de métricas |
| `tripStopped` | `delivery-{id}` | `{tripId, metrics}` | Admin detuvo el viaje (para la app) |
| `forceLogout` | `delivery-{id}` | `{reason}` | Admin borró/desactivó el usuario |

### Cliente → Servidor

| Evento | Descripción |
|---|---|
| `join-admin` | Dashboard se une al room `admins` (requiere token JWT admin) |
| `join-delivery` | App se une al room `delivery-{userId}` |

---

## 📱 App Flutter — estructura

```
flutter_app/lib/
├── main.dart                    # Entry point, inicializa ForegroundService
├── bloc/auth/                   # AuthBloc — estado de autenticación
├── config/
│   ├── router.dart              # go_router — rutas de la app
│   └── theme.dart               # Colores y estilos (AppTheme)
├── models/
│   ├── user.dart                # Modelo User
│   └── trip.dart                # Modelo Trip
├── screens/
│   ├── login_screen.dart        # Pantalla de login
│   ├── home_screen.dart         # Pantalla principal (viaje activo)
│   └── splash_screen.dart       # Splash inicial
├── services/
│   ├── api_service.dart         # HTTP client (Dio) — base: http://186.64.123.15:5000/api
│   ├── socket_service.dart      # Socket.IO client
│   ├── location_service.dart    # GPS tracking + heartbeat + offline queue
│   ├── storage_service.dart     # SharedPreferences — token y user
│   └── foreground_service.dart  # Flutter Foreground Task (Android)
└── widgets/
    └── metric_card.dart         # Widget de métricas
```

### Lógica clave en `home_screen.dart`

- **`_startTrip()`** — llama API, inicia tracking y reloj
- **`_startLocationTracking()`** — arranca `LocationService` + polling + reloj
- **`_startClock()`** — Timer cada 1s actualizando `_elapsedSeconds`
- **`_startTripPolling()`** — Timer cada 10s verificando si el viaje sigue activo. Tiene **grace period de 30s** al inicio para evitar falsos positivos
- **`_showTripStoppedDialog()`** — Dialog cuando el admin detiene el viaje
- **Socket listeners** — `tripStopped`, `forceLogout`

### Lógica clave en `location_service.dart`

- **`startTracking()`** — pide permisos GPS, inicia heartbeat timer (30s), arranca stream de posiciones
- **`_onPositionUpdate()`** — filtra accuracy > 100m, filtra movimientos < 5m (excepto primera posición), filtra velocidades imposibles > 120 km/h
- **Heartbeat timer** — envía última posición conocida cada 30s si el delivery está quieto (guarda `_lastSentTime` para no duplicar si ya mandó por movimiento)
- **Offline queue** — si falla el envío HTTP, guarda en `_pendingQueue` (máx 500 items) y reenvía automáticamente al recuperar conexión
- **`stopTracking()`** — cancela stream, heartbeat timer, limpia cola

---

## 🖥️ Dashboard — estructura

```
dashboard/src/
├── app/
│   ├── page.tsx                 # Tracking en vivo (mapa + sidebar)
│   ├── history/page.tsx         # Historial de viajes con filtros
│   ├── users/page.tsx           # Gestión de usuarios (CRUD)
│   ├── apk/page.tsx             # Descarga de APK
│   └── login/page.tsx           # Login admin
├── components/
│   ├── Map.tsx                  # Mapa Leaflet con pins de deliveries
│   ├── TripRouteMap.tsx         # Mapa con polyline de ruta de viaje histórico
│   ├── ActiveDeliveryCard.tsx   # Card de delivery activo en sidebar
│   └── DashboardLayout.tsx      # Layout con sidebar de navegación
└── lib/
    ├── api.ts                   # Axios instance con baseURL y JWT interceptor
    ├── socket.ts                # Socket.IO singleton con reconexión automática
    └── types.ts                 # Interfaces TypeScript (User, Trip, ActiveDelivery...)
```

### Funcionalidades del dashboard

- **Tracking en vivo** — mapa con pins actualizados por socket + polling HTTP cada 10s
- **Historial de viajes** — filtros por nombre/ID de delivery y rango de fechas, botón para ver ruta en mapa
- **Ver ruta histórica** — modal con mapa Leaflet, polyline roja, marcador verde (inicio) y rojo (fin)
- **Gestión de usuarios** — crear/editar/desactivar/eliminar deliveries
- **Eliminar usuario** — detiene viaje activo automáticamente y fuerza logout en la app
- **Descarga APK** — página para distribuir la app

---

## 🚀 Deploy en producción

### Infraestructura
- **VPS:** `186.64.123.15` (Linux)
- **Backend:** Puerto `5000`, gestionado por PM2
- **Dashboard:** Puerto `3000`, gestionado por PM2
- **Nginx:** Reverse proxy, sirve ambos en puerto 80

### PM2 (ecosystem.config.js)
```bash
pm2 start ecosystem.config.js    # Iniciar todo
pm2 status                        # Ver estado
pm2 logs boston-backend           # Logs del backend
pm2 restart boston-backend        # Reiniciar backend
pm2 restart boston-dashboard      # Reiniciar dashboard
```

### Deploy de actualizaciones
```bash
# En el VPS
cd /var/www/boston-tracker

# Backend
git pull
cd backend && npm run build && pm2 restart boston-backend

# Dashboard
cd ../dashboard && npm run build && pm2 restart boston-dashboard
```

### Variables de entorno backend (`backend/.env`)
```env
NODE_ENV=production
PORT=5000
DB_HOST=localhost
DB_PORT=5432
DB_NAME=boston_tracker
DB_USER=postgres
DB_PASS=<password>
JWT_SECRET=<secret>
JWT_EXPIRE=7d
```

---

## 🔐 Sistema de autenticación

- **JWT** almacenado en cookie (`token`) en el dashboard
- **JWT** almacenado en `SharedPreferences` en la app Flutter
- **Roles:** `admin` y `delivery`
- **Middleware `authenticate`** — verifica JWT en header `Authorization: Bearer <token>`
- **Middleware `authorize(role)`** — verifica que el usuario tenga el rol requerido
- **Middleware `authorizeOwnership`** — delivery solo puede operar sobre su propio ID

### Flujo de eliminación de usuario
```
Admin elimina usuario desde dashboard
  → Backend busca viaje activo del usuario
  → Si existe: lo marca como 'completed', calcula métricas finales
  → Emite socket 'forceLogout' al room 'delivery-{userId}'
  → App Flutter recibe 'forceLogout'
  → App para GPS, limpia storage, navega a login con mensaje
```

---

## 🐛 Bugs conocidos resueltos

| Bug | Causa | Fix |
|---|---|---|
| Pin no aparecía al iniciar viaje | Primera posición GPS descartada por filtro de distancia | Bypass del filtro en `isFirstPosition` |
| Viaje se detenía solo a los 10s | Polling sin grace period veía `null` antes de que el viaje se guardara en DB | Grace period de 30s en `_startTripPolling()` |
| `maxSpeed` siempre 0 en historial | Hardcodeado en `trips.ts` | Consulta `Location.findOne` ordenada por speed DESC |
| Socket no reconectaba tras relogin | Singleton no destruido al desconectarse | `socket.disconnect(); socket = null` antes de crear nuevo |
| Mileage se recalculaba en cada update | Iteraba todas las locations en DB | Solo incrementa con delta desde última location |

---

## 📋 Estado actual del proyecto (Mayo 2026)

### ✅ Funcionando
- Login admin en dashboard y delivery en app
- Inicio/detención de viajes (solo admin puede detener)
- GPS tracking en tiempo real con foreground service
- Heartbeat cada 30s para deliveries quietos
- Offline queue — guarda hasta 500 ubicaciones si no hay internet
- Mapa en vivo con pins actualizados por socket + polling
- Historial de viajes con filtros por fecha y delivery
- Ver ruta completa de viajes históricos en mapa
- Reloj en tiempo real en la app mostrando tiempo transcurrido
- Gestión de usuarios (CRUD) desde dashboard
- Forzar logout y detener viaje al eliminar/desactivar usuario
- Protección: delivery no puede cerrar sesión durante viaje activo

### 🔄 Pendiente / Próximas mejoras
- Migración a arquitectura SaaS multitenant
- Panel super-admin para gestionar múltiples tenants
- Subdominios dinámicos por tenant (`cliente.deliveryplus.com`)
- White-label del dashboard (logo/colores configurables por tenant)
- Onboarding de delivery por QR en lugar de URL hardcodeada
- Landing page con registro self-service
- Sistema de facturación por uso

---

## 🗺️ Roadmap SaaS (DeliveryPlus)

El sistema está diseñado para escalar a una plataforma multi-tenant donde múltiples restaurantes/empresas usen la misma infraestructura con sus propios subdominios.

```
Fase 1: Multitenant en DB
  → Agregar tenantId a Users, Trips, Locations
  → Middleware que filtra por tenantId automáticamente
  → Seed de tenant Boston como primero

Fase 2: Super-admin panel (app.deliveryplus.com)
  → CRUD de tenants
  → Métricas globales por tenant
  → Habilitar/suspender tenants

Fase 3: Subdominios dinámicos
  → Nginx con wildcard *.deliveryplus.com
  → Middleware detecta subdominio → resuelve tenantId
  → Dashboard se auto-configura según el tenant

Fase 4: White-label
  → Logo, colores, nombre configurables por tenant
  → Dashboard usa config del tenant del token

Fase 5: Flutter configurable
  → App escanea QR al instalar → configura URL y tenantId
  → O app universal que pide empresa al login

Fase 6: Billing
  → Plan por cantidad de deliveries activos
  → Integración Stripe/MercadoPago
```

---

## 👨‍💻 Desarrollo local

### Backend
```bash
cd backend
npm install
cp .env.example .env  # Configurar variables
npm run dev           # ts-node-dev con hot reload
```

### Dashboard
```bash
cd dashboard
npm install
npm run dev           # Next.js dev server en :3000
```

### Flutter App
```bash
cd flutter_app
flutter pub get
flutter run -d <device-id>   # Correr en dispositivo físico
# Para build APK:
flutter build apk --release
```

### Dispositivo de prueba
- **TECNO LI7** — Android ARM64
- Device ID: `11459254AB102563`
- Comando: `flutter run -d 11459254AB102563`

---

## 📝 Notas importantes para IAs / colaboradores

1. **El dashboard tiene su propio `.git`** sin remote configurado — commits del dashboard son locales. El repo raíz en GitHub es el que contiene todo.

2. **La URL del backend está hardcodeada** en `flutter_app/lib/services/api_service.dart` como `http://186.64.123.15:5000/api`. Para cambiar el entorno hay que modificar ese archivo.

3. **El socket en el backend es no-fatal** — permite conexiones sin token válido para el dashboard; la autorización se hace en el evento `join-admin`.

4. **`authorizeOwnership` en deliveries** — verifica que `req.params.id === req.user.id` para que un delivery no pueda operar sobre otro. Los admins pasan siempre.

5. **El build del backend** genera `dist/` que es lo que PM2 ejecuta. Siempre correr `npm run build` antes de reiniciar PM2.

6. **Warnings CRLF en git** son normales en Windows — no afectan el funcionamiento.

7. **`totalLocations: 0`** en viajes recién creados es correcto — se incrementa con cada `updateLocation`.
