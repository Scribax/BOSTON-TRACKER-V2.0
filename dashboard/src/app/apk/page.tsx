'use client';

import { useState, useEffect } from 'react';
import DashboardLayout from '@/components/DashboardLayout';
import api from '@/lib/api';
import { Upload, Package, Clock, FileDown } from 'lucide-react';

interface ApkVersion {
  id: string;
  version: string;
  filename: string;
  size: number;
  uploadedAt: string;
  downloadUrl: string;
}

export default function ApkPage() {
  const [versions, setVersions] = useState<ApkVersion[]>([]);
  const [loading, setLoading] = useState(true);
  const [uploading, setUploading] = useState(false);
  const [uploadProgress, setUploadProgress] = useState(0);
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    fetchVersions();
  }, []);

  const fetchVersions = async () => {
    try {
      const res = await api.get('/apk/info');
      const data = res.data?.data;
      if (data) {
        setVersions([{
          id: '1',
          version: data.version || '1.0.0',
          filename: data.fileName || 'boston-tracker-latest.apk',
          size: data.size || 0,
          uploadedAt: data.updatedAt || new Date().toISOString(),
          downloadUrl: data.downloadUrl || '',
        }]);
      }
    } catch (err) {
      console.error('Error fetching APK info:', err);
    } finally {
      setLoading(false);
    }
  };

  const handleUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    setUploading(true);
    setUploadProgress(0);
    const formData = new FormData();
    formData.append('apk', file);

    try {
      await api.post('/apk/upload', formData, {
        headers: { 'Content-Type': 'multipart/form-data' },
        onUploadProgress: (e) => {
          const pct = e.total ? Math.round((e.loaded * 100) / e.total) : 0;
          setUploadProgress(pct);
        },
      });
      setUploadProgress(100);
      await fetchVersions();
    } catch (err: any) {
      alert(err.response?.data?.message || 'Error subiendo APK');
    } finally {
      setUploading(false);
      setUploadProgress(0);
    }
  };

  const copyLink = () => {
    const url = 'http://186.64.123.15:5000/api/apk/download/latest';
    if (navigator.clipboard?.writeText) {
      navigator.clipboard.writeText(url).then(() => { setCopied(true); setTimeout(() => setCopied(false), 2000); });
    } else {
      // HTTP fallback
      const el = document.createElement('textarea');
      el.value = url;
      document.body.appendChild(el);
      el.select();
      document.execCommand('copy');
      document.body.removeChild(el);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    }
  };

  const formatSize = (bytes: number) => {
    if (!bytes) return '0 MB';
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  };

  return (
    <DashboardLayout>
      <div className="p-6">
        <div className="flex items-center justify-between mb-6">
          <div className="flex items-center gap-3">
            <Package className="w-6 h-6 text-red-600" />
            <h2 className="text-xl font-bold text-gray-900">Gestión de APK</h2>
          </div>
          <label className="px-4 py-2 bg-red-600 hover:bg-red-700 text-white text-sm font-medium rounded-lg flex items-center gap-2 transition-colors cursor-pointer">
            <Upload className="w-4 h-4" />
            {uploading ? 'Subiendo...' : 'Subir APK'}
            <input
              type="file"
              accept=".apk"
              onChange={handleUpload}
              className="hidden"
              disabled={uploading}
            />
          </label>
        </div>

        {/* Upload progress bar */}
        {uploading && (
          <div className="bg-white rounded-xl border border-gray-200 p-4 mb-4">
            <div className="flex items-center justify-between mb-2">
              <span className="text-sm font-medium text-gray-700">Subiendo APK...</span>
              <span className="text-sm font-bold text-red-600">{uploadProgress}%</span>
            </div>
            <div className="w-full bg-gray-100 rounded-full h-3 overflow-hidden">
              <div
                className="h-3 bg-red-600 rounded-full transition-all duration-300"
                style={{ width: `${uploadProgress}%` }}
              />
            </div>
          </div>
        )}

        {/* Download link card */}
        <div className="bg-white rounded-xl border border-gray-200 p-6 mb-6">
          <h3 className="font-semibold text-gray-900 mb-2">Enlace de descarga</h3>
          <p className="text-sm text-gray-500 mb-3">
            Comparte este enlace con los deliveries para que descarguen la última versión
          </p>
          <div className="flex items-center gap-2">
            <input
              type="text"
              readOnly
              value="http://186.64.123.15:5000/api/apk/download/latest"
              className="flex-1 px-3 py-2 bg-gray-50 border border-gray-200 rounded-lg text-sm text-gray-600"
            />
            <button
              onClick={copyLink}
              className={`px-4 py-2 text-sm font-medium rounded-lg transition-colors ${
                copied ? 'bg-green-100 text-green-700' : 'bg-gray-100 hover:bg-gray-200 text-gray-700'
              }`}
            >
              {copied ? '¡Copiado!' : 'Copiar'}
            </button>
          </div>
        </div>

        {loading ? (
          <div className="flex items-center justify-center py-20">
            <div className="w-8 h-8 border-3 border-red-600 border-t-transparent rounded-full animate-spin" />
          </div>
        ) : versions.length === 0 ? (
          <div className="text-center py-20">
            <Package className="w-16 h-16 text-gray-300 mx-auto mb-4" />
            <p className="text-gray-500 font-medium">No hay versiones subidas</p>
            <p className="text-gray-400 text-sm mt-1">Sube tu primera APK para comenzar</p>
          </div>
        ) : (
          <div className="space-y-3">
            {versions.map((v, i) => (
              <div
                key={v.id}
                className={`bg-white rounded-xl border p-4 flex items-center justify-between ${
                  i === 0 ? 'border-green-200 bg-green-50' : 'border-gray-200'
                }`}
              >
                <div className="flex items-center gap-4">
                  <div className={`w-10 h-10 rounded-lg flex items-center justify-center ${
                    i === 0 ? 'bg-green-100' : 'bg-gray-100'
                  }`}>
                    <Package className={`w-5 h-5 ${i === 0 ? 'text-green-600' : 'text-gray-500'}`} />
                  </div>
                  <div>
                    <p className="font-medium text-gray-900 flex items-center gap-2">
                      v{v.version}
                      {i === 0 && (
                        <span className="px-2 py-0.5 bg-green-100 text-green-700 text-xs rounded-full">
                          Última
                        </span>
                      )}
                    </p>
                    <p className="text-xs text-gray-500 flex items-center gap-3">
                      <span className="flex items-center gap-1">
                        <Clock className="w-3 h-3" />
                        {new Date(v.uploadedAt).toLocaleDateString('es-AR')}
                      </span>
                      <span>{formatSize(v.size)}</span>
                    </p>
                  </div>
                </div>
                <a
                  href={v.downloadUrl}
                  className="p-2 text-gray-400 hover:text-red-600 hover:bg-red-50 rounded-lg transition-colors"
                >
                  <FileDown className="w-5 h-5" />
                </a>
              </div>
            ))}
          </div>
        )}
      </div>
    </DashboardLayout>
  );
}
