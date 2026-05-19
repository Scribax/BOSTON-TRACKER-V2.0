#!/bin/bash
# ============================================================
# BOSTON TRACKER - VPS DEPLOY SCRIPT
# VPS: 186.64.123.15 | Ubuntu 20.04+
# Instala: Node.js 20, PostgreSQL 15, Nginx, PM2
# Uso: bash deploy.sh
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓] $1${NC}"; }
warn() { echo -e "${YELLOW}[!] $1${NC}"; }
err()  { echo -e "${RED}[✗] $1${NC}"; exit 1; }

REPO_URL="https://github.com/Scribax/BOSTON-TRACKER-V2.0.git"
APP_DIR="/var/www/boston-tracker"
DOMAIN="bostonamerican.com"
SERVER_IP="186.64.123.15"

echo ""
echo "=============================================="
echo "  BOSTON TRACKER - DEPLOY COMPLETO VPS"
echo "  IP: $SERVER_IP | Dominio: $DOMAIN"
echo "=============================================="
echo ""

# ------------------------------------------------------------
# 1. SISTEMA BASE
# ------------------------------------------------------------
log "Actualizando sistema..."
apt-get update -qq && apt-get upgrade -y -qq

log "Instalando dependencias base..."
apt-get install -y -qq curl git build-essential nginx certbot python3-certbot-nginx ufw

# ------------------------------------------------------------
# 2. NODE.JS 20
# ------------------------------------------------------------
if ! command -v node &> /dev/null; then
  log "Instalando Node.js 20..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs
else
  log "Node.js ya instalado: $(node -v)"
fi

# ------------------------------------------------------------
# 3. PM2
# ------------------------------------------------------------
if ! command -v pm2 &> /dev/null; then
  log "Instalando PM2..."
  npm install -g pm2
fi
pm2 startup systemd -u root --hp /root > /dev/null 2>&1 || true

# ------------------------------------------------------------
# 4. POSTGRESQL 15
# ------------------------------------------------------------
if ! command -v psql &> /dev/null; then
  log "Instalando PostgreSQL 15..."
  curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql.gpg
  echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
  apt-get update -qq
  apt-get install -y postgresql-15 postgresql-client-15
  systemctl enable postgresql
  systemctl start postgresql
else
  log "PostgreSQL ya instalado"
fi

log "Configurando base de datos..."
sudo -u postgres psql <<EOF
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'boston_user') THEN
    CREATE USER boston_user WITH PASSWORD 'boston123';
  END IF;
END
\$\$;
CREATE DATABASE boston_tracker OWNER boston_user;
GRANT ALL PRIVILEGES ON DATABASE boston_tracker TO boston_user;
ALTER USER boston_user CREATEDB;
EOF
log "Base de datos 'boston_tracker' lista"

# ------------------------------------------------------------
# 5. CLONAR / ACTUALIZAR REPO
# ------------------------------------------------------------
if [ -d "$APP_DIR" ]; then
  warn "Directorio $APP_DIR ya existe. Borrando para instalación limpia..."
  rm -rf "$APP_DIR"
fi

log "Clonando repositorio..."
git clone "$REPO_URL" "$APP_DIR"
cd "$APP_DIR"

# ------------------------------------------------------------
# 6. BACKEND - Instalar y compilar
# ------------------------------------------------------------
log "Instalando dependencias del backend..."
cd "$APP_DIR/backend"
npm ci --production=false

log "Creando .env del backend..."
cat > .env <<ENVEOF
# ================================
# BOSTON TRACKER - PRODUCCIÓN
# ================================
PORT=5000
NODE_ENV=production

# PostgreSQL
DB_HOST=localhost
DB_PORT=5432
DB_NAME=boston_tracker
DB_USER=boston_user
DB_PASSWORD=boston123
DB_SSL=false

# JWT
JWT_SECRET=boston_tracker_super_secret_key_$(openssl rand -hex 16)
JWT_EXPIRE=7d

# CORS / URLs
FRONTEND_URL=http://$DOMAIN
BACKEND_URL=http://$DOMAIN:5000

# Servidor
SERVER_IP=$SERVER_IP
ENVEOF

log "Compilando TypeScript del backend..."
npm run build

# ------------------------------------------------------------
# 7. DASHBOARD - Instalar y compilar
# ------------------------------------------------------------
log "Instalando dependencias del dashboard..."
cd "$APP_DIR/dashboard"
npm ci

log "Creando .env.local del dashboard..."
cat > .env.local <<ENVEOF
NEXT_PUBLIC_API_URL=http://$SERVER_IP:5000/api
NEXT_PUBLIC_SOCKET_URL=http://$SERVER_IP:5000
ENVEOF

log "Compilando dashboard (Next.js)..."
npm run build

# ------------------------------------------------------------
# 8. PM2 - Levantar servicios
# ------------------------------------------------------------
log "Configurando PM2..."
cd "$APP_DIR"

pm2 delete all 2>/dev/null || true

pm2 start ecosystem.config.js
pm2 save

log "PM2 configurado"

# ------------------------------------------------------------
# 9. NGINX
# ------------------------------------------------------------
log "Configurando Nginx..."

cat > /etc/nginx/sites-available/boston-tracker <<NGINXEOF
server {
    listen 80;
    server_name $DOMAIN $SERVER_IP;

    # Dashboard (Next.js) en /
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_cache_bypass \$http_upgrade;
    }

    # Backend API en /api
    location /api {
        proxy_pass http://127.0.0.1:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_cache_bypass \$http_upgrade;
    }

    # Socket.IO WebSocket
    location /socket.io {
        proxy_pass http://127.0.0.1:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 86400;
    }
}
NGINXEOF

ln -sf /etc/nginx/sites-available/boston-tracker /etc/nginx/sites-enabled/boston-tracker
rm -f /etc/nginx/sites-enabled/default

nginx -t && systemctl reload nginx
log "Nginx configurado"

# ------------------------------------------------------------
# 10. FIREWALL
# ------------------------------------------------------------
log "Configurando firewall UFW..."
ufw --force reset > /dev/null
ufw default deny incoming > /dev/null
ufw default allow outgoing > /dev/null
ufw allow ssh > /dev/null
ufw allow 80/tcp > /dev/null
ufw allow 443/tcp > /dev/null
ufw allow 5000/tcp > /dev/null   # Backend directo (Flutter app)
ufw --force enable > /dev/null
log "Firewall configurado"

# ------------------------------------------------------------
# 11. SEED USUARIOS INICIALES
# ------------------------------------------------------------
log "Creando usuarios iniciales en la base de datos..."
cd "$APP_DIR/backend"
node dist/create-users.js 2>/dev/null || warn "Script create-users.js no encontrado, usar seed manual"

# ------------------------------------------------------------
# RESUMEN FINAL
# ------------------------------------------------------------
echo ""
echo "=============================================="
echo -e "${GREEN}  DEPLOY COMPLETADO EXITOSAMENTE${NC}"
echo "=============================================="
echo ""
echo "  Dashboard:  http://$SERVER_IP"
echo "  Backend API: http://$SERVER_IP:5000/api"
echo "  Health:     http://$SERVER_IP:5000/api/health"
echo ""
echo "  PM2 status: pm2 status"
echo "  Logs:       pm2 logs"
echo ""
echo "  Credenciales iniciales:"
echo "  Admin:    ID=ADM001 / pass=admin123"
echo "  Delivery: ID=DEL001 / pass=delivery123"
echo "=============================================="
