# Aura

App nativa de macOS para controlar el hogar (aire acondicionado, TV, barras de LED y más)
desde una ventana principal, una "Dynamic Island" emulada en el notch y la barra de menú.
Usa un Broadlink RM4 Mini como puente IR y la API local de las TV Samsung Tizen.

> Estado: **M7**: aire, TV Samsung, LED, webhooks, isla, barra de menús, escenas, automatizaciones,
> Atajos/Siri y atajos globales. Ver [CHANGELOG.md](CHANGELOG.md).

## Instalar (DMG)

```bash
scripts/build_release.sh                       # firma ad-hoc, sin notarizar
SIGN_IDENTITY="Developer ID Application: Nation IT Solutions (TEAMID)" \
NOTARY_PROFILE=aura-notary scripts/build_release.sh   # firmado y notarizado
```

El DMG queda en `dist/`. Arrastrá Aura a Aplicaciones. Con firma ad-hoc, la primera vez abrila con
clic derecho → **Abrir**. Para notarizar, guardá las credenciales una vez con
`xcrun notarytool store-credentials aura-notary --apple-id … --team-id … --password <app-specific>`.

## Requisitos

- macOS 14 Sonoma o superior
- Xcode 16 o superior (Swift 6)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Compilar y correr

```bash
xcodegen generate          # genera Aura.xcodeproj (no se versiona)
open Aura.xcodeproj        # y ⌘R
```

Desde la terminal:

```bash
xcodegen generate
xcodebuild -project Aura.xcodeproj -scheme Aura -destination 'platform=macOS' build
xcodebuild -project Aura.xcodeproj -scheme Aura -destination 'platform=macOS' test
```

## Modo demo

En la primera apertura Aura arranca en **modo demo**: reemplaza los drivers por simulaciones
con latencia (120–350 ms) y carga una casa de ejemplo (aire, TV, LED, ventilador y 4 escenas).
El modo demo trabaja en memoria y nunca toca tus datos reales.
Se desactiva en **Ajustes → Avanzado → Modo demo**.

## Importar los códigos del prototipo en Python

**Ajustes → Importar y exportar → Importar codigos.json del prototipo** abre un selector
apuntando a `~/.ar-mac/codigos.json`. Como la app corre en sandbox, macOS exige que el archivo
lo elija el usuario. El importador:

- `codigos`: `off` → `off`, `on` → `on`, `frio_<t>` → `cool_<t>`; el resto conserva su nombre.
- `led`: `ligar` → `power_on`, `desligar` → `power_off`, `brilho_mais` → `brightness_up`,
  `brilho_menos` → `brightness_down`; los colores conservan su nombre.
- `ip` → crea o actualiza el puente Broadlink.
- Omite entradas vacías o dañadas y muestra un aviso por cada una.

## Conectar tu Broadlink (M2)

1. **Ajustes → Avanzado**: desactivá el modo demo.
2. **Ajustes → Puentes → Buscar Broadlink**. La primera vez macOS pregunta si Aura puede usar la
   red local: aceptá. Si lo negaste, habilitalo en Ajustes del Sistema → Privacidad y seguridad →
   Red local.
3. Tocá **Agregar** en tu RM4 Mini. Si tu red bloquea el broadcast, escribí la IP a mano.
4. Si aparece "bloqueado": en la app Broadlink abrí el dispositivo → Propiedades → desactivá
   "Bloquear dispositivo".

### Probar los LED (criterio de aceptación de M2)

1. **Dispositivos → Agregar dispositivo** → tipo *Luces LED* → elegí el Broadlink → *Crear y grabar códigos*.
   (Si importaste el codigos.json, el dispositivo "LED" ya existe: abrilo y tocá *Grabar códigos*.)
2. Elegí un botón (por ejemplo *Encender*), tocá **Empezar a escuchar** y apretá ese botón en el
   control de los LED apuntando al Broadlink (a menos de 1 m).
3. Cuando diga "¡Listo!", tocá **Probar**: los LED tienen que responder.
4. Cerrá el asistente y usá la tarjeta o la ficha de los LED.

### Vectores de prueba del protocolo

```bash
python3 -m venv .venv && . .venv/bin/activate && pip install broadlink==0.19.0
python3 scripts/gen_broadlink_vectors.py > AuraTests/BroadlinkVectors.swift
```

## Aire acondicionado (M3)

1. **Dispositivos → Agregar → Aire**: elegí los modos a grabar (Frío, Calor…) y el rango (por defecto 17–26 °C).
2. *Crear y grabar códigos* abre el asistente con Encender, Apagar, Swing y cada temperatura.
3. Para las temperaturas: poné el control **un grado abajo** sin apuntar al aire, y apretá **TEMP +**
   apuntando al Broadlink. Cada paso siguiente es apretar TEMP + otra vez. Así el código tiene modo y
   temperatura juntos (los Carrier mandan el estado completo).
4. En la ficha: dial de temperatura (solo deja elegir las grabadas), modo, swing y **temporizador**
   (30/60/90/120 min para apagar).

## TV Samsung (M4)

1. **Dispositivos → Agregar → TV → Por red**. *Buscar* encuentra la TV por SSDP, o escribí su IP
   (TV → Configuración → General → Red → Estado de red).
2. *Crear y emparejar*: la TV muestra un aviso, elegí **Permitir** con el control. El token queda en
   el Llavero (servicio `com.nationit.aura`).
3. Encender usa Wake-on-LAN (la TV tiene que tener *Encender con móvil / red* activado) y, si no
   responde, el código IR `key_power` del Broadlink de respaldo.
4. Si la red falla, las teclas con código IR grabado salen por el Broadlink.

Si no conecta: TV y Mac en la misma red, TV encendida, y en la TV **Configuración → General →
Administrador de dispositivos externos → Administrador de conexión de dispositivos** con Aura en
*Permitir*. Desde la ficha de la TV: *Emparejar → Olvidar emparejamiento* y volver a emparejar.

## Webhooks

Tipo *Webhook*: cada acción es un pedido HTTP (GET/POST/PUT, encabezados y cuerpo). Las de uso
*Encender/Apagar* van al botón de power y a las escenas; las de uso *Botón* aparecen en el control.
Sirve para Home Assistant, Shelly, Tasmota, n8n, etc. Botón **Probar** en el editor.

## Dynamic Island (M5)

- Pasá el mouse por el notch (150 ms) o usá **⌥⌘Espacio**. Se cierra al salir (600 ms), con Esc o
  con un clic afuera.
- Pestañas con tus favoritos (aire con −/+, TV con volumen/canal/apps, LED con colores y brillo,
  botones de controles genéricos) y tus escenas favoritas.
- Después de cada comando muestra la actividad 1,8 s (roja si falló).
- En Macs sin notch es una píldora arriba al centro. Ajustes → Dynamic Island: pantalla, ocultar con
  apps en pantalla completa, apagarla.

## Barra de menús, atajos, Siri e inicio (M6)

- **Barra de menús**: favoritos con power, −/+ del aire, volumen de la TV y escenas. Opción
  *Solo en la barra de menús* (sin Dock).
- **Atajos globales** (sin permisos de Accesibilidad): ⌥⌘Espacio isla, ⌥⌘A ventana, ⌃⌥1…9 escenas
  favoritas. Se cambian en Ajustes → Atajos de teclado.
- **Siri / Atajos / Spotlight**: «Oye Siri, ejecutar Cine en Aura», «Encender Aire con Aura»,
  «Apagar TV con Aura», «Cambiar la temperatura de Aire con Aura». En la app Atajos están las
  acciones de Aura (encender/apagar, temperatura, escena, apretar un botón, abrir la isla).
- **Automatizaciones**: hora + días + acción (dispositivo o escena). Corren mientras Aura esté
  abierta (aunque sea solo en la barra de menús). Si fallan, avisan con una notificación.
- **Abrir al iniciar sesión**: Ajustes → Inicio (SMAppService).
- **Asistente inicial**: red local → Broadlink → codigos.json → TV. Se reabre desde Ajustes → Inicio.

## Solución de problemas

| Problema | Qué hacer |
|---|---|
| No encuentra el Broadlink | Agregalo por IP. Revisá Ajustes del Sistema → Privacidad → Red local → Aura activado. |
| "Broadlink bloqueado" | App Broadlink → dispositivo → Propiedades → desactivar *Bloquear dispositivo*. |
| Un botón no hace nada | Volvé a grabarlo más cerca (menos de 1 m) y probalo en el asistente. |
| El aire quedó desincronizado | Ficha → **Sincronizar** y poné cómo está realmente. |
| La TV no enciende | Activá *Encender con móvil* en la TV, o grabá `key_power` en el Broadlink de respaldo. |
| La TV pide permiso cada vez | Revisá que no esté en *Denegar* en el administrador de conexión de la TV. |
| No aparece la isla | Ajustes → Dynamic Island → activada; si usás pantalla completa, desactivá *Ocultar*. |
| Un atajo global no responde | Otra app ya lo usa: cambialo en Ajustes → Atajos de teclado. |
| Siri no conoce las frases | Abrí Aura una vez después de instalar y esperá unos minutos; mirá la app Atajos. |

## Ícono

`scripts/generate_icon.py` regenera el AppIcon (necesita Pillow solo para regenerar).

## Dónde se guardan los datos

`~/Library/Containers/com.nationit.aura/Data/Library/Application Support/Aura/store.json`
(JSON legible, también exportable desde Ajustes).

Logs: `log stream --predicate 'subsystem == "com.nationit.aura"'`

## Arquitectura

```
Aura/
  App/             AuraApp, AppDelegate, AppModel, AppSettings
  DesignSystem/    Tokens (color, radios, espaciado, motion), tipografía y componentes
  Features/        Root, Dashboard, Devices, Rooms, Remotes, Scenes, Automations, Settings,
                   Island (panel + vistas), MenuBar, Onboarding, Pairing, Webhook, Learning
  Intents/         App Intents y frases de Siri
  Core/
    Models/        Device, Room, HomeScene, Command, Capability, DeviceState, ACSettings, TVKey
    Store/         AppStore (@Observable), StoreFile (JSON), LegacyCodesImporter, DemoData
    CommandBus/    Cola por dispositivo, timeout de 3 s, un reintento con reconexión, feedback
    Support/       Log (os.Logger por subsistema), errores para el usuario, withTimeout
    Scheduler/     Automation, SleepTimer, Scheduler (próxima ejecución por calendario)
    HotKeys/       Atajos globales con Carbon RegisterEventHotKey
  Drivers/         Broadlink, SamsungTV (WebSocket, REST, WoL, SSDP, Llavero), Webhook, Mock
AuraTests/         Importador, CommandBus, modelos y store
```

Reglas clave:

- La UI **nunca** habla con un driver: todo pasa por `CommandBus`.
- El IR es de una sola vía: Aura guarda el último estado enviado ("estado asumido") y la ficha
  de cada dispositivo tiene **Sincronizar** para corregirlo sin enviar comandos.
- Los aires guardan un código por combinación (`<modo>_<temp>[_<ventilador>]`); la UI solo
  habilita las combinaciones grabadas y avisa cuáles faltan.

## Sandbox

App Sandbox activado con `network.client`, `network.server` (para recibir respuestas UDP del
Broadlink) y `files.user-selected.read-write` (importar/exportar).

El descubrimiento usa un socket BSD con `SO_BROADCAST` porque `NWConnection` no envía broadcast;
los pedidos a un Broadlink conocido usan `NWConnection`. Si el broadcast fallara bajo sandbox en
tu red, siempre podés agregar el Broadlink por IP.
