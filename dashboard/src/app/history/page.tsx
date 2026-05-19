'use client';

import { useState, useEffect, useMemo } from 'react';
import dynamic from 'next/dynamic';
import DashboardLayout from '@/components/DashboardLayout';
import api from '@/lib/api';
import { Trip } from '@/lib/types';
import { History, MapPin, X, Search } from 'lucide-react';

const TripRouteMap = dynamic(() => import('@/components/TripRouteMap'), { ssr: false });

export default function HistoryPage() {
  const [trips, setTrips] = useState<Trip[]>([]);
  const [loading, setLoading] = useState(true);
  const [filterDelivery, setFilterDelivery] = useState('');
  const [filterDateFrom, setFilterDateFrom] = useState('');
  const [filterDateTo, setFilterDateTo] = useState('');
  const [selectedTrip, setSelectedTrip] = useState<Trip | null>(null);
  const [routeLocations, setRouteLocations] = useState<any[]>([]);
  const [loadingRoute, setLoadingRoute] = useState(false);

  useEffect(() => { fetchTrips(); }, []);

  const fetchTrips = async () => {
    try {
      const res = await api.get('/trips/history?limit=200');
      const data = res.data?.data || res.data || [];
      setTrips(Array.isArray(data) ? data : []);
    } catch (err) {
      console.error('Error fetching trips:', err);
    } finally {
      setLoading(false);
    }
  };

  const filtered = useMemo(() => {
    return trips.filter((t) => {
      if (filterDelivery) {
        const name = (t.delivery?.name || '').toLowerCase();
        const empId = (t.delivery?.employeeId || '').toLowerCase();
        if (!name.includes(filterDelivery.toLowerCase()) && !empId.includes(filterDelivery.toLowerCase())) return false;
      }
      if (filterDateFrom && new Date(t.startTime) < new Date(filterDateFrom)) return false;
      if (filterDateTo && new Date(t.startTime) > new Date(filterDateTo + 'T23:59:59')) return false;
      return true;
    });
  }, [trips, filterDelivery, filterDateFrom, filterDateTo]);

  const openRoute = async (trip: Trip) => {
    setSelectedTrip(trip);
    setLoadingRoute(true);
    try {
      const res = await api.get(`/trips/details/${trip.id}`);
      setRouteLocations(res.data?.data?.locations || []);
    } catch { setRouteLocations([]); }
    finally { setLoadingRoute(false); }
  };

  const fmt = (s: number) => {
    if (!s) return '0m';
    const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60);
    return h > 0 ? `${h}h ${m}m` : `${m}m`;
  };
  const fmtDist = (km: number) => {
    if (!km) return '0 m';
    return km < 1 ? `${(km * 1000).toFixed(0)} m` : `${km.toFixed(2)} km`;
  };

  return (
    <DashboardLayout>
      <div className="p-6">
        {/* Header */}
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-3">
            <History className="w-6 h-6 text-red-600" />
            <h2 className="text-xl font-bold text-gray-900">Historial de Viajes</h2>
          </div>
          <span className="text-sm text-gray-500">{filtered.length} de {trips.length} viajes</span>
        </div>

        {/* Filters */}
        <div className="flex flex-wrap gap-3 mb-5">
          <div className="relative flex-1 min-w-[180px]">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" />
            <input
              type="text"
              placeholder="Buscar delivery..."
              value={filterDelivery}
              onChange={(e) => setFilterDelivery(e.target.value)}
              className="w-full pl-9 pr-3 py-2 border border-gray-200 rounded-lg text-sm focus:ring-2 focus:ring-red-500 outline-none"
            />
          </div>
          <input
            type="date"
            value={filterDateFrom}
            onChange={(e) => setFilterDateFrom(e.target.value)}
            className="px-3 py-2 border border-gray-200 rounded-lg text-sm focus:ring-2 focus:ring-red-500 outline-none"
          />
          <input
            type="date"
            value={filterDateTo}
            onChange={(e) => setFilterDateTo(e.target.value)}
            className="px-3 py-2 border border-gray-200 rounded-lg text-sm focus:ring-2 focus:ring-red-500 outline-none"
          />
          {(filterDelivery || filterDateFrom || filterDateTo) && (
            <button onClick={() => { setFilterDelivery(''); setFilterDateFrom(''); setFilterDateTo(''); }}
              className="px-3 py-2 text-sm text-red-600 hover:bg-red-50 rounded-lg flex items-center gap-1 border border-red-200">
              <X className="w-4 h-4" /> Limpiar
            </button>
          )}
        </div>

        {loading ? (
          <div className="flex items-center justify-center py-20">
            <div className="w-8 h-8 border-2 border-red-600 border-t-transparent rounded-full animate-spin" />
          </div>
        ) : filtered.length === 0 ? (
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
                  <th className="px-4 py-3 text-left text-xs font-semibold text-gray-600 uppercase">Vel. Prom</th>
                  <th className="px-4 py-3 text-left text-xs font-semibold text-gray-600 uppercase">Vel. Máx</th>
                  <th className="px-4 py-3 text-left text-xs font-semibold text-gray-600 uppercase">Ruta</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {filtered.map((trip) => (
                  <tr key={trip.id} className="hover:bg-gray-50 transition-colors">
                    <td className="px-4 py-3">
                      <p className="text-sm font-medium text-gray-900">{trip.delivery?.name || 'N/A'}</p>
                      <p className="text-xs text-gray-500">{trip.delivery?.employeeId || trip.deliveryId?.slice(0, 8)}</p>
                    </td>
                    <td className="px-4 py-3 text-sm text-gray-600">
                      {new Date(trip.startTime).toLocaleDateString('es-AR', { day: '2-digit', month: '2-digit', year: 'numeric' })}
                    </td>
                    <td className="px-4 py-3 text-sm text-gray-600">{fmt(trip.totalTime)}</td>
                    <td className="px-4 py-3 text-sm text-gray-600">{fmtDist(trip.totalMileage)}</td>
                    <td className="px-4 py-3 text-sm text-gray-600">{trip.averageSpeed?.toFixed(0) || 0} km/h</td>
                    <td className="px-4 py-3 text-sm text-gray-600">{trip.maxSpeed?.toFixed(0) || 0} km/h</td>
                    <td className="px-4 py-3">
                      <button onClick={() => openRoute(trip)}
                        className="p-1.5 text-gray-400 hover:text-red-600 hover:bg-red-50 rounded transition-colors"
                        title="Ver ruta">
                        <MapPin className="w-4 h-4" />
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {/* Route Modal */}
        {selectedTrip && (
          <div className="fixed inset-0 bg-black/60 z-50 flex items-center justify-center p-4">
            <div className="bg-white rounded-2xl shadow-2xl w-full max-w-3xl max-h-[90vh] flex flex-col">
              <div className="flex items-center justify-between p-4 border-b border-gray-200">
                <div>
                  <h3 className="font-bold text-gray-900">Ruta del viaje</h3>
                  <p className="text-sm text-gray-500">
                    {selectedTrip.delivery?.name} — {new Date(selectedTrip.startTime).toLocaleDateString('es-AR')}
                    {' · '}{fmtDist(selectedTrip.totalMileage)} · {fmt(selectedTrip.totalTime)}
                  </p>
                </div>
                <button onClick={() => { setSelectedTrip(null); setRouteLocations([]); }}
                  className="p-2 hover:bg-gray-100 rounded-lg transition-colors">
                  <X className="w-5 h-5" />
                </button>
              </div>
              <div className="flex-1 min-h-[400px]">
                {loadingRoute ? (
                  <div className="flex items-center justify-center h-full">
                    <div className="w-8 h-8 border-2 border-red-600 border-t-transparent rounded-full animate-spin" />
                  </div>
                ) : routeLocations.length === 0 ? (
                  <div className="flex items-center justify-center h-full text-gray-500">
                    Sin puntos GPS registrados para este viaje
                  </div>
                ) : (
                  <TripRouteMap locations={routeLocations} />
                )}
              </div>
            </div>
          </div>
        )}
      </div>
    </DashboardLayout>
  );
}
