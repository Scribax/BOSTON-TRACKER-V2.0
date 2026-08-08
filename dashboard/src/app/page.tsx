'use client';

import { useState, useEffect, useCallback } from 'react';
import dynamic from 'next/dynamic';
import DashboardLayout from '@/components/DashboardLayout';
import ActiveDeliveryCard from '@/components/ActiveDeliveryCard';
import { getSocket } from '@/lib/socket';
import api from '@/lib/api';
import { ActiveDelivery, DeliveryDestination } from '@/lib/types';
import { Truck, Radio, Search, WifiOff, Focus, MapPin, X } from 'lucide-react';

const Map = dynamic(() => import('@/components/Map'), { ssr: false });

function playBeep() {
  try {
    const ctx = new (window.AudioContext || (window as any).webkitAudioContext)();
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.connect(gain); gain.connect(ctx.destination);
    osc.frequency.value = 880; osc.type = 'sine';
    gain.gain.setValueAtTime(0.3, ctx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.4);
    osc.start(ctx.currentTime); osc.stop(ctx.currentTime + 0.4);
  } catch {}
}

export default function TrackingPage() {
  const [deliveries, setDeliveries] = useState<ActiveDelivery[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [search, setSearch] = useState('');
  const [centerRequest, setCenterRequest] = useState(0);
  const [menuPoint, setMenuPoint] = useState<{ latitude: number; longitude: number; x: number; y: number } | null>(null);
  const [destinationTimeline, setDestinationTimeline] = useState<Record<string, DeliveryDestination[]>>({});

  const fetchActiveTrips = useCallback(async () => {
    try {
      const res = await api.get('/deliveries');
      const raw = res.data?.data;
      const data = raw?.deliveries || (Array.isArray(raw) ? raw : []);
      const mapped: ActiveDelivery[] = data.map((t: any) => ({
        id: t.deliveryId || t.id,
        name: t.delivery?.name || t.deliveryName || 'Sin nombre',
        employeeId: t.delivery?.employeeId || t.employeeId || '',
        tripId: t.id || t.tripId,
        startTime: t.startTime,
        lastSeenAt: t.lastSeenAt || t.lastLocation?.timestamp || null,
        isOnline: t.isOnline ?? null,
        location: t.lastLocation || null,
        metrics: t.metrics || null,
        lastDestination: t.lastDestination || null,
        destinationHistory: t.destinationHistory || [],
      }));
      setDeliveries((prev) => mapped.map((d) => {
        const existing = prev.find((p) => p.id === d.id);
        if (existing && d.location && d.location.batteryLevel == null && existing.location?.batteryLevel != null) {
          return { ...d, location: { ...d.location, batteryLevel: existing.location.batteryLevel } };
        }
        return d;
      }));
    } catch (err) {
      console.error('Error fetching active trips:', err);
    }
  }, []);

  const fetchDestinationTimeline = useCallback(async (deliveryId: string) => {
    try {
      const res = await api.get(`/deliveries/${deliveryId}/destination-timeline`);
      const destinations = res.data?.data?.destinations || [];
      setDestinationTimeline((prev) => ({ ...prev, [deliveryId]: destinations }));
    } catch (err) {
      console.error('Error fetching destination timeline:', err);
    }
  }, []);

  useEffect(() => {
    fetchActiveTrips();
    const interval = setInterval(fetchActiveTrips, 10000);
    const timelineInterval = setInterval(() => {
      if (selectedId) fetchDestinationTimeline(selectedId);
    }, 15000);

    const socket = getSocket();

    socket.on('tripStarted', (data: any) => {
      const newDelivery: ActiveDelivery = {
        id: data.deliveryId,
        name: data.deliveryName || 'Sin nombre',
        employeeId: data.employeeId || '',
        tripId: data.tripId,
        startTime: data.startTime || new Date().toISOString(),
        lastSeenAt: data.startTime || new Date().toISOString(),
        isOnline: true,
        location: null,
        metrics: null,
      };
      setDeliveries((prev) => {
        const exists = prev.find((d) => d.id === newDelivery.id);
        if (exists) return prev;
        playBeep();
        return [...prev, newDelivery];
      });
    });

    socket.on('tripStopped', (data: any) => {
      setDeliveries((prev) => prev.filter((d) => d.id !== data.deliveryId));
      setSelectedId((prev) => (prev === data.deliveryId ? null : prev));
      setDestinationTimeline((prev) => {
        const next = { ...prev };
        delete next[data.deliveryId];
        return next;
      });
    });

    socket.on('locationUpdate', (data: any) => {
      const loc = {
        deliveryId: data.deliveryId,
        latitude: data.currentLocation?.latitude ?? data.latitude,
        longitude: data.currentLocation?.longitude ?? data.longitude,
        accuracy: data.currentLocation?.accuracy ?? data.accuracy ?? 0,
        speed: data.speed ?? 0,
        heading: data.heading ?? 0,
        batteryLevel: data.batteryLevel ?? null,
        timestamp: data.currentLocation?.timestamp ?? data.timestamp ?? new Date().toISOString(),
      };
      setDeliveries((prev) =>
        prev.map((d) =>
          d.id === data.deliveryId
            ? { ...d, location: loc, lastSeenAt: loc.timestamp, isOnline: true }
            : d
        )
      );
    });

    socket.on('metricsUpdate', (data: any) => {
      setDeliveries((prev) =>
        prev.map((d) =>
          d.id === data.deliveryId
            ? { ...d, metrics: data }
            : d
        )
      );
    });

    socket.on('deliveryDestination', (data: DeliveryDestination) => {
      console.log('deliveryDestination received', data);
      setDeliveries((prev) =>
        prev.map((d) =>
          d.id === data.deliveryId
            ? {
                ...d,
                lastDestination: data,
                destinationHistory: [data, ...(d.destinationHistory || [])].slice(0, 20),
              }
            : d
        )
      );
      setDestinationTimeline((prev) => ({
        ...prev,
        [data.deliveryId]: [data, ...(prev[data.deliveryId] || [])].slice(0, 20),
      }));
    });

    socket.on('deliveryDestinationAck', (data: any) => {
      setDeliveries((prev) =>
        prev.map((d) =>
          d.id === data.deliveryId && d.lastDestination?.assignedAt === data.assignedAt
            ? {
                ...d,
                lastDestination: {
                  ...d.lastDestination,
                  acknowledgedAt: data.receivedAt,
                } as DeliveryDestination,
              }
            : d
        )
      );
      setDestinationTimeline((prev) => ({
        ...prev,
        [data.deliveryId]: (prev[data.deliveryId] || []).map((item) =>
          item.assignedAt === data.assignedAt
            ? { ...item, acknowledgedAt: data.receivedAt }
            : item
        ),
      }));
    });

    const statusTimer = setInterval(() => {
      setDeliveries((prev) =>
        prev.map((d) => {
          const lastSeen = d.lastSeenAt ? new Date(d.lastSeenAt).getTime() : null;
          if (!lastSeen) return d;
          const minutes = (Date.now() - lastSeen) / 60000;
          return {
            ...d,
            isOnline: minutes < 3,
          };
        })
      );
    }, 30000);

    return () => {
      clearInterval(interval);
      clearInterval(timelineInterval);
      clearInterval(statusTimer);
      socket.off('tripStarted');
      socket.off('tripStopped');
      socket.off('locationUpdate');
      socket.off('metricsUpdate');
      socket.off('deliveryDestination');
      socket.off('deliveryDestinationAck');
    };
  }, [fetchActiveTrips, fetchDestinationTimeline, selectedId]);

  const sendDestination = async (deliveryId: string) => {
    if (!menuPoint) return;
    const delivery = deliveries.find((d) => d.id === deliveryId);
    if (!delivery) return;
    const assignedAt = new Date().toISOString();
    console.log('[dashboard] sending destination', {
      deliveryId,
      deliveryName: delivery.name,
      latitude: menuPoint.latitude,
      longitude: menuPoint.longitude,
    });
    const socket = getSocket();
    socket.emit('deliveryDestination', {
      deliveryId,
      deliveryName: delivery.name,
      latitude: menuPoint.latitude,
      longitude: menuPoint.longitude,
      label: `Destino para ${delivery.name}`,
      assignedAt,
    });
    console.log('[dashboard] destination emitted', deliveryId);
    setDeliveries((prev) =>
      prev.map((d) =>
        d.id === deliveryId
          ? {
              ...d,
              lastDestination: {
                deliveryId,
                deliveryName: delivery.name,
                latitude: menuPoint.latitude,
                longitude: menuPoint.longitude,
                label: `Destino para ${delivery.name}`,
                assignedAt,
              },
            }
          : d
      )
    );
    void fetchDestinationTimeline(deliveryId);
    setMenuPoint(null);
  };

  const handleStopTrip = async (deliveryId: string) => {
    if (!confirm('¿Detener este viaje?')) return;
    try {
      await api.post(`/deliveries/${deliveryId}/stop`);
      setDeliveries((prev) => prev.filter((d) => d.id !== deliveryId));
      setSelectedId((prev) => (prev === deliveryId ? null : prev));
    } catch (err) {
      console.error('Error stopping trip:', err);
    }
  };

  return (
    <DashboardLayout>
      <div className="flex h-full">
        {/* Map */}
        <div className="flex-1 relative">
          <Map
            deliveries={deliveries}
            selectedId={selectedId}
            onSelect={setSelectedId}
            onAssignDestination={setMenuPoint}
            centerRequest={centerRequest}
          />

          <div className="absolute top-4 right-4 z-[500]">
            <button
              onClick={() => setCenterRequest((v) => v + 1)}
              className="inline-flex items-center gap-2 px-3 py-2 rounded-lg bg-white/95 shadow-lg border border-gray-200 text-sm font-medium text-gray-700 hover:bg-gray-50"
            >
              <Focus className="w-4 h-4 text-red-600" />
              Centrar mapa
            </button>
          </div>
        </div>

        {/* Sidebar panel */}
        <div className="w-96 border-l border-gray-200 bg-white overflow-y-auto">
          <div className="p-4 border-b border-gray-100">
            <div className="flex items-center justify-between">
              <h3 className="font-semibold text-gray-900 flex items-center gap-2">
                <Truck className="w-5 h-5 text-red-600" />
                Deliveries Activos
              </h3>
              <span className="px-2.5 py-1 bg-red-100 text-red-700 text-xs font-bold rounded-full">
                {deliveries.length}
              </span>
            </div>
          </div>

          {/* Search */}
          {deliveries.length > 0 && (
            <div className="px-4 py-2 border-b border-gray-100">
              <div className="relative">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-gray-400" />
                <input
                  type="text"
                  placeholder="Buscar delivery..."
                  value={search}
                  onChange={(e) => setSearch(e.target.value)}
                  className="w-full pl-8 pr-3 py-1.5 text-sm border border-gray-200 rounded-lg focus:outline-none focus:ring-1 focus:ring-red-400"
                />
              </div>
            </div>
          )}

          <div className="p-4 space-y-3">
            {deliveries.length === 0 ? (
              <div className="text-center py-12">
                <Radio className="w-12 h-12 text-gray-300 mx-auto mb-3" />
                <p className="text-gray-500 font-medium">Sin deliveries activos</p>
                <p className="text-gray-400 text-sm mt-1">
                  Los viajes aparecerán aquí cuando inicien
                </p>
              </div>
            ) : (
              deliveries
                .filter(d => !search || d.name.toLowerCase().includes(search.toLowerCase()) || d.employeeId.toLowerCase().includes(search.toLowerCase()))
                .map((delivery) => {
                  const loc = delivery.lastLocation || delivery.location;
                  const lastUpdate = loc?.timestamp ? new Date(loc.timestamp) : null;
                  const minsWithoutSignal = lastUpdate ? Math.floor((Date.now() - lastUpdate.getTime()) / 60000) : null;
                  const noSignal = minsWithoutSignal !== null && minsWithoutSignal >= 3 && (delivery.totalLocations ?? 0) > 0;
                  const isWaitingFirstLocation = !loc && (delivery.totalLocations ?? 0) === 0;
                  return (
                    <div key={delivery.id}>
                      {isWaitingFirstLocation && (
                        <div className="mb-1 px-2 py-1 bg-blue-50 border border-blue-200 rounded-lg flex items-center gap-1.5 text-xs text-blue-700">
                          <Radio className="w-3 h-3 animate-pulse" />
                          Esperando primer reporte GPS de la app...
                        </div>
                      )}
                      {!isWaitingFirstLocation && noSignal && (
                        <div className="mb-1 px-2 py-1 bg-yellow-50 border border-yellow-200 rounded-lg flex items-center gap-1.5 text-xs text-yellow-700">
                          <WifiOff className="w-3 h-3" />
                          Sin señal GPS hace {minsWithoutSignal} min
                        </div>
                      )}
                      <ActiveDeliveryCard
                        delivery={delivery}
                        isSelected={delivery.id === selectedId}
                        onSelect={() => setSelectedId(delivery.id)}
                        onStop={() => handleStopTrip(delivery.id)}
                      />
                      {delivery.id === selectedId && delivery.lastDestination && (
                        <div className="mt-2 rounded-lg border border-blue-200 bg-blue-50 p-3 text-xs text-blue-900">
                          <div className="font-semibold mb-1">Último destino</div>
                          <div>{delivery.lastDestination.label || delivery.lastDestination.deliveryName}</div>
                          <div className="mt-1 text-blue-700">
                            {delivery.lastDestination.latitude.toFixed(5)}, {delivery.lastDestination.longitude.toFixed(5)}
                          </div>
                          <div className="mt-1">
                            Estado:{' '}
                            {delivery.lastDestination.acknowledgedAt ? 'Recibido por delivery' : 'Pendiente de confirmación'}
                          </div>
                        </div>
                      )}
                      {delivery.id === selectedId && (destinationTimeline[delivery.id] || []).length > 0 && (
                        <div className="mt-2 rounded-lg border border-gray-200 bg-white p-3">
                          <div className="font-semibold text-sm text-gray-900 mb-2">Timeline de destinos</div>
                          <div className="space-y-2 max-h-48 overflow-y-auto">
                            {(destinationTimeline[delivery.id] || []).map((item) => (
                              <div key={`${item.deliveryId}-${item.assignedAt}`} className="text-xs p-2 rounded border border-gray-100">
                                <div className="font-medium text-gray-800">{item.label || item.deliveryName}</div>
                                <div className="text-gray-500">
                                  {item.latitude.toFixed(5)}, {item.longitude.toFixed(5)}
                                </div>
                                <div className="text-gray-500">
                                  {item.acknowledgedAt ? 'ACK recibido' : 'Sin ACK'}
                                </div>
                              </div>
                            ))}
                          </div>
                        </div>
                      )}
                    </div>
                  );
                })
            )}
          </div>
        </div>

        {menuPoint && (
          <div className="fixed inset-0 z-[800] bg-black/20" onClick={() => setMenuPoint(null)}>
            <div
              className="absolute min-w-72 rounded-xl bg-white shadow-2xl border border-gray-200 p-3"
              style={{ left: menuPoint.x + 8, top: menuPoint.y + 8 }}
              onClick={(e) => e.stopPropagation()}
            >
              <div className="flex items-center justify-between mb-3">
                <div>
                  <p className="font-semibold text-gray-900">Enviar ubicación</p>
                  <p className="text-xs text-gray-500">
                    {menuPoint.latitude.toFixed(5)}, {menuPoint.longitude.toFixed(5)}
                  </p>
                </div>
                <button onClick={() => setMenuPoint(null)} className="text-gray-400 hover:text-gray-600">
                  <X className="w-4 h-4" />
                </button>
              </div>
              <div className="space-y-2 max-h-72 overflow-y-auto">
                {deliveries.map((delivery) => (
                  <button
                    key={delivery.id}
                    onClick={() => sendDestination(delivery.id)}
                    className="w-full flex items-center gap-2 px-3 py-2 rounded-lg border border-gray-200 hover:bg-gray-50 text-left"
                  >
                    <MapPin className="w-4 h-4 text-red-600" />
                    <span className="text-sm font-medium text-gray-800">{delivery.name}</span>
                  </button>
                ))}
              </div>
            </div>
          </div>
        )}
      </div>
    </DashboardLayout>
  );
}
