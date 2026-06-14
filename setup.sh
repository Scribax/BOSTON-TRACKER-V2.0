#!/bin/bash
# ============================================================
# BOSTON TRACKER - UPDATE / DEPLOY SCRIPT
# Uso: bash setup.sh
# Ejecutar en el VPS dentro del repo clonado.
# Hace pull, instala dependencias, compila y reinicia PM2.
# ============================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[✓] $1${NC}"; }
warn() { echo -e "${YELLOW}[!] $1${NC}"; }
err()  { echo -e "${RED}[✗] $1${NC}"; exit 1; }

APP_DIR="/var/www/boston-tracker"
BACKEND_DIR="$APP_DIR/backend"
DASHBOARD_DIR="$APP_DIR/dashboard"
BRANCH="${BRANCH:-main}"

echo ""
echo "=============================================="
echo "  BOSTON TRACKER - UPDATE DEPLOY"
echo "  Directorio: $APP_DIR"
echo "  Branch: $BRANCH"
echo "=============================================="
echo ""

if [ "$(id -u)" -ne 0 ]; then
  err "Ejecuta este script como root o con sudo."
fi

if [ ! -d "$APP_DIR/.git" ]; then
  err "No existe un repositorio Git en $APP_DIR. Ejecuta primero el deploy inicial."
fi

cd "$APP_DIR"

log "Actualizando repositorio..."
git fetch origin "$BRANCH"
git pull --ff-only origin "$BRANCH"

log "Instalando dependencias del backend..."
cd "$BACKEND_DIR"
npm ci

log "Compilando backend..."
npm run build

log "Instalando dependencias del dashboard..."
cd "$DASHBOARD_DIR"
npm ci

log "Compilando dashboard..."
npm run build

log "Reiniciando servicios PM2..."
cd "$APP_DIR"
pm2 restart boston-backend --update-env
pm2 restart boston-dashboard --update-env
pm2 save

log "Verificando estado..."
pm2 status

echo ""
echo "=============================================="
echo -e "${GREEN}  DEPLOY COMPLETADO EXITOSAMENTE${NC}"
echo "=============================================="
echo ""
echo "  Backend:   pm2 restart boston-backend"
echo "  Dashboard: pm2 restart boston-dashboard"
echo "  Estado:    pm2 status"
echo "  Logs:      pm2 logs boston-backend --lines 50"
echo "             pm2 logs boston-dashboard --lines 50"
echo "=============================================="
