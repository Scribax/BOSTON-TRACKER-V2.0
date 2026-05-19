// ==========================================
// LOCATION MODEL - TypeScript + Sequelize
// ==========================================

import { DataTypes, Model } from 'sequelize';

import { sequelize } from '@config/database';
import type {
  LocationAttributes,
  LocationCreationAttributes,
} from '../types/database';

class LocationModel
  extends Model<LocationAttributes, LocationCreationAttributes>
  implements LocationAttributes
{
  declare id: string;
  declare tripId: string;
  declare latitude: number;
  declare longitude: number;
  declare accuracy: number | undefined;
  declare speed: number | undefined;
  declare heading: number | undefined;
  declare batteryLevel: number | undefined;
  declare timestamp: Date;
  declare readonly createdAt: Date;
  declare readonly updatedAt: Date;
}

LocationModel.init(
  {
    id: {
      type: DataTypes.UUID,
      defaultValue: DataTypes.UUIDV4,
      primaryKey: true,
    },
    tripId: {
      type: DataTypes.UUID,
      allowNull: false,
      references: {
        model: 'trips',
        key: 'id',
      },
    },
    latitude: {
      type: DataTypes.DOUBLE,
      allowNull: false,
      validate: {
        min: { args: [-90], msg: 'La latitud debe estar entre -90 y 90' },
        max: { args: [90], msg: 'La latitud debe estar entre -90 y 90' },
      },
    },
    longitude: {
      type: DataTypes.DOUBLE,
      allowNull: false,
      validate: {
        min: { args: [-180], msg: 'La longitud debe estar entre -180 y 180' },
        max: { args: [180], msg: 'La longitud debe estar entre -180 y 180' },
      },
    },
    accuracy: {
      type: DataTypes.FLOAT,
      allowNull: true,
    },
    speed: {
      type: DataTypes.FLOAT,
      allowNull: true,
    },
    heading: {
      type: DataTypes.FLOAT,
      allowNull: true,
    },
    batteryLevel: {
      type: DataTypes.INTEGER,
      allowNull: true,
    },
    timestamp: {
      type: DataTypes.DATE,
      defaultValue: DataTypes.NOW,
      allowNull: false,
    },
  },
  {
    sequelize,
    tableName: 'locations',
    timestamps: true,
    indexes: [
      { fields: ['tripId'] },
      { fields: ['timestamp'] },
      { fields: ['tripId', 'timestamp'] },
    ],
  }
);

export default LocationModel;
