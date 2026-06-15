import type { DeliveryDestinationPayload } from '../types';

type StoredDestination = DeliveryDestinationPayload & {
  receivedAt: string;
  acknowledgedAt?: string;
};

const lastDestinationByDelivery = new Map<string, StoredDestination>();
const destinationHistoryByDelivery = new Map<string, StoredDestination[]>();

export const storeDeliveryDestination = (
  deliveryId: string,
  payload: DeliveryDestinationPayload
): StoredDestination => {
  const stored: StoredDestination = {
    ...payload,
    receivedAt: new Date().toISOString(),
  };

  lastDestinationByDelivery.set(deliveryId, stored);

  const history = destinationHistoryByDelivery.get(deliveryId) ?? [];
  history.push(stored);
  destinationHistoryByDelivery.set(deliveryId, history.slice(-20));

  return stored;
};

export const getLastDeliveryDestination = (deliveryId: string): StoredDestination | null => {
  return lastDestinationByDelivery.get(deliveryId) ?? null;
};

export const getDeliveryDestinationHistory = (deliveryId: string): StoredDestination[] => {
  return destinationHistoryByDelivery.get(deliveryId) ?? [];
};

export const acknowledgeDeliveryDestination = (deliveryId: string, assignedAt: string): void => {
  const current = lastDestinationByDelivery.get(deliveryId);
  if (current && current.assignedAt === assignedAt) {
    current.acknowledgedAt = new Date().toISOString();
    lastDestinationByDelivery.set(deliveryId, current);
  }

  const history = destinationHistoryByDelivery.get(deliveryId);
  if (!history) return;

  const updated = history.map((item) =>
    item.assignedAt === assignedAt
      ? { ...item, acknowledgedAt: new Date().toISOString() }
      : item
  );
  destinationHistoryByDelivery.set(deliveryId, updated);
};
