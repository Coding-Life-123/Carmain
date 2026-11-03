export type EstadoItem = 'vencido' | 'proximo' | 'ok' | 'desconocido';

export type CategoriaMantenimiento =
  | 'motor'
  | 'transmision'
  | 'frenos'
  | 'refrigeracion'
  | 'diferencial'
  | 'suspension'
  | 'neumaticos'
  | 'electrico'
  | 'escape'
  | 'inspeccion';

export type TipoComponente =
  | 'motor'
  | 'transmision'
  | 'diferencial'
  | 'transferCase'
  | 'frenos'
  | 'suspension'
  | 'otro';

export type TipoUso = 'normal' | 'severo';

export interface SnapshotMotor {
  codigo: string;
  esSwap: boolean;
  original?: string;
  combustible?: string;
  cilindrada?: number;
  cilindros?: number;
  aspiracion?: string;
  potenciaHp?: number;
  torqueNm?: number;
}

export interface SnapshotTransmision {
  codigo: string;
  esSwap: boolean;
  original?: string;
  tipo?: string;
  marchas?: number;
}

export interface SnapshotComponenteExtra {
  tipo: string;
  codigo: string;
  esSwap: boolean;
  original?: string;
  descripcion?: string;
}

export interface SnapshotVehiculo {
  marca: string;
  modelo: string;
  anio: number;
  trim?: string;
  placa?: string;
  vin?: string | null;
  drivetrain: string;
  kilometrajeActual: number;
  tipoUso: TipoUso;
  notasUso?: string | null;
  motor: SnapshotMotor;
  transmision: SnapshotTransmision;
  componentesExtra?: SnapshotComponenteExtra[];
}

export interface AlertaIngenieria {
  id: string;
  vector: string;
  severidad: 'alta' | 'media' | 'recomendacion';
  componenteAfectado: string;
  titulo: string;
  diagnostico: string;
  recomendacionUpgrade?: string;
}

export interface SnapshotItemPlan {
  id: string;
  categoria: CategoriaMantenimiento;
  descripcion: string;
  componenteAplica: TipoComponente;
  intervaloKm: number;
  intervaloMeses?: number;
  intervaloSeveroKm?: number;
  ultimaVezKm?: number;
  ultimaVezFecha?: string;
  fuente: string;
  confianza: string;
  esVigilanciaSwap?: boolean;
}

export interface SnapshotPlan {
  version: number;
  items: SnapshotItemPlan[];
  alertasIngenieria?: AlertaIngenieria[];
}

export interface SnapshotHistorialItem {
  categoria: CategoriaMantenimiento;
  descripcion: string;
  componenteAplica?: TipoComponente;
}

export interface SnapshotHistorial {
  id: string;
  fecha: string;
  kilometraje: number;
  items: SnapshotHistorialItem[];
  costo?: number;
  moneda?: string;
  taller?: string;
  nivelVerificacion: string;
  evidencia: number;
}

export interface SnapshotV1 {
  schema: number;
  generadoEn: string;
  vehiculo: SnapshotVehiculo;
  plan: SnapshotPlan;
  historial: SnapshotHistorial[];
}

export interface SesionPublicaRespuesta {
  codigo: string;
  tokenLargo?: string;
  vehiculoId: string;
  activa: boolean;
  creadaEn: string;
  expiraEn: string;
  consultadaEn?: string;
  snapshot: SnapshotV1;
}

export interface PropuestaItemRealizado {
  itemId?: string;
  categoria: CategoriaMantenimiento;
  componenteAplica: TipoComponente;
  descripcion: string;
}

export interface PropuestaPayload {
  schema: number;
  id: string;
  creadaEn: string;
  mecanico?: {
    taller?: string;
    nombre?: string;
  };
  kilometraje: number;
  fecha: string;
  costo?: number;
  moneda: string;
  notas?: string;
  itemsRealizados: PropuestaItemRealizado[];
}

