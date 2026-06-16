# Boston Tracker

Sistema de rastreo GPS en tiempo real para deliveries. El administrador monitorea ubicaciones, métricas y estado de viajes desde un dashboard web, mientras el delivery usa una app Android en Flutter para iniciar viajes, enviar ubicación y recibir destinos asignados.

> Estado actual: producción en VPS `186.64.123.15`
> Backend: `Node.js + TypeScript + Express + Socket.IO + PostgreSQL`
> Dashboard: `Next.js 14`
> Mobile: `Flutter`

---

## Arquitectura

```text
Flutter App  ── HTTP / Socket.IO ──>  Backend (:5000)  ── PostgreSQL
Dashboard    ── HTTP / Socket.IO ──>  Backend (:5000)  ── PostgreSQL
```

### Roles

- `admin`: gestiona usuarios, ve el mapa en vivo, detiene viajes y asigna destinos.
- `delivery`: inicia su viaje, envía ubicación y recibe destinos o eventos de sesión.

---

## Flujo actual del sistema

### 1. Login y sesión

- El login devuelve `token`, `refreshToken` y `user`.
- El backend expone `POST /api/auth/refresh` para renovar la sesión.
- En Flutter:
  - `token` y `refreshToken` se guardan en `FlutterSecureStorage`.
  - `user` se guarda en `SharedPreferences`.
  - Si la app arranca con sesión guardada, intenta validar con `GET /api/auth/me`.
  - Si falla, usa `refreshToken` para renovar la sesión.

### 2. Inicio de viaje

- El delivery inicia viaje desde la app.
- La app llama `POST /api/deliveries/:id/start`.
- El backend crea un `Trip` con estado `active`.
- El dashboard recibe `tripStarted` por Socket.IO.

### 3. Seguimiento GPS

- La app Flutter usa `geolocator` para leer posiciones.
- El tracking corre con configuración de foreground en Android para mantener GPS activo.
- Cada ubicación válida se envía por:
  - `POST /api/deliveries/:id/location`
- Cada cierto intervalo también se envían métricas por:
  - `POST /api/deliveries/:id/metrics`

### 4. Mapa en vivo del dashboard

- El dashboard consume `locationUpdate` y `metricsUpdate` por Socket.IO.
- También mantiene reconexión automática y puede refrescar por HTTP.
- Cuando un delivery queda inactivo o se desconecta, el backend usa `lastSeenAt` para estimar estado online/offline.

### 5. Destinos asignados por el admin

- El admin envía un destino por Socket.IO con `deliveryDestination`.
- El backend:
  - lo guarda en memoria por delivery,
  - lo reenvía al room `delivery-<id>`,
  - y si el delivery se reconecta o vuelve a hacer `join-delivery`, el backend puede reenviar la última destination.
- La app Flutter:
  - se une al room `delivery-<userId>` al conectar y reconectar,
  - recibe `deliveryDestination`,
  - guarda la última destination localmente,
  - muestra notificación,
  - responde con `deliveryDestinationAck`.

### 6. Cierre de viaje o de sesión

- Si el admin detiene el viaje:
  - `POST /api/deliveries/:id/stop`
  - el backend marca el viaje como `completed`
  - emite `tripStopped` al delivery y a `admins`
- Si el admin desactiva o elimina un usuario:
  - el backend puede emitir `forceLogout`
  - la app Flutter limpia storage y vuelve al login

---

## Stack tecnológico

### Backend

| Tecnología | Uso |
|---|---|
| Node.js | Runtime |
| TypeScript | Lenguaje |
| Express | API REST |
| Socket.IO | Tiempo real |
| Sequelize | ORM |
| PostgreSQL | Base de datos |
| JWT | Autenticación |
| PM2 | Procesos en producción |

### Dashboard

| Tecnología | Uso |
|---|---|
| Next.js 14 | Frontend admin |
| TypeScript | Lenguaje |
| TailwindCSS | Estilos |
| Leaflet | Mapas |
| Socket.IO Client | Tiempo real |
| js-cookie | Token del admin |

### Flutter App

| Tecnología | Uso |
|---|---|
| Flutter | App Android |
| Dart | Lenguaje |
| flutter_bloc | Estado |
| geolocator | GPS |
| socket_io_client | Socket.IO |
| dio | HTTP client |
| go_router | Navegación |
| FlutterSecureStorage | Token seguro |
| SharedPreferences | Usuario y datos locales |
| logger | Logs |

---

## Backend

### Estructura principal

```text
backend/src/
├── controllers/
├── middleware/
├── models/
├── routes/
├── services/
├── utils/
├── types/
└── server.ts
```

### Auth

#### Rutas

| Método | Ruta | Auth | Descripción |
|---|---|---|---|
| POST | `/api/auth/login` | No | Login con `email` o `employeeId` + `password` |
| POST | `/api/auth/refresh` | No | Renueva `token` usando `refreshToken` |
| GET | `/api/auth/me` | JWT | Devuelve usuario autenticado |
| POST | `/api/auth/logout` | JWT | Logout lógico del lado cliente |
| GET | `/api/auth/users` | Admin | Lista usuarios |
| POST | `/api/auth/users` | Admin | Crea usuario |
| PUT | `/api/auth/users/:id` | Admin | Edita usuario |
| DELETE | `/api/auth/users/:id` | Admin | Elimina usuario y fuerza logout |

### Deliveries

| Método | Ruta | Auth | Descripción |
|---|---|---|---|
| GET | `/api/deliveries` | Admin | Lista deliveries activos |
| GET | `/api/deliveries/my-trip` | Delivery | Viaje activo del usuario autenticado |
| POST | `/api/deliveries/:id/start` | Dueño o admin | Inicia viaje |
| POST | `/api/deliveries/:id/stop` | Admin | Detiene viaje |
| POST | `/api/deliveries/:id/location` | Dueño o admin | Guarda ubicación |
| POST | `/api/deliveries/:id/metrics` | Dueño o admin | Guarda métricas |
| POST | `/api/deliveries/:id/inactivity-alert` | Dueño o admin | Alerta de inactividad |
| GET | `/api/deliveries/:id/history` | Dueño o admin | Historial de viajes |
| GET | `/api/deliveries/:id/destination-timeline` | Dueño o admin | Timeline de destinos |

### Trips

| Método | Ruta | Auth | Descripción |
|---|---|---|---|
| GET | `/api/trips/history` | Admin | Historial paginado |
| GET | `/api/trips/details/:id` | Admin | Detalle completo de viaje |
| DELETE | `/api/trips/:id` | Admin | Elimina un viaje |

---

## Socket.IO

### Servidor -> Cliente

| Evento | Destino | Descripción |
|---|---|---|
| `tripStarted` | `admins` | Nuevo viaje iniciado |
| `tripStopped` | `admins` y `delivery-<id>` | Viaje detenido |
| `tripCompleted` | `admins` | Viaje finalizado |
| `locationUpdate` | `admins` | Ubicación en vivo |
| `metricsUpdate` | `admins` | Métricas en vivo |
| `deliveryDestination` | `delivery-<id>` | Destino asignado por admin |
| `deliveryDestinationAck` | `admins` | Confirmación de recepción del destino |
| `forceLogout` | `delivery-<id>` | Cierre forzado por admin |

### Cliente -> Servidor

| Evento | Descripción |
|---|---|
| `join-admin` | El dashboard se une al room `admins` |
| `join-delivery` | La app delivery se une al room `delivery-<userId>` |
| `deliveryDestination` | El dashboard asigna un destino |
| `deliveryDestinationAck` | La app confirma recepción del destino |

---

## Flutter App

### Estructura principal

```text
flutter_app/lib/
├── bloc/auth/
├── config/
├── models/
├── screens/
├── services/
└── main.dart
```

### Flujo de la app

- `main.dart`
  - inicializa permisos
  - inicializa storage
  - carga auth restaurada
  - arranca router y services
- `AuthBloc`
  - maneja login, logout y arranque con sesión persistida
  - si hay token guardado, intenta validar y luego refrescar si hace falta
- `HomeScreen`
  - carga viaje activo
  - conecta socket
  - arranca tracking GPS
  - escucha `tripStopped`, `forceLogout`, `deliveryDestination`
- `SocketService`
  - conecta a Socket.IO
  - se re-une al room delivery al conectar y reconectar
  - expone eventos a la UI
- `DestinationService`
  - persiste la última destination
  - muestra notificación
  - envía ACK al backend
- `LocationService`
  - lee GPS
  - filtra posiciones inválidas
  - envía ubicación y métricas al backend

### Detalles importantes del tracking

- Filtra ubicaciones con accuracy muy mala.
- Evita enviar puntos con desplazamiento insignificante.
- Evita velocidades imposibles.
- Envía ubicación por HTTP con throttling.
- Envía métricas periódicas además de las métricas derivadas del movimiento.

---

## Dashboard

### Estructura principal

```text
dashboard/src/
├── app/
├── components/
├── lib/
└── ...
```

### Funcionalidades

- Login de admin.
- Vista en vivo del tracking.
- Cards de deliveries activos.
- Historial y detalle de viajes.
- Mapa de ruta histórica.
- Gestión de usuarios.
- Descarga de APK.

### Socket del dashboard

- Usa cookie `token`.
- Conecta al backend por Socket.IO.
- Emite `join-admin` al conectar.
- Escucha `locationUpdate`, `tripStarted`, `tripStopped`, `tripCompleted`, `metricsUpdate`, `forceLogout`.

---

## Modelos principales

### User

```typescript
{
  id: string,
  name: string,
  email?: string,
  employeeId?: string,
  password: string,
  role: 'admin' | 'delivery',
  phone?: string,
  isActive: boolean,
  lastLogin?: Date
}
```

### Trip

```typescript
{
  id: string,
  deliveryId: string,
  status: 'active' | 'completed' | 'paused',
  startTime: Date,
  endTime?: Date,
  mileage: number,
  duration: number,
  averageSpeed: number,
  realTimeMetrics: object
}
```

### Location

```typescript
{
  id: string,
  tripId: string,
  latitude: number,
  longitude: number,
  accuracy?: number,
  speed?: number,
  heading?: number,
  timestamp: Date
}
```

---

## Deploy

### Infraestructura

- VPS: `186.64.123.15`
- Backend: puerto `5000`
- Dashboard: puerto `3000`
- Reverse proxy: Nginx
- Process manager: PM2

### Producción

```bash
pm2 start ecosystem.config.js
pm2 status
pm2 logs boston-backend
pm2 logs boston-dashboard
pm2 restart boston-backend
pm2 restart boston-dashboard
```

### Actualización en VPS

```bash
cd /var/www/boston-tracker
git pull

cd backend
npm install
npm run build
pm2 restart boston-backend

cd ../dashboard
npm install
npm run build
pm2 restart boston-dashboard
```

---

## Variables de entorno

### Backend

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
JWT_REFRESH_EXPIRE=30d
```

### Dashboard

```env
NEXT_PUBLIC_SOCKET_URL=http://186.64.123.15:5000
```

### Flutter

- `flutter_app/lib/services/api_service.dart` tiene la URL base del backend hardcodeada.
- Si cambiás entorno, tenés que actualizar esa URL.

---

## Bugs ya resueltos

| Bug | Causa | Fix |
|---|---|---|
| El pin no aparecía al iniciar viaje | La primera posición quedaba filtrada | Se permitió la primera ubicación válida |
| El viaje se detenía solo demasiado pronto | Polling sin margen al arrancar | Grace period de arranque |
| `maxSpeed` quedaba en 0 | Cálculo incompleto en historial | Se ajustó la lógica de métricas |
| El socket no seguía después de restaurar sesión | El usuario recuperado perdía el `token` | Se reinyecta token en auth restaurada |
| El delivery no recibía destinos al reabrir la app | No se re-hacía `join-delivery` correctamente | Se rejoin al conectar y reconectar |

---

## Estado actual

### Funcionando

- Login admin y delivery
- Refresh de sesión en Flutter
- Inicio y detención de viajes
- GPS tracking en Android
- Envío de ubicación y métricas
- Dashboard con mapa en vivo
- Asignación de destinos por socket
- Persistencia local de la última destination
- Force logout por eliminación o desactivación
- Historial de viajes
- Gestión de usuarios

### Pendiente

- Multitenancy real
- White-label por tenant
- Onboarding por QR
- Billing
- Super-admin panel

---

## Desarrollo local

### Backend

```bash
cd backend
npm install
npm run dev
```

### Dashboard

```bash
cd dashboard
npm install
npm run dev
```

### Flutter

```bash
cd flutter_app
flutter pub get
flutter run -d <device-id>
```

### Build APK

```bash
cd flutter_app
flutter build apk --release
```

---

## Notas para colaboradores

1. El backend usa JWT en `Authorization: Bearer <token>`.
2. La app Flutter guarda el `token` en almacenamiento seguro, no en `SharedPreferences`.
3. El delivery socket depende de `join-delivery` con el `userId` correcto.
4. El dashboard usa `join-admin` después de conectarse.
5. El backend puede reenviar la última `deliveryDestination` al reconectar.
6. El build del backend debe compilarse antes de reiniciar PM2.

