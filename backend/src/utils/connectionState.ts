const lastSeenByDelivery = new Map<string, number>();

export const markDeliverySeen = (deliveryId: string, at: Date = new Date()): void => {
  lastSeenByDelivery.set(deliveryId, at.getTime());
};

export const getDeliveryLastSeen = (deliveryId: string): Date | null => {
  const ts = lastSeenByDelivery.get(deliveryId);
  return ts ? new Date(ts) : null;
};
