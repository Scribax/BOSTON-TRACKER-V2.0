// ============================================================
// SEED - Crea usuarios iniciales en la BD
// Uso: npx tsx src/seed.ts  O  node dist/seed.js
// ============================================================

import dotenv from 'dotenv';
dotenv.config();

import { sequelize, testConnection } from './config/database';
import User from './models/User';

const seed = async () => {
  const connected = await testConnection();
  if (!connected) {
    console.error('❌ No se pudo conectar a la base de datos');
    process.exit(1);
  }

  await sequelize.sync({ alter: false });

  const users = [
    {
      name: 'Administrador Boston',
      email: 'admin@bostonburgers.com',
      employeeId: 'ADM001',
      password: 'admin123',
      role: 'admin' as const,
      isActive: true,
    },
    {
      name: 'Juan Pérez',
      employeeId: 'DEL001',
      password: 'delivery123',
      role: 'delivery' as const,
      isActive: true,
    },
    {
      name: 'María González',
      employeeId: 'DEL002',
      password: 'delivery123',
      role: 'delivery' as const,
      isActive: true,
    },
    {
      name: 'Carlos López',
      employeeId: 'DEL003',
      password: 'delivery123',
      role: 'delivery' as const,
      isActive: true,
    },
  ];

  for (const userData of users) {
    const existing = await User.findOne({
      where: userData.employeeId
        ? { employeeId: userData.employeeId }
        : { email: userData.email },
    });

    if (existing) {
      console.log(`  ⚠️  Usuario ya existe: ${userData.name} (${userData.employeeId || userData.email})`);
      continue;
    }

    await User.create(userData as any);
    console.log(`  ✅ Creado: ${userData.name} [${userData.role}] - ID: ${userData.employeeId || userData.email}`);
  }

  console.log('\n✅ Seed completado');
  await sequelize.close();
  process.exit(0);
};

seed().catch((err) => {
  console.error('❌ Error en seed:', err);
  process.exit(1);
});
