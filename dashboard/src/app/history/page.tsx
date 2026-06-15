'use client';

import { useState, useEffect, useMemo } from 'react';
import dynamic from 'next/dynamic';
import DashboardLayout from '@/components/DashboardLayout';
import api from '@/lib/api';
import { Trip } from '@/lib/types';
import { History, MapPin, X, Search, Download, Trash2, CheckSquare, Square } from 'lucide-react';

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
  const [selectedTripIds, setSelectedTripIds] = useState<string[]>([]);
  const [deleting, setDeleting] = useState(false);

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

  const [hideShort, setHideShort] = useState(true);

  const filtered = useMemo(() => {
    return trips.filter((t) => {
      if (hideShort && (t.totalTime || 0) < 60) return false;
      if (filterDelivery) {
        const name = (t.delivery?.name || '').toLowerCase();
        const empId = (t.delivery?.employeeId || '').toLowerCase();
        if (!name.includes(filterDelivery.toLowerCase()) && !empId.includes(filterDelivery.toLowerCase())) return false;
      }
      if (filterDateFrom && new Date(t.startTime) < new Date(filterDateFrom)) return false;
      if (filterDateTo && new Date(t.startTime) > new Date(filterDateTo + 'T23:59:59')) return false;
      return true;
    });
  }, [trips, filterDelivery, filterDateFrom, filterDateTo, hideShort]);

  const openRoute = async (trip: Trip) => {
    setSelectedTrip(trip);
    setLoadingRoute(true);
    try {
      const res = await api.get(`/trips/details/${trip.id}`);
      setRouteLocations(res.data?.data?.locations || []);
    } catch { setRouteLocations([]); }
    finally { setLoadingRoute(false); }
  };

  const exportCSV = () => {
    const headers = ['Delivery', 'ID Empleado', 'Fecha', 'Hora Inicio', 'Hora Fin', 'Duración', 'Distancia (km)', 'Vel. Prom (km/h)', 'Vel. Máx (km/h)'];
    const rows = filtered.map(t => [
      t.delivery?.name || 'N/A',
      t.delivery?.employeeId || '',
      new Date(t.startTime).toLocaleDateString('es-AR'),
      new Date(t.startTime).toLocaleTimeString('es-AR', { hour: '2-digit', minute: '2-digit' }),
      t.endTime ? new Date(t.endTime).toLocaleTimeString('es-AR', { hour: '2-digit', minute: '2-digit' }) : '-',
      fmt(t.totalTime),
      t.totalMileage?.toFixed(2) || '0',
      t.averageSpeed?.toFixed(0) || '0',
      t.maxSpeed?.toFixed(0) || '0',
    ]);
    const csv = [headers, ...rows].map(r => r.map(v => `"${v}"`).join(',')).join('\n');
    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url; a.download = `historial-viajes-${new Date().toISOString().slice(0,10)}.csv`;
    a.click(); URL.revokeObjectURL(url);
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

  const toggleTripSelection = (tripId: string) => {
    setSelectedTripIds((prev) =>
      prev.includes(tripId) ? prev.filter((id) => id !== tripId) : [...prev, tripId]
    );
  };

  const selectAllFiltered = () => {
    const ids = filtered.map((trip) => trip.id);
    setSelectedTripIds(ids);
  };

  const clearSelection = () => {
    setSelectedTripIds([]);
  };

  const deleteSelectedTrips = async () => {
    if (selectedTripIds.length === 0) return;
    if (!confirm(`¿Eliminar ${selectedTripIds.length} viajes seleccionados?`)) return;
    setDeleting(true);
    try {
      await api.delete('/trips/history/bulk-delete', { data: { ids: selectedTripIds } });
      setTrips((prev) => prev.filter((trip) => !selectedTripIds.includes(trip.id)));
      setSelectedTripIds([]);
      if (selectedTrip && selectedTripIds.includes(selectedTrip.id)) {
        setSelectedTrip(null);
        setRouteLocations([]);
      }
    } catch (err) {
      console.error('Error deleting selected trips:', err);
      alert('No se pudieron eliminar algunos viajes');
    } finally {
      setDeleting(false);
    }
  };

  const deleteSingleTrip = async (tripId: string) => {
    if (!confirm('¿Eliminar este viaje?')) return;
    try {
      await api.delete(`/trips/details/${tripId}`);
      setTrips((prev) => prev.filter((trip) => trip.id !== tripId));
      setSelectedTripIds((prev) => prev.filter((id) => id !== tripId));
      if (selectedTrip?.id === tripId) {
        setSelectedTrip(null);
        setRouteLocations([]);
      }
    } catch (err) {
      console.error('Error deleting trip:', err);
      alert('No se pudo eliminar el viaje');
    }
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
          <div className="flex items-center gap-3">
            <span className="text-sm text-gray-500">{filtered.length} de {trips.length} viajes</span>
            {selectedTripIds.length > 0 && (
              <span className="text-sm text-red-600 font-medium">
                {selectedTripIds.length} seleccionados
              </span>
            )}
            <label className="flex items-center gap-1.5 text-xs text-gray-500 cursor-pointer select-none">
              <input type="checkbox" checked={hideShort} onChange={e => setHideShort(e.target.checked)} className="rounded" />
              Ocultar &lt;1min
            </label>
            {filtered.length > 0 && (
              <button
                onClick={selectAllFiltered}
                className="px-3 py-1.5 bg-gray-100 hover:bg-gray-200 text-gray-700 text-xs font-medium rounded-lg flex items-center gap-1.5 transition-colors"
              >
                <CheckSquare className="w-3.5 h-3.5" />
                Seleccionar todos
              </button>
            )}
            {selectedTripIds.length > 0 && (
              <>
                <button
                  onClick={clearSelection}
                  className="px-3 py-1.5 bg-white hover:bg-gray-50 text-gray-700 text-xs font-medium rounded-lg border border-gray-200 transition-colors"
                >
                  Limpiar selección
                </button>
                <button
                  onClick={deleteSelectedTrips}
                  disabled={deleting}
                  className="px-3 py-1.5 bg-red-600 hover:bg-red-700 disabled:opacity-60 text-white text-xs font-medium rounded-lg flex items-center gap-1.5 transition-colors"
                >
                  <Trash2 className="w-3.5 h-3.5" />
                  {deleting ? 'Eliminando...' : 'Eliminar seleccionados'}
                </button>
              </>
            )}
            {filtered.length > 0 && (
              <button onClick={exportCSV}
                className="px-3 py-1.5 bg-green-600 hover:bg-green-700 text-white text-xs font-medium rounded-lg flex items-center gap-1.5 transition-colors">
                <Download className="w-3.5 h-3.5" /> Exportar CSV
              </button>
            )}
          </div>
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
                  <th className="px-4 py-3 text-left text-xs font-semibold text-gray-600 uppercase">Fecha / Hora</th>
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
                      <button
                        onClick={() => toggleTripSelection(trip.id)}
                        className="text-gray-500 hover:text-red-600"
                        title={selectedTripIds.includes(trip.id) ? 'Deseleccionar' : 'Seleccionar'}
                      >
                        {selectedTripIds.includes(trip.id) ? <CheckSquare className="w-4 h-4" /> : <Square className="w-4 h-4" />}
                      </button>
                    </td>
                    <td className="px-4 py-3">
                      <p className="text-sm font-medium text-gray-900">{trip.delivery?.name || 'N/A'}</p>
                      <p className="text-xs text-gray-500">{trip.delivery?.employeeId || trip.deliveryId?.slice(0, 8)}</p>
                    </td>
                    <td className="px-4 py-3 text-sm text-gray-600">
                      <p>{new Date(trip.startTime).toLocaleDateString('es-AR', { day: '2-digit', month: '2-digit', year: 'numeric' })}</p>
                      <p className="text-xs text-gray-400">
                        {new Date(trip.startTime).toLocaleTimeString('es-AR', { hour: '2-digit', minute: '2-digit' })}
                        {trip.endTime ? ` → ${new Date(trip.endTime).toLocaleTimeString('es-AR', { hour: '2-digit', minute: '2-digit' })}` : ''}
                      </p>
                    </td>
                    <td className="px-4 py-3 text-sm text-gray-600">{fmt(trip.totalTime)}</td>
                    <td className="px-4 py-3 text-sm text-gray-600">{fmtDist(trip.totalMileage)}</td>
                    <td className="px-4 py-3 text-sm text-gray-600">{trip.averageSpeed?.toFixed(0) || 0} km/h</td>
                    <td className="px-4 py-3 text-sm text-gray-600">{trip.maxSpeed?.toFixed(0) || 0} km/h</td>
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-2">
                        <button onClick={() => openRoute(trip)}
                          className="p-1.5 text-gray-400 hover:text-red-600 hover:bg-red-50 rounded transition-colors"
                          title="Ver ruta">
                          <MapPin className="w-4 h-4" />
                        </button>
                        <button
                          onClick={() => deleteSingleTrip(trip.id)}
                          className="p-1.5 text-gray-400 hover:text-red-600 hover:bg-red-50 rounded transition-colors"
                          title="Eliminar viaje"
                        >
                          <Trash2 className="w-4 h-4" />
                        </button>
                      </div>
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
