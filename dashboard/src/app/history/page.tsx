'use client';

import { useState, useEffect } from 'react';
import DashboardLayout from '@/components/DashboardLayout';
import api from '@/lib/api';
import { Trip } from '@/lib/types';
import { History, Clock, Route, Gauge, Calendar } from 'lucide-react';

export default function HistoryPage() {
  const [trips, setTrips] = useState<Trip[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetchTrips();
  }, []);

  const fetchTrips = async () => {
    try {
      const res = await api.get('/trips/history?limit=50');
      const data = res.data?.data || res.data || [];
      setTrips(Array.isArray(data) ? data : []);
    } catch (err) {
      console.error('Error fetching trips:', err);
    } finally {
      setLoading(false);
    }
  };

  const formatDuration = (seconds: number) => {
    if (!seconds) return '0m';
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    if (h > 0) return `${h}h ${m}m`;
    return `${m}m`;
  };

  const formatDistance = (km: number) => {
    if (!km) return '0 m';
    if (km < 1) return `${(km * 1000).toFixed(0)} m`;
    return `${km.toFixed(2)} km`;
  };

  return (
    <DashboardLayout>
      <div className="p-6">
        <div className="flex items-center justify-between mb-6">
          <div className="flex items-center gap-3">
            <History className="w-6 h-6 text-red-600" />
            <h2 className="text-xl font-bold text-gray-900">Historial de Viajes</h2>
          </div>
          <span className="text-sm text-gray-500">{trips.length} viajes completados</span>
        </div>

        {loading ? (
          <div className="flex items-center justify-center py-20">
            <div className="w-8 h-8 border-3 border-red-600 border-t-transparent rounded-full animate-spin" />
          </div>
        ) : trips.length === 0 ? (
          <div className="text-center py-20">
            <History className="w-16 h-16 text-gray-300 mx-auto mb-4" />
            <p className="text-gray-500 font-medium">No hay viajes completados</p>
          </div>
        ) : (
          <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
            <table className="w-full">
              <thead className="bg-gray-50 border-b border-gray-200">
                <tr>
                  <th className="px-4 py-3 text-left text-xs font-semibold text-gray-600 uppercase">Delivery</th>
                  <th className="px-4 py-3 text-left text-xs font-semibold text-gray-600 uppercase">Fecha</th>
                  <th className="px-4 py-3 text-left text-xs font-semibold text-gray-600 uppercase">Duración</th>
                  <th className="px-4 py-3 text-left text-xs font-semibold text-gray-600 uppercase">Distancia</th>
                  <th className="px-4 py-3 text-left text-xs font-semibold text-gray-600 uppercase">Vel. Promedio</th>
                  <th className="px-4 py-3 text-left text-xs font-semibold text-gray-600 uppercase">Vel. Máx</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {trips.map((trip) => (
                  <tr key={trip.id} className="hover:bg-gray-50 transition-colors">
                    <td className="px-4 py-3">
                      <div>
                        <p className="text-sm font-medium text-gray-900">
                          {trip.delivery?.name || 'N/A'}
                        </p>
                        <p className="text-xs text-gray-500">
                          {trip.delivery?.employeeId || trip.deliveryId.slice(0, 8)}
                        </p>
                      </div>
                    </td>
                    <td className="px-4 py-3 text-sm text-gray-600">
                      {new Date(trip.startTime).toLocaleDateString('es-AR', {
                        day: '2-digit',
                        month: '2-digit',
                        year: 'numeric',
                      })}
                    </td>
                    <td className="px-4 py-3 text-sm text-gray-600">
                      {formatDuration(trip.totalTime)}
                    </td>
                    <td className="px-4 py-3 text-sm text-gray-600">
                      {formatDistance(trip.totalMileage)}
                    </td>
                    <td className="px-4 py-3 text-sm text-gray-600">
                      {trip.averageSpeed?.toFixed(0) || 0} km/h
                    </td>
                    <td className="px-4 py-3 text-sm text-gray-600">
                      {trip.maxSpeed?.toFixed(0) || 0} km/h
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </DashboardLayout>
  );
}
