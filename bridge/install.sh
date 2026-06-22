#!/bin/bash
# Instala el servicio navius-sat-bridge en Ubuntu Touch.
# Ejecutar como root: sudo bash install.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "[install] Copiando script a /usr/local/lib/navius/..."
mkdir -p /usr/local/lib/navius
cp "$SCRIPT_DIR/navius-sat-bridge.py" /usr/local/lib/navius/
chmod +x /usr/local/lib/navius/navius-sat-bridge.py

echo "[install] Instalando servicio systemd..."
cp "$SCRIPT_DIR/navius-sat-bridge.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable navius-sat-bridge.service
systemctl start navius-sat-bridge.service

echo "[install] Estado del servicio:"
systemctl status navius-sat-bridge.service --no-pager

echo ""
echo "Instalación completada. El servicio arrancará automáticamente al iniciar."
echo "Logs: journalctl -u navius-sat-bridge -f"
