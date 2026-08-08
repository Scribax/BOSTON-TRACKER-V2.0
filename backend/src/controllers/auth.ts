// ==========================================
// AUTH CONTROLLER - TypeScript Edition
// ==========================================

import { Response } from 'express';
import jwt from 'jsonwebtoken';
import { Op } from 'sequelize';

import { User, Trip, Location } from '@models/index';
import { Server as SocketIOServer } from 'socket.io';
import { calculateTotalDistance, filterGPSNoise, calculateAverageSpeed } from '@utils/geo';
import type {
  ApiResponse,
  AuthenticatedRequest,
  LoginRequest,
  LoginResponse,
  RefreshRequest,
  UserDTO,
  CreateUserRequest,
} from '../types/index';

const JWT_SECRET = process.env.JWT_SECRET || 'your-secret-key';
const JWT_EXPIRE = process.env.JWT_EXPIRE || '7d';
const JWT_REFRESH_EXPIRE = process.env.JWT_REFRESH_EXPIRE || '30d';

/**
 * Generate JWT token
 */
const generateToken = (id: string, role: string): string => {
  return jwt.sign({ id, role }, JWT_SECRET as string, { expiresIn: JWT_EXPIRE } as any);
};

const generateRefreshToken = (id: string, role: string): string => {
  return jwt.sign({ id, role, type: 'refresh' }, JWT_SECRET as string, { expiresIn: JWT_REFRESH_EXPIRE } as any);
};

/**
 * Convert User to UserDTO (remove sensitive data)
 */
const toUserDTO = (user: User): UserDTO => ({
  id: user.id,
  name: user.name,
  email: user.email,
  employeeId: user.employeeId,
  role: user.role,
  phone: user.phone,
  isActive: user.isActive,
  lastLogin: user.lastLogin,
});

// ==========================================
// LOGIN
// ==========================================

export const login = async (
  req: AuthenticatedRequest,
  res: Response<ApiResponse<LoginResponse>>
): Promise<void> => {
  try {
    const { email, employeeId, password } = req.body as LoginRequest;

    // Validate input
    if (!password || (!email && !employeeId)) {
      res.status(400).json({
        success: false,
        message: 'Por favor proporciona credenciales válidas',
        error: 'Missing credentials',
      });
      return;
    }

    // Find user by email or employeeId (case-insensitive)
    const identifier = (email || employeeId || '').trim();
    const user: User | null = await User.findOne({
      where: {
        [Op.or]: [
          { email: { [Op.iLike]: identifier } },
          { employeeId: { [Op.iLike]: identifier } },
        ],
      },
    });

    // Verify user and password
    if (!user || !(await user.matchPassword(password))) {
      res.status(401).json({
        success: false,
        message: 'Credenciales inválidas',
        error: 'Invalid credentials',
      });
      return;
    }

    // Check if active
    if (!user.isActive) {
      res.status(401).json({
        success: false,
        message: 'Usuario desactivado',
        error: 'User inactive',
      });
      return;
    }

    // Update last login
    user.lastLogin = new Date();
    await user.save({ validate: false } as any);

    // Generate token
    const token = generateToken(user.id, user.role);
    const refreshToken = generateRefreshToken(user.id, user.role);

    res.json({
      success: true,
      message: 'Login exitoso',
      data: {
        success: true,
        message: 'Login exitoso',
        token,
        refreshToken,
        user: toUserDTO(user),
      },
    });
  } catch (error) {
    console.error('Login error:', error);
    res.status(500).json({
      success: false,
      message: 'Error interno del servidor',
      error: error instanceof Error ? error.message : 'Unknown error',
    });
  }
};

// ==========================================
// GET CURRENT USER
// ==========================================

export const getCurrentUser = async (
  req: AuthenticatedRequest,
  res: Response<ApiResponse<{ user: UserDTO }>>
): Promise<void> => {
  try {
    if (!req.user) {
      res.status(401).json({
        success: false,
        message: 'Usuario no autenticado',
        error: 'Not authenticated',
      });
      return;
    }

    res.json({
      success: true,
      data: { user: req.user },
    });
  } catch (error) {
    console.error('Get current user error:', error);
    res.status(500).json({
      success: false,
      message: 'Error interno del servidor',
      error: error instanceof Error ? error.message : 'Unknown error',
    });
  }
};

// ==========================================
// REFRESH TOKEN
// ==========================================

export const refreshToken = async (
  req: AuthenticatedRequest,
  res: Response<ApiResponse<LoginResponse>>
): Promise<void> => {
  try {
    const { refreshToken: token } = req.body as RefreshRequest;

    if (!token) {
      res.status(400).json({
        success: false,
        message: 'Refresh token requerido',
        error: 'Missing refresh token',
      });
      return;
    }

    const decoded = jwt.verify(token, JWT_SECRET) as { id: string; role?: string; type?: string };
    if (decoded.type !== 'refresh') {
      res.status(401).json({
        success: false,
        message: 'Refresh token inválido',
        error: 'Invalid refresh token',
      });
      return;
    }

    const user = await User.findByPk(decoded.id);
    if (!user || !user.isActive) {
      res.status(401).json({
        success: false,
        message: 'Usuario no válido',
        error: 'User invalid',
      });
      return;
    }

    const accessToken = generateToken(user.id, user.role);
    const newRefreshToken = generateRefreshToken(user.id, user.role);

    res.json({
      success: true,
      message: 'Token renovado',
      data: {
        success: true,
        message: 'Token renovado',
        token: accessToken,
        refreshToken: newRefreshToken,
        user: toUserDTO(user),
      },
    });
  } catch (error) {
    res.status(401).json({
      success: false,
      message: 'Refresh expirado o inválido',
      error: error instanceof Error ? error.message : 'Invalid refresh token',
    });
  }
};

// ==========================================
// LOGOUT
// ==========================================

export const logout = async (
  _req: AuthenticatedRequest,
  res: Response<ApiResponse>
): Promise<void> => {
  // In JWT, logout is handled client-side by removing the token
  res.json({
    success: true,
    message: 'Sesión cerrada exitosamente',
  });
};

// ==========================================
// GET ALL USERS (Admin only)
// ==========================================

export const getAllUsers = async (
  req: AuthenticatedRequest,
  res: Response<ApiResponse<{ users: UserDTO[]; count: number }>>
): Promise<void> => {
  try {
    const users = await User.findAll({
      attributes: { exclude: ['password'] },
      order: [['createdAt', 'DESC']],
    });

    // Get active trip info for deliveries
    const usersWithTripInfo = await Promise.all(
      users.map(async (user) => {
        const userDTO = toUserDTO(user);

        if (user.role === 'delivery') {
          const activeTrip = await Trip.findOne({
            where: { deliveryId: user.id, status: 'active' },
          });

          if (activeTrip) {
            return {
              ...userDTO,
              hasActiveTrip: true,
              tripId: (activeTrip as any).id,
            };
          }
        }

        return userDTO;
      })
    );

    res.json({
      success: true,
      data: usersWithTripInfo as UserDTO[],
      count: users.length,
    } as any);
  } catch (error) {
    console.error('Get all users error:', error);
    res.status(500).json({
      success: false,
      message: 'Error interno del servidor',
      error: error instanceof Error ? error.message : 'Unknown error',
    });
  }
};

// ==========================================
// CREATE USER (Admin only)
// ==========================================

export const createUser = async (
  req: AuthenticatedRequest,
  res: Response<ApiResponse<{ user: UserDTO }>>
): Promise<void> => {
  try {
    const { name, email, employeeId, password, role, phone } = req.body as CreateUserRequest;

    // Validation
    if (!name || !password || !role) {
      res.status(400).json({
        success: false,
        message: 'Nombre, contraseña y rol son requeridos',
        error: 'Missing required fields',
      });
      return;
    }

    // Validate role-specific fields
    if (role === 'admin' && !email) {
      res.status(400).json({
        success: false,
        message: 'Email es requerido para administradores',
        error: 'Email required for admin',
      });
      return;
    }

    if (role === 'delivery' && !employeeId) {
      res.status(400).json({
        success: false,
        message: 'ID de empleado es requerido para deliveries',
        error: 'EmployeeId required for delivery',
      });
      return;
    }

    // Check for duplicates
    if (email) {
      const existingEmail = await User.findOne({ where: { email } });
      if (existingEmail) {
        res.status(400).json({
          success: false,
          message: 'Email ya existe',
          error: 'Email already exists',
        });
        return;
      }
    }

    if (employeeId) {
      const existingEmployeeId = await User.findOne({ where: { employeeId } });
      if (existingEmployeeId) {
        res.status(400).json({
          success: false,
          message: 'ID de empleado ya existe',
          error: 'EmployeeId already exists',
        });
        return;
      }
    }

    // Create user - only pass defined fields to avoid NULL unique constraint issues
    const createData: any = { name, password, role, isActive: true };
    if (email) createData.email = email;
    if (employeeId) createData.employeeId = employeeId;
    if (phone) createData.phone = phone;

    const user = await User.create(createData);

    res.status(201).json({
      success: true,
      message: 'Usuario creado exitosamente',
      data: { user: toUserDTO(user) },
    });
  } catch (error) {
    console.error('Create user error:', error);
    const errMsg = error instanceof Error ? error.message : String(error);
    res.status(500).json({
      success: false,
      message: `Error creando usuario: ${errMsg}`,
      error: errMsg,
    });
  }
};

// ==========================================
// UPDATE USER (Admin only)
// ==========================================

export const updateUser = async (
  req: AuthenticatedRequest,
  res: Response<ApiResponse<{ user: UserDTO }>>
): Promise<void> => {
  try {
    const { id } = req.params;
    const { name, email, employeeId, password, role, phone, isActive } = req.body;

    const user = await User.findByPk(id);

    if (!user) {
      res.status(404).json({
        success: false,
        message: 'Usuario no encontrado',
        error: 'User not found',
      });
      return;
    }

    // Update fields
    if (name) user.name = name;
    if (email) user.email = email;
    if (employeeId) user.employeeId = employeeId;
    if (password) user.password = password;
    if (role) user.role = role;
    if (phone) user.phone = phone;
    if (typeof isActive === 'boolean') user.isActive = isActive;

    await user.save();

    // If deactivating, stop active trip and force logout on device
    if (isActive === false) {
      const io = getIO(req);
      await stopActiveTrip(id, io);
      io.to(`delivery-${id}`).emit('forceLogout', {
        reason: 'Tu cuenta fue desactivada por el administrador.',
      });
    }

    res.json({
      success: true,
      message: 'Usuario actualizado exitosamente',
      data: { user: toUserDTO(user) },
    });
  } catch (error) {
    console.error('Update user error:', error);
    res.status(500).json({
      success: false,
      message: 'Error interno del servidor',
      error: error instanceof Error ? error.message : 'Unknown error',
    });
  }
};

// ==========================================
// DELETE USER (Admin only)
// ==========================================

const getIO = (req: AuthenticatedRequest): SocketIOServer => {
  return (req as AuthenticatedRequest & { io: SocketIOServer }).io;
};

const stopActiveTrip = async (userId: string, io: SocketIOServer) => {
  const activeTrip = await Trip.findOne({ where: { deliveryId: userId, status: 'active' } });
  if (!activeTrip) return;

  const locations = await Location.findAll({
    where: { tripId: (activeTrip as any).id },
    order: [['timestamp', 'ASC']],
  });
  const filtered = filterGPSNoise(locations as unknown as Location[]);
  const finalMileage = calculateTotalDistance(filtered);
  const finalDuration = activeTrip.getDuration();
  const finalAvgSpeed = calculateAverageSpeed(filtered, finalDuration);

  (activeTrip as any).endTime = new Date();
  (activeTrip as any).status = 'completed';
  (activeTrip as any).mileage = finalMileage;
  (activeTrip as any).duration = finalDuration;
  (activeTrip as any).averageSpeed = finalAvgSpeed;
  await activeTrip.save();

  io.to('admins').emit('tripStopped', {
    tripId: (activeTrip as any).id,
    deliveryId: userId,
    endTime: (activeTrip as any).endTime,
  });
};

export const deleteUser = async (
  req: AuthenticatedRequest,
  res: Response<ApiResponse>
): Promise<void> => {
  try {
    const { id } = req.params;

    const user = await User.findByPk(id);

    if (!user) {
      res.status(404).json({
        success: false,
        message: 'Usuario no encontrado',
        error: 'User not found',
      });
      return;
    }

    const io = getIO(req);

    // Stop any active trip first
    await stopActiveTrip(id, io);

    // Force logout on the device via socket
    io.to(`delivery-${id}`).emit('forceLogout', {
      reason: 'Tu cuenta fue eliminada por el administrador.',
    });

    // Hard delete
    await user.destroy();

    res.json({
      success: true,
      message: 'Usuario eliminado exitosamente',
    });
  } catch (error) {
    console.error('Delete user error:', error);
    res.status(500).json({
      success: false,
      message: 'Error interno del servidor',
      error: error instanceof Error ? error.message : 'Unknown error',
    });
  }
};
