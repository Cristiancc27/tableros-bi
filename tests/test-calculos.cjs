const fs = require('fs');
const path = require('path');
const vm = require('vm');
const assert = require('assert/strict');
const root = path.resolve(__dirname, '../../..');
const html = fs.readFileSync(path.join(root, 'tools/tablero-cvp/Tablero_CVP.html'), 'utf8');
assert.equal(html, fs.readFileSync(path.join(root, 'siente/src/main/webapp/WEB-INF/tablero-cvp/Tablero_CVP.html'), 'utf8'));
const declaration = html.match(/^const valEjecutado=.*;$/m)[0];
const calculate = vm.runInNewContext(declaration + '\nvalEjecutado');
const households = [
  {Estado:'En ejecución', v:1000, ve:250, LoteID:2844},
  {Estado:'Ejecutado Entregado', v:2000, ve:1700, LoteID:2844},
  {Estado:'Diagnóstico viable', v:3000, ve:25, LoteID:2846}
];
assert.equal(calculate({hog:households}), 1975);
assert.equal(calculate({hog:households.filter(h=>h.LoteID===2844)}), 1950);
assert.equal(calculate({hog:[]}), 0);
console.log('PASS: valor ejecutado usa importes ejecutados, incluye todos los estados y respeta el filtro');

const normalize = vm.runInNewContext(html.match(/^const normalizeState =.*;$/m)[0] + '\nnormalizeState');
assert.equal(normalize('7. Estructuración aprobada'), 'Estructuración aprobada');
assert.equal(normalize('15. Asignado'), 'Asignado');
assert.equal(normalize('En ejecución'), 'En ejecución');
assert.equal(normalize(null), '');
const rawStates = ['7. Estructuración aprobada', '7. Estructuración aprobada', '15. Asignado', 'En ejecución'];
assert.equal(rawStates.map(normalize).filter(s=>s==='Estructuración aprobada').length, 2);
console.log('PASS: estados numerados y no numerados se agrupan correctamente');
