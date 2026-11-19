# Changelog

## M7 · Distribución

- AppIcon propio (todas las medidas), generado con `scripts/generate_icon.py`.
- `scripts/build_release.sh`: Release, firma Developer ID o ad-hoc, notarización con notarytool si
  hay perfil, DMG con alias a Aplicaciones y fondo oscuro.
- README con instalación, configuración de cada equipo y solución de problemas.

## M6 · Escenas, automatizaciones, barra de menús, Siri y atajos

- Editor de escenas (pasos, demoras, orden, favoritas) y automatizaciones por hora y días.
- Scheduler: corre mientras la app esté abierta, respeta cambios de huso, no ejecuta horarios
  viejos al volver, notifica fallas. Temporizadores de apagado.
- MenuBarExtra con controles rápidos y escenas; modo solo barra de menús.
- App Intents + App Shortcuts en español (encender, apagar, temperatura, escena, botón, isla).
- Atajos globales con Carbon (sin dependencias ni permisos) y grabador de atajos.
- Abrir al iniciar sesión (SMAppService) y asistente inicial.

## M5 · Dynamic Island

- NSPanel no activante sobre el notch (geometría de `safeAreaInsets` y áreas auxiliares), píldora
  en Macs sin notch. Estados compacto, expandido (hover 150 ms o ⌥⌘Espacio) y actividad 1,8 s.
- Controles por tipo, pestañas de favoritos y escenas; cierre por salida del mouse, Esc o clic afuera.
- Respeta Reducir movimiento, feedback háptico, ocultar en pantalla completa y elección de pantalla.

## M4 · TV Samsung y webhooks

- WebSocket wss:8002 con token en el Llavero, REST 8001 (info y apps), Wake-on-LAN, SSDP.
- Emparejamiento guiado, olvidar emparejamiento, respaldo por IR cuando la red falla.
- Dispositivos webhook con acciones HTTP configurables.

## M3 · Aire acondicionado y habitaciones

- Alta de aire con modos y rango; grabación guiada con TEMP+; swing; temporizador.
- Habitaciones: crear, editar, eliminar y mover dispositivos arrastrando.

## M2.1 · Búsqueda de Broadlink más robusta

- La búsqueda manda el "hello" al broadcast global y al de cada interfaz (algunos Mac rechazan
  255.255.255.255 con "No route to host") y, si nadie responde, barre la subred por unicast
  (solo /22 a /30). Un destino que falla ya no corta la búsqueda.
- El selo "Modo demo activo" abre Ajustes, que muestra arriba un botón para desactivarlo.

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
