import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { calcularEstadoItem } from './src/estado.ts';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const vectoresPath = path.resolve(__dirname, '..', 'contrato', 'estado_items.json');
const vectores = JSON.parse(fs.readFileSync(vectoresPath, 'utf8'));

let pasados = 0;
let fallidos = 0;

console.log(`\nVerificando ${vectores.length} vectores de prueba de contrato en TypeScript...`);

for (let i = 0; i < vectores.length; i++) {
  const v = vectores[i];
  const itemMock = {
    id: `item-${i}`,
    categoria: 'motor',
    descripcion: v.descripcion,
    componenteAplica: 'motor',
    intervaloKm: v.intervaloKm,
    intervaloMeses: v.intervaloMeses,
    intervaloSeveroKm: v.intervaloSeveroKm,
    ultimaVezKm: v.ultimaVezKm,
    ultimaVezFecha: v.ultimaVezFecha,
    fuente: 'oem',
    confianza: 'alta',
  };

  const resultado = calcularEstadoItem(itemMock as any, v.kmActual, v.tipoUso);

  if (resultado === v.estadoEsperado) {
    console.log(`  ✓ Vector ${i + 1}: ${v.descripcion} -> ${resultado}`);
    pasados++;
  } else {
    console.error(`  ✗ Vector ${i + 1}: ${v.descripcion}`);
    console.error(`    Esperado: ${v.estadoEsperado}, Obtenido: ${resultado}`);
    fallidos++;
  }
}

console.log(`\nResultado: ${pasados} pasados, ${fallidos} fallidos.`);
if (fallidos > 0) {
  process.exit(1);
}

