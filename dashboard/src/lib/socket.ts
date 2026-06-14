import { io, Socket } from 'socket.io-client';
import Cookies from 'js-cookie';

const SOCKET_URL = process.env.NEXT_PUBLIC_SOCKET_URL || 'http://186.64.123.15:5000';

let socket: Socket | null = null;

export function getSocket(): Socket {
  if (!socket || !socket.connected) {
    if (socket) {
      socket.disconnect();
      socket = null;
    }
    const token = Cookies.get('token');
    socket = io(SOCKET_URL, {
      transports: ['websocket', 'polling'],
      auth: { token },
      reconnection: true,
      reconnectionAttempts: Infinity,
      reconnectionDelay: 2000,
    });

    socket.on('connect', () => {
      console.log('✅ Socket connected:', socket?.id);
      const latestToken = Cookies.get('token');
      if (latestToken) {
        (socket as any).auth = { token: latestToken };
      }
      socket?.emit('join-admin');
      console.log('📡 Emitted join-admin with token present:', Boolean(latestToken));
    });

    socket.on('connect_error', (err) => {
      console.error('❌ Socket connection error:', err.message);
    });

    socket.on('disconnect', (reason) => {
      console.log('🔌 Socket disconnected:', reason);
    });

    socket.on('connect_error', (err) => {
      console.error('❌ Socket connect_error details:', err);
    });

    socket.on('locationUpdate', (data: any) => {
      console.log('📍 locationUpdate received:', data);
    });
  }
  return socket;
}

export function disconnectSocket() {
  if (socket) {
    socket.disconnect();
    socket = null;
  }
}
