'use client';

import { ActiveDelivery } from '@/lib/types';
import { Clock, Gauge, Route, Square } from 'lucide-react';

function getInitials(name: string) {
  return name.split(' ').slice(0, 2).map(w => w[0]).join('').toUpperCase();
}

function getColor(name: string) {
  const colors = ['bg-blue-500','bg-purple-500','bg-indigo-500','bg-teal-500','bg-orange-500','bg-pink-500'];
  const i = name.charCodeAt(0) % colors.length;
  return colors[i];
}

interface Props {
  delivery: ActiveDelivery;
  isSelected: boolean;
  onSelect: () => void;
  onStop: () => void;
}

export default function ActiveDeliveryCard({ delivery, isSelected, onSelect, onStop }: Props) {
  const elapsed = delivery.startTime
    ? Math.floor((Date.now() - new Date(delivery.startTime).getTime()) / 60000)
    : 0;
  const lastSeen = delivery.lastSeenAt ? new Date(delivery.lastSeenAt) : null;
  const lastSeenLabel = lastSeen
    ? lastSeen.toLocaleTimeString('es-AR', { hour: '2-digit', minute: '2-digit' })
    : 'Sin dato';
  const online = delivery.isOnline ?? false;

  const formatDistance = (meters: number) => {
    if (!meters) return '0 m';
    if (meters < 1000) return `${meters} m`;
    return `${(meters / 1000).toFixed(2)} km`;
  };

  return (
    <div
      onClick={onSelect}
      className={`p-4 rounded-xl border-2 cursor-pointer transition-all ${
        isSelected
          ? 'border-red-500 bg-red-50 shadow-md'
          : 'border-gray-200 bg-white hover:border-gray-300 hover:shadow-sm'
      }`}
    >
      <div className="flex items-center justify-between mb-3">
        <div className="flex items-center gap-2">
          <div className={`w-9 h-9 rounded-full flex items-center justify-center text-white text-sm font-bold shadow-sm ${
            isSelected ? 'ring-2 ring-red-500 ring-offset-1' : ''
          } ${getColor(delivery.name)}`}>
            {getInitials(delivery.name)}
          </div>
          <div>
            <p className="font-semibold text-gray-900 text-sm">{delivery.name}</p>
            <p className="text-xs text-gray-500">{delivery.employeeId}</p>
          </div>
        </div>
        <span className="px-2 py-1 bg-green-100 text-green-700 text-xs font-medium rounded-full flex items-center gap-1">
          <span className={`w-1.5 h-1.5 rounded-full ${online ? 'bg-green-500 animate-pulse' : 'bg-gray-400'}`} />
          {online ? 'Activo' : 'Sin señal'}
        </span>
      </div>

      <div className="grid grid-cols-3 gap-2 mb-3">
        <div className="text-center p-2 bg-gray-50 rounded-lg">
          <Route className="w-4 h-4 text-gray-400 mx-auto mb-1" />
          <p className="text-xs font-semibold text-gray-900">
            {formatDistance((delivery.metrics?.totalDistance || 0) * 1000)}
          </p>
          <p className="text-[10px] text-gray-500">Distancia</p>
        </div>
        <div className="text-center p-2 bg-gray-50 rounded-lg">
          <Clock className="w-4 h-4 text-gray-400 mx-auto mb-1" />
          <p className="text-xs font-semibold text-gray-900">{elapsed} min</p>
          <p className="text-[10px] text-gray-500">Duración</p>
        </div>
        <div className="text-center p-2 bg-gray-50 rounded-lg">
          <Gauge className="w-4 h-4 text-gray-400 mx-auto mb-1" />
          <p className="text-xs font-semibold text-gray-900">
            {delivery.metrics?.currentSpeed || 0} km/h
          </p>
          <p className="text-[10px] text-gray-500">Velocidad</p>
        </div>
      </div>

      {/* Battery + GPS signal row */}
      {(delivery.location?.batteryLevel != null || delivery.location?.accuracy != null) && (
        <div className="flex items-center gap-3 mb-2 px-1">
          {delivery.location?.batteryLevel != null && (() => {
            const b = delivery.location!.batteryLevel!;
            const color = b > 50 ? 'text-green-600' : b > 20 ? 'text-yellow-500' : 'text-red-500';
            const fillColor = b > 50 ? '#16a34a' : b > 20 ? '#eab308' : '#ef4444';
            const fillW = Math.round((b / 100) * 18);
            return (
              <span className={`text-xs font-medium flex items-center gap-1 ${color}`}>
                <svg width="22" height="12" viewBox="0 0 22 12" fill="none" xmlns="http://www.w3.org/2000/svg">
                  <rect x="0.5" y="0.5" width="19" height="11" rx="2" stroke="currentColor" strokeWidth="1.2"/>
                  <rect x="2" y="2" width={fillW} height="8" rx="1" fill={fillColor}/>
                  <path d="M20 4v4" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round"/>
                </svg>
                {b}%
              </span>
            );
          })()}
          {delivery.location?.accuracy != null && (() => {
            const a = delivery.location!.accuracy;
            const label = a <= 10 ? 'GPS Excelente' : a <= 30 ? 'GPS Bueno' : a <= 60 ? 'GPS Regular' : 'GPS Débil';
            const color = a <= 10 ? 'text-green-600' : a <= 30 ? 'text-blue-500' : a <= 60 ? 'text-yellow-500' : 'text-red-500';
            return (
              <span className={`text-xs font-medium ${color}`}>
                📡 {label} ({a.toFixed(0)}m)
              </span>
            );
          })()}
        </div>
      )}

      <div className="flex items-center justify-between">
        <div className="flex flex-col">
          <span className="text-xs text-gray-500 flex items-center gap-1">
            <Clock className="w-3 h-3" />
            Inicio: {new Date(delivery.startTime).toLocaleTimeString('es-AR', { hour: '2-digit', minute: '2-digit' })}
          </span>
          <span className="text-[11px] text-gray-400">
            Última conexión: {lastSeenLabel}
          </span>
        </div>
        <button
          onClick={(e) => {
            e.stopPropagation();
            onStop();
          }}
          className="px-3 py-1.5 bg-red-600 hover:bg-red-700 text-white text-xs font-medium rounded-lg flex items-center gap-1 transition-colors"
        >
          <Square className="w-3 h-3" />
          Detener
        </button>
      </div>
    </div>
  );
}
