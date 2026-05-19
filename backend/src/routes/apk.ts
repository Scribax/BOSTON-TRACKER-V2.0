// ==========================================
// APK ROUTES - TypeScript Edition
// ==========================================

import { Router, Response, Request } from 'express';
import multer from 'multer';
import path from 'path';
import fs from 'fs';

import { authenticate, authorize } from '@middleware/auth';
import type { AuthenticatedRequest } from '../types/index';

const router = Router();

const APK_DIR = path.join(process.cwd(), 'public', 'apk');
const APK_PATH = path.join(APK_DIR, 'boston-tracker-latest.apk');
if (!fs.existsSync(APK_DIR)) fs.mkdirSync(APK_DIR, { recursive: true });

const upload = multer({
  storage: multer.diskStorage({
    destination: (_req: any, _file: any, cb: any) => cb(null, APK_DIR),
    filename: (_req: any, _file: any, cb: any) => cb(null, 'boston-tracker-latest.apk'),
  }),
  limits: { fileSize: 200 * 1024 * 1024 },
});

// ==========================================
// GET APK INFO
// ==========================================

router.get('/info', authenticate, authorize('admin'), async (
  req: AuthenticatedRequest,
  res: Response
): Promise<void> => {
  try {
    const exists = fs.existsSync(APK_PATH);
    const stat = exists ? fs.statSync(APK_PATH) : null;
    const baseUrl = `${req.protocol}://${req.get('host')}`;
    res.json({
      success: true,
      data: {
        version: '1.0.0',
        fileName: 'boston-tracker-latest.apk',
        downloadUrl: `${baseUrl}/api/apk/download/latest`,
        size: stat ? stat.size : 0,
        updatedAt: stat ? stat.mtime.toISOString() : null,
        available: exists,
      },
    });
  } catch (error) {
    console.error('Get APK info error:', error);
    res.status(500).json({ success: false, message: 'Error interno del servidor' });
  }
});

// ==========================================
// UPLOAD APK
// ==========================================

router.post('/upload', authenticate, authorize('admin'), upload.single('apk'), async (
  req: any,
  res: Response
): Promise<void> => {
  try {
    if (!req.file) {
      res.status(400).json({ success: false, message: 'No se recibió ningún archivo APK' });
      return;
    }
    res.json({
      success: true,
      message: 'APK subida correctamente',
      data: { size: req.file.size, fileName: req.file.filename },
    });
  } catch (error) {
    console.error('Upload APK error:', error);
    res.status(500).json({ success: false, message: 'Error subiendo APK' });
  }
});

// ==========================================
// DOWNLOAD APK
// ==========================================

router.get('/download/latest', async (_req: Request, res: Response): Promise<void> => {
  try {
    if (!fs.existsSync(APK_PATH)) {
      res.status(404).json({ success: false, message: 'APK no disponible aún' });
      return;
    }
    res.download(APK_PATH, 'boston-tracker-latest.apk');
  } catch (error) {
    res.status(500).json({ success: false, message: 'Error descargando APK' });
  }
});

// ==========================================
// SEND WHATSAPP LINK
// ==========================================

router.post('/send-whatsapp', authenticate, authorize('admin'), async (
  req: AuthenticatedRequest,
  res: Response
): Promise<void> => {
  try {
    const { phoneNumber, deliveryName, customMessage } = req.body;

    if (!phoneNumber) {
      res.status(400).json({
        success: false,
        message: 'Número de teléfono es requerido',
      });
      return;
    }

    const cleanPhone = phoneNumber.replace(/[^\d+]/g, '');
    const apkUrl = `http://${req.get('host')}/apk/boston-tracker-latest.apk`;

    const message = customMessage || `Hola ${deliveryName || ''}! Descarga la app BOSTON Tracker: ${apkUrl}`;
    const whatsappUrl = `https://wa.me/${cleanPhone}?text=${encodeURIComponent(message)}`;

    res.json({
      success: true,
      data: {
        whatsappUrl,
        phoneNumber: cleanPhone,
        apkUrl,
        message,
      },
    });
  } catch (error) {
    console.error('Send WhatsApp link error:', error);
    res.status(500).json({
      success: false,
      message: 'Error interno del servidor',
      error: error instanceof Error ? error.message : 'Unknown error',
    });
  }
});


export default router;
