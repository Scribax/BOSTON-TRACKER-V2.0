const lastSeenByDelivery = new Map<string, number>();
const lastDestinationByDelivery = new Map<string, unknown>();

export const markDeliverySeen = (deliveryId: string, at: Date = new Date()): void => {
  lastSeenByDelivery.set(deliveryId, at.getTime());
};

export const getDeliveryLastSeen = (deliveryId: string): Date | null => {
  const ts = lastSeenByDelivery.get(deliveryId);
  return ts ? new Date(ts) : null;
};

export const setLastDeliveryDestination = (deliveryId: string, destination: unknown): void => {
  lastDestinationByDelivery.set(deliveryId, destination);
};

export const getLastDeliveryDestination = (deliveryId: string): unknown | null => {
  return lastDestinationByDelivery.get(deliveryId) ?? null;
};
