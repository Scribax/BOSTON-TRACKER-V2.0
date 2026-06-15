// ==========================================
// TRIPS ROUTES - TypeScript Edition
// ==========================================

import { Router, Response } from 'express';

import { Trip, User, Location } from '@models/index';
import { authenticate, authorize } from '@middleware/auth';
import type { ApiResponse, AuthenticatedRequest } from '../types/index';

const router = Router();

// ==========================================
// GET TRIP HISTORY (Admin)
// ==========================================

router.get('/history', authenticate, authorize('admin'), async (
  req: AuthenticatedRequest,
  res: Response<ApiResponse>
): Promise<void> => {
  try {
    const page = parseInt(req.query.page as string) || 1;
    const limit = parseInt(req.query.limit as string) || 20;
    const sortBy = (req.query.sortBy as string) || 'endTime';
    const sortOrder = (req.query.sortOrder as string) || 'DESC';
    const offset = (page - 1) * limit;

    const { count, rows: trips } = await Trip.findAndCountAll({
      where: { status: 'completed' },
      include: [
        {
          model: User,
          as: 'delivery',
          attributes: ['id', 'name', 'employeeId'],
        },
      ],
      order: [[sortBy, sortOrder]],
      limit,
      offset,
    });

    const tripsData = await Promise.all(
      trips.map(async (trip) => {
        const locationCount = await Location.count({
          where: { tripId: (trip as any).id },
        });

        // Calculate max speed from location records
        const maxSpeedRecord = await Location.findOne({
          where: { tripId: (trip as any).id },
          order: [['speed', 'DESC']],
          attributes: ['speed'],
        });
        const maxSpeed = maxSpeedRecord ? ((maxSpeedRecord as any).speed || 0) : 0;

        return {
          id: (trip as any).id,
          deliveryId: (trip as any).deliveryId,
          delivery: (trip as any).delivery ? {
            name: (trip as any).delivery.name,
            employeeId: (trip as any).delivery.employeeId,
          } : null,
          startTime: (trip as any).startTime,
          endTime: (trip as any).endTime,
          totalMileage: (trip as any).mileage || 0,
          totalTime: ((trip as any).duration || trip.getDuration() || 0) * 60,
          averageSpeed: (trip as any).averageSpeed || trip.getAverageSpeed() || 0,
          maxSpeed,
          status: (trip as any).status,
          totalLocations: locationCount,
        };
      })
    );

    res.json({
      success: true,
      data: tripsData,
      meta: {
        count,
        page,
        total: count,
        limit,
      },
    });
  } catch (error) {
    console.error('Get trip history error:', error);
    res.status(500).json({
      success: false,
      message: 'Error interno del servidor',
      error: error instanceof Error ? error.message : 'Unknown error',
    });
  }
});

// ==========================================
// GET TRIP DETAILS
// ==========================================

router.get('/details/:id', authenticate, authorize('admin'), async (
  req: AuthenticatedRequest,
  res: Response<ApiResponse>
): Promise<void> => {
  try {
    const { id } = req.params;

    const trip = await Trip.findByPk(id, {
      include: [
        {
          model: User,
          as: 'delivery',
          attributes: ['id', 'name', 'employeeId'],
        },
        {
          model: Location,
          as: 'tripLocations',
          order: [['timestamp', 'ASC']],
        },
      ],
    });

    if (!trip) {
      res.status(404).json({
        success: false,
        message: 'Viaje no encontrado',
        error: 'Trip not found',
      });
      return;
    }

    res.json({
      success: true,
      data: {
        id: (trip as any).id,
        deliveryId: (trip as any).deliveryId,
        employeeId: (trip as any).delivery?.employeeId,
        startTime: (trip as any).startTime,
        endTime: (trip as any).endTime,
        mileage: (trip as any).mileage,
        duration: trip.getDuration(),
        averageSpeed: trip.getAverageSpeed(),
        status: (trip as any).status,
        locations: (trip as any).tripLocations || [],
      },
    });
  } catch (error) {
    console.error('Get trip details error:', error);
    res.status(500).json({
      success: false,
      message: 'Error interno del servidor',
      error: error instanceof Error ? error.message : 'Unknown error',
    });
  }
});

// ==========================================
// DELETE TRIP (Admin)
// ==========================================

router.delete('/details/:id', authenticate, authorize('admin'), async (
  req: AuthenticatedRequest,
  res: Response<ApiResponse>
): Promise<void> => {
  try {
    const { id } = req.params;

    const trip = await Trip.findByPk(id);

    if (!trip) {
      res.status(404).json({
        success: false,
        message: 'Viaje no encontrado',
        error: 'Trip not found',
      });
      return;
    }

    if ((trip as any).status === 'active') {
      res.status(400).json({
        success: false,
        message: 'No se puede eliminar un viaje activo',
        error: 'Cannot delete active trip',
      });
      return;
    }

    // Delete associated locations first
    await Location.destroy({ where: { tripId: id } });
    await trip.destroy();

    res.json({
      success: true,
      message: 'Viaje eliminado exitosamente',
    });
  } catch (error) {
    console.error('Delete trip error:', error);
    res.status(500).json({
      success: false,
      message: 'Error interno del servidor',
      error: error instanceof Error ? error.message : 'Unknown error',
    });
  }
});

// ==========================================
// BULK DELETE TRIPS (Admin)
// ==========================================

router.delete('/history/bulk-delete', authenticate, authorize('admin'), async (
  req: AuthenticatedRequest,
  res: Response<ApiResponse>
): Promise<void> => {
  try {
    const ids = Array.isArray(req.body?.ids) ? req.body.ids : [];

    if (ids.length === 0) {
      res.status(400).json({
        success: false,
        message: 'No se recibieron viajes para eliminar',
        error: 'No trip ids provided',
      });
      return;
    }

    const trips = await Trip.findAll({ where: { id: ids } });
    const activeTrips = trips.filter((trip) => (trip as any).status === 'active');
    if (activeTrips.length > 0) {
      res.status(400).json({
        success: false,
        message: 'No se pueden eliminar viajes activos',
        error: 'Cannot delete active trips',
      });
      return;
    }

    for (const trip of trips) {
      await Location.destroy({ where: { tripId: (trip as any).id } });
      await trip.destroy();
    }

    res.json({
      success: true,
      message: 'Viajes eliminados exitosamente',
      data: { deleted: trips.length },
    });
  } catch (error) {
    console.error('Bulk delete trips error:', error);
    res.status(500).json({
      success: false,
      message: 'Error interno del servidor',
      error: error instanceof Error ? error.message : 'Unknown error',
    });
  }
});

export default router;
