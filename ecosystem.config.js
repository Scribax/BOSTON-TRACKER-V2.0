// ============================================================
// PM2 ECOSYSTEM - BOSTON TRACKER
// Gestiona: backend (Node/TS compilado) + dashboard (Next.js)
// Uso: pm2 start ecosystem.config.js
// ============================================================

module.exports = {
  apps: [
    // ----------------------------------------------------------
    // BACKEND - Express + Socket.IO + PostgreSQL
    // ----------------------------------------------------------
    {
      name: 'boston-backend',
      script: './backend/dist/server.js',
      cwd: '/var/www/boston-tracker',
      instances: 1,
      autorestart: true,
      watch: false,
      max_memory_restart: '500M',
      env: {
        NODE_ENV: 'production',
        PORT: 5000,
      },
      error_file: '/var/log/pm2/boston-backend-error.log',
      out_file: '/var/log/pm2/boston-backend-out.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss',
    },

    // ----------------------------------------------------------
    // DASHBOARD - Next.js
    // ----------------------------------------------------------
    {
      name: 'boston-dashboard',
      script: 'node_modules/.bin/next',
      args: 'start',
      cwd: '/var/www/boston-tracker/dashboard',
      instances: 1,
      autorestart: true,
      watch: false,
      max_memory_restart: '500M',
      env: {
        NODE_ENV: 'production',
        PORT: 3000,
      },
      error_file: '/var/log/pm2/boston-dashboard-error.log',
      out_file: '/var/log/pm2/boston-dashboard-out.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss',
    },
  ],
};
