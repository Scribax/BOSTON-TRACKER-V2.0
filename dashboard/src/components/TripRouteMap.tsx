'use client';

import { useEffect, useRef } from 'react';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';

interface Location {
  latitude: number;
  longitude: number;
  timestamp: string;
  speed?: number;
}

interface TripRouteMapProps {
  locations: Location[];
}

export default function TripRouteMap({ locations }: TripRouteMapProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<L.Map | null>(null);

  useEffect(() => {
    if (!containerRef.current || mapRef.current) return;

    const valid = locations.filter(
      (l) => l.latitude != null && l.longitude != null && !isNaN(l.latitude) && !isNaN(l.longitude)
    );
    if (valid.length === 0) return;

    const center: [number, number] = [valid[0].latitude, valid[0].longitude];

    mapRef.current = L.map(containerRef.current, { center, zoom: 14 });

    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '&copy; OpenStreetMap contributors',
    }).addTo(mapRef.current);

    // Draw route polyline
    const latlngs: [number, number][] = valid.map((l) => [l.latitude, l.longitude]);
    const polyline = L.polyline(latlngs, { color: '#dc2626', weight: 4, opacity: 0.8 }).addTo(mapRef.current);

    // Start marker (green)
    const startIcon = L.divIcon({
      className: '',
      html: `<div style="width:14px;height:14px;background:#16a34a;border:2px solid white;border-radius:50%;box-shadow:0 1px 4px rgba(0,0,0,0.4)"></div>`,
      iconSize: [14, 14],
      iconAnchor: [7, 7],
    });
    L.marker([valid[0].latitude, valid[0].longitude], { icon: startIcon })
      .addTo(mapRef.current)
      .bindPopup('Inicio');

    // End marker (red)
    const endIcon = L.divIcon({
      className: '',
      html: `<div style="width:14px;height:14px;background:#dc2626;border:2px solid white;border-radius:50%;box-shadow:0 1px 4px rgba(0,0,0,0.4)"></div>`,
      iconSize: [14, 14],
      iconAnchor: [7, 7],
    });
    const last = valid[valid.length - 1];
    L.marker([last.latitude, last.longitude], { icon: endIcon })
      .addTo(mapRef.current)
      .bindPopup('Fin');

    // Fit map to route
    mapRef.current.fitBounds(polyline.getBounds(), { padding: [30, 30] });

    return () => {
      mapRef.current?.remove();
      mapRef.current = null;
    };
  }, [locations]);

  return <div ref={containerRef} className="w-full h-full min-h-[400px]" />;
}
