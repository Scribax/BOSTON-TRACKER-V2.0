'use client';

import { useState, useEffect, useCallback } from 'react';
import dynamic from 'next/dynamic';
import DashboardLayout from '@/components/DashboardLayout';
import ActiveDeliveryCard from '@/components/ActiveDeliveryCard';
import { getSocket } from '@/lib/socket';
import api from '@/lib/api';
import { ActiveDelivery } from '@/lib/types';
import { Truck, Radio } from 'lucide-react';

const Map = dynamic(() => import('@/components/Map'), { ssr: false });

export default function TrackingPage() {
  const [deliveries, setDeliveries] = useState<ActiveDelivery[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);

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
        location: t.lastLocation || null,
        metrics: t.metrics || null,
      }));
      setDeliveries(mapped);
    } catch (err) {
      console.error('Error fetching active trips:', err);
    }
  }, []);

  useEffect(() => {
    fetchActiveTrips();
    const interval = setInterval(fetchActiveTrips, 10000);

    const socket = getSocket();

    socket.on('tripStarted', (data: any) => {
      const newDelivery: ActiveDelivery = {
        id: data.deliveryId,
        name: data.deliveryName || 'Sin nombre',
        employeeId: data.employeeId || '',
        tripId: data.tripId,
        startTime: data.startTime || new Date().toISOString(),
        location: null,
        metrics: null,
      };
      setDeliveries((prev) => {
        const exists = prev.find((d) => d.id === newDelivery.id);
        if (exists) return prev;
        return [...prev, newDelivery];
      });
    });

    socket.on('tripStopped', (data: any) => {
      setDeliveries((prev) => prev.filter((d) => d.id !== data.deliveryId));
      setSelectedId((prev) => (prev === data.deliveryId ? null : prev));
    });

    socket.on('locationUpdate', (data: any) => {
      const loc = {
        deliveryId: data.deliveryId,
        latitude: data.currentLocation?.latitude ?? data.latitude,
        longitude: data.currentLocation?.longitude ?? data.longitude,
        accuracy: data.currentLocation?.accuracy ?? data.accuracy ?? 0,
        speed: data.speed ?? 0,
        heading: data.heading ?? 0,
        timestamp: data.currentLocation?.timestamp ?? data.timestamp ?? new Date().toISOString(),
      };
      setDeliveries((prev) =>
        prev.map((d) =>
          d.id === data.deliveryId
            ? { ...d, location: loc }
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

    return () => {
      clearInterval(interval);
      socket.off('tripStarted');
      socket.off('tripStopped');
      socket.off('locationUpdate');
      socket.off('metricsUpdate');
    };
  }, [fetchActiveTrips]);

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
          />
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
              deliveries.map((delivery) => (
                <ActiveDeliveryCard
                  key={delivery.id}
                  delivery={delivery}
                  isSelected={delivery.id === selectedId}
                  onSelect={() => setSelectedId(delivery.id)}
                  onStop={() => handleStopTrip(delivery.id)}
                />
              ))
            )}
          </div>
        </div>
      </div>
    </DashboardLayout>
  );
}
