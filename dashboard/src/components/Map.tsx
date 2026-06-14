'use client';

import { useEffect, useRef } from 'react';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import { ActiveDelivery } from '@/lib/types';

interface MapProps {
  deliveries: ActiveDelivery[];
  selectedId?: string | null;
  onSelect?: (id: string) => void;
  onAssignDestination?: (point: { latitude: number; longitude: number; x: number; y: number }) => void;
  centerRequest?: number;
}

export default function Map({ deliveries, selectedId, onSelect, onAssignDestination, centerRequest }: MapProps) {
  const mapRef = useRef<L.Map | null>(null);
  const markersRef = useRef<Record<string, L.Marker>>({});
  const containerRef = useRef<HTMLDivElement>(null);
  const hasAutocentered = useRef(false);

  useEffect(() => {
    if (!containerRef.current || mapRef.current) return;

    mapRef.current = L.map(containerRef.current, {
      center: [-34.617, -68.33],
      zoom: 12,
      zoomControl: true,
    });

    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '&copy; OpenStreetMap contributors',
    }).addTo(mapRef.current);

    mapRef.current.on('contextmenu', (event) => {
      onAssignDestination?.({
        latitude: event.latlng.lat,
        longitude: event.latlng.lng,
        x: event.originalEvent.clientX,
        y: event.originalEvent.clientY,
      });
    });

    return () => {
      mapRef.current?.off('contextmenu');
      mapRef.current?.remove();
      mapRef.current = null;
    };
  }, []);

  useEffect(() => {
    if (!mapRef.current) return;

    const activeIds = new Set(deliveries.map((d) => d.id));

    // Remove markers that are no longer active
    Object.keys(markersRef.current).forEach((id) => {
      if (!activeIds.has(id)) {
        markersRef.current[id].remove();
        delete markersRef.current[id];
      }
    });

    // Update or create markers
    deliveries.forEach((delivery) => {
      if (!delivery.location) return;

      const { latitude, longitude } = delivery.location;
      if (latitude == null || longitude == null || isNaN(latitude) || isNaN(longitude)) return;

      // Auto-center on first real location received
      if (!hasAutocentered.current) {
        mapRef.current?.setView([latitude, longitude], 14);
        hasAutocentered.current = true;
      }
      const isSelected = delivery.id === selectedId;

      const icon = L.divIcon({
        className: 'custom-marker',
        html: `
          <div class="relative flex items-center justify-center">
            <div class="w-10 h-10 rounded-full ${isSelected ? 'bg-red-600' : 'bg-blue-600'} border-3 border-white shadow-lg flex items-center justify-center">
              <svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 17a2 2 0 11-4 0 2 2 0 014 0zM19 17a2 2 0 11-4 0 2 2 0 014 0z" />
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16V6a1 1 0 00-1-1H4a1 1 0 00-1 1v10a1 1 0 001 1h1m8-1a1 1 0 01-1 1H9m4-1V8a1 1 0 011-1h2.586a1 1 0 01.707.293l3.414 3.414a1 1 0 01.293.707V16a1 1 0 01-1 1h-1m-6-1a1 1 0 001 1h1M5 17a2 2 0 104 0m-4 0a2 2 0 114 0m6 0a2 2 0 104 0m-4 0a2 2 0 114 0" />
              </svg>
            </div>
            <div class="absolute -bottom-6 whitespace-nowrap bg-gray-900 text-white text-xs px-2 py-0.5 rounded">
              ${delivery.name}
            </div>
          </div>
        `,
        iconSize: [40, 50],
        iconAnchor: [20, 20],
      });

      const battery = delivery.location?.batteryLevel;
      const acc = delivery.location?.accuracy;
      const batteryHtml = battery != null
        ? `<div style="margin-top:4px;font-size:11px;color:${battery > 50 ? '#16a34a' : battery > 20 ? '#ca8a04' : '#dc2626'}">🔋 ${battery}%</div>`
        : '';
      const gpsHtml = acc != null
        ? `<div style="font-size:11px;color:${acc <= 10 ? '#16a34a' : acc <= 30 ? '#2563eb' : acc <= 60 ? '#ca8a04' : '#dc2626'}">📡 ${acc <= 10 ? 'Excelente' : acc <= 30 ? 'Bueno' : acc <= 60 ? 'Regular' : 'Débil'} (${acc.toFixed(0)}m)</div>`
        : '';

      if (markersRef.current[delivery.id]) {
        markersRef.current[delivery.id].setLatLng([latitude, longitude]);
        markersRef.current[delivery.id].setIcon(icon);
        markersRef.current[delivery.id].getPopup()?.setContent(
          `<div style="font-size:12px;font-weight:600">${delivery.name}</div><div style="font-size:11px;color:#6b7280">${delivery.employeeId}</div>${batteryHtml}${gpsHtml}`
        );
      } else {
        const marker = L.marker([latitude, longitude], { icon }).addTo(mapRef.current!);
        marker.bindPopup(
          `<div style="font-size:12px;font-weight:600">${delivery.name}</div><div style="font-size:11px;color:#6b7280">${delivery.employeeId}</div>${batteryHtml}${gpsHtml}`,
          { offset: [0, -20], closeButton: false }
        );
        marker.on('click', () => { onSelect?.(delivery.id); marker.openPopup(); });
        markersRef.current[delivery.id] = marker;
      }
    });

  }, [deliveries, selectedId, onSelect]);

  useEffect(() => {
    if (!mapRef.current || centerRequest == null) return;

    const selected = deliveries.find((d) => d.id === selectedId);
    const lat = selected?.location?.latitude;
    const lng = selected?.location?.longitude;

    if (lat != null && lng != null && !isNaN(lat) && !isNaN(lng)) {
      mapRef.current.setView([lat, lng], 15, { animate: true });
      return;
    }

    const validPoints = deliveries
      .filter((d) => d.location?.latitude != null && d.location?.longitude != null)
      .map((d) => [d.location!.latitude, d.location!.longitude] as [number, number]);

    if (validPoints.length > 1) {
      mapRef.current.fitBounds(L.latLngBounds(validPoints), { padding: [40, 40], animate: true, maxZoom: 16 });
    }
  }, [centerRequest, deliveries, selectedId]);

  return <div ref={containerRef} className="w-full h-full" />;
}
