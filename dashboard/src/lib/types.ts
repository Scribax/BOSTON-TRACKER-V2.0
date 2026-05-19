export interface User {
  id: string;
  name: string;
  email: string | null;
  employeeId: string;
  role: 'admin' | 'delivery';
  phone: string | null;
  isActive: boolean;
  lastLogin: string | null;
  createdAt: string;
}

export interface Trip {
  id: string;
  deliveryId: string;
  status: 'active' | 'completed';
  startTime: string;
  endTime: string | null;
  totalMileage: number;
  averageSpeed: number;
  maxSpeed: number;
  totalTime: number;
  delivery?: User;
}

export interface LocationUpdate {
  deliveryId: string;
  deliveryName?: string;
  latitude: number;
  longitude: number;
  speed: number;
  heading: number;
  accuracy: number;
  batteryLevel?: number | null;
  timestamp: string;
}

export interface TripMetrics {
  currentSpeed: number;
  averageSpeed: number;
  maxSpeed: number;
  totalDistance: number;
  totalTime: number;
}

export interface ActiveDelivery {
  id: string;
  name: string;
  employeeId: string;
  tripId: string;
  startTime: string;
  location: LocationUpdate | null;
  metrics: TripMetrics | null;
}
