# Changelog

## M2 · Driver Broadlink + aprendizaje

- Protocolo local de Broadlink portado de python-broadlink 0.19.0: descubrimiento por broadcast
  y por IP, autenticación (0x65) con rotación de clave e ID, AES-128-CBC sin padding (CommonCrypto),
  checksums, familias RM / RM4 (prefijo de longitud) detectadas por devtype, `send_data`,
  `enter_learning`, `check_data`, barrido y captura RF en RM Pro / RM4 Pro.
- `scripts/gen_broadlink_vectors.py` + `AuraTests/BroadlinkVectors.swift`: los tests comparan
  byte a byte contra paquetes generados con la librería de referencia.
- Cliente actor con cola interna (varios dispositivos comparten el puente), re-autenticación
  automática si vence la clave y redescubrimiento por MAC si cambió la IP.
- Errores claros: Broadlink bloqueado, permiso de Red Local denegado, timeout, modelo no compatible.
- Asistente de aprendizaje: lista de botones, escucha con cuenta regresiva de 30 s, probar,
  reintentar, omitir, IR o RF. Guarda cada código apenas se graba.
- Control IR genérico editable: agregar botones, nombre, ícono, color, volver a grabar,
  eliminar y reordenar con drag & drop.
- Alta de dispositivos (LED, ventilador, genérico) desde Dispositivos.
- Ajustes → Puentes: buscar en la red, agregar por IP, probar conexión, redescubrir, olvidar.
- LED funcionando con el driver real (power, brillo, colores y efectos).

## M1 · Base del proyecto

- `project.yml` de XcodeGen (Swift 6, strict concurrency, macOS 14, sandbox).
- Design system dark con acentos azules: tokens de color, radios, espaciado, motion,
  tipografía y componentes `Card`, `PrimaryButton`, `IconButton`, `TileButton`, `Chip`,
  `StatusPill`, `Dial` (arrastre, scroll y teclado), `StepSlider`.
- Modelos (`Device`, `Room`, `HomeScene`, `Command`, `Capability`, `DeviceState`, `ACSettings`, `TVKey`).
- Persistencia en JSON con guardado diferido, exportar/importar configuración.
- Importador de `codigos.json` del prototipo (tolerante a archivos parciales o dañados).
- `CommandBus`: serializa por dispositivo, timeout de 3 s, un reintento con reconexión,
  publica el resultado para el feedback.
- Modo demo con drivers mock y casa de ejemplo.
- Ventana principal: sidebar, dashboard (saludo, resumen, escenas, tarjetas con control rápido),
  habitaciones, dispositivos con filtros, escenas ejecutables, ajustes.
- Controles completos: aire (dial, modo, ventilador, swing), TV (D-pad, volumen, canales,
  apps, teclado numérico, atajos de teclado), LED (colores, brillo, efectos), genérico.
- Sincronizar estado asumido a mano.
- Tests: importador, CommandBus (reintento, timeout, serialización, paralelismo), modelos y store.

Pendiente para los próximos hitos: drivers reales, asistente de aprendizaje, temporizador
del aire, isla, menú de barra, automatizaciones, onboarding, App Intents, ícono y DMG.
