import { SesionPublicaRespuesta, PropuestaPayload } from './types';

export class ApiError extends Error {
  status: number;
  constructor(message: string, status: number) {
    super(message);
    this.status = status;
    this.name = 'ApiError';
  }
}

export async function fetchSesion(codigoOToken: string): Promise<SesionPublicaRespuesta> {
  const resp = await fetch(`/api/sesion/${encodeURIComponent(codigoOToken)}`, {
    headers: {
      Accept: 'application/json',
    },
  });

  if (!resp.ok) {
    if (resp.status === 404) {
      throw new ApiError('La sesión no existe o ya ha expirado.', 404);
    }
    if (resp.status === 429) {
      throw new ApiError('Demasiadas solicitudes. Por favor espera un momento.', 429);
    }
    throw new ApiError(`Error del servidor (${resp.status})`, resp.status);
  }

  return resp.json();
}

export async function enviarPropuesta(
  codigoOToken: string,
  propuesta: PropuestaPayload
): Promise<{ ok: boolean; duplicado?: boolean; mensaje?: string }> {
  const resp = await fetch(`/api/sesion/${encodeURIComponent(codigoOToken)}/propuesta`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Accept: 'application/json',
    },
    body: JSON.stringify(propuesta),
  });

  if (!resp.ok) {
    if (resp.status === 413) {
      throw new ApiError('El tamaño del reporte excede el límite permitido (64 KB).', 413);
    }
    if (resp.status === 404) {
      throw new ApiError('La sesión ya no está activa para recibir propuestas.', 404);
    }
    const errBody = await resp.json().catch(() => ({}));
    throw new ApiError(errBody.error || `Error enviando propuesta (${resp.status})`, resp.status);
  }

  return resp.json();
}

