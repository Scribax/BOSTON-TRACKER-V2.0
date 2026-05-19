'use client';

import { ActiveDelivery } from '@/lib/types';
import { Truck, Clock, Gauge, Route, Square } from 'lucide-react';

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
          <div className={`w-8 h-8 rounded-full flex items-center justify-center ${
            isSelected ? 'bg-red-600' : 'bg-blue-600'
          }`}>
            <Truck className="w-4 h-4 text-white" />
          </div>
          <div>
            <p className="font-semibold text-gray-900 text-sm">{delivery.name}</p>
            <p className="text-xs text-gray-500">{delivery.employeeId}</p>
          </div>
        </div>
        <span className="px-2 py-1 bg-green-100 text-green-700 text-xs font-medium rounded-full flex items-center gap-1">
          <span className="w-1.5 h-1.5 bg-green-500 rounded-full animate-pulse" />
          Activo
        </span>
      </div>

      <div className="grid grid-cols-3 gap-2 mb-3">
        <div className="text-center p-2 bg-gray-50 rounded-lg">
          <Route className="w-4 h-4 text-gray-400 mx-auto mb-1" />
          <p className="text-xs font-semibold text-gray-900">
            {formatDistance(delivery.metrics?.totalDistance || 0)}
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

      <div className="flex items-center justify-between">
        <span className="text-xs text-gray-500 flex items-center gap-1">
          <Clock className="w-3 h-3" />
          Inicio: {new Date(delivery.startTime).toLocaleTimeString('es-AR', { hour: '2-digit', minute: '2-digit' })}
        </span>
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
