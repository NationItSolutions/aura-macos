# Aura

App nativa de macOS para controlar el hogar (aire acondicionado, TV, barras de LED y más)
desde una ventana principal, una "Dynamic Island" emulada en el notch y la barra de menú.
Usa un Broadlink RM4 Mini como puente IR y la API local de las TV Samsung Tizen.

> Estado: **M2 (driver Broadlink + aprendizaje)**. La TV Samsung llega en M4. Ver [CHANGELOG.md](CHANGELOG.md).

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

## Dónde se guardan los datos

`~/Library/Containers/com.nationit.aura/Data/Library/Application Support/Aura/store.json`
(JSON legible, también exportable desde Ajustes).

Logs: `log stream --predicate 'subsystem == "com.nationit.aura"'`

## Arquitectura

```
Aura/
  App/             AuraApp, AppDelegate, AppModel, AppSettings
  DesignSystem/    Tokens (color, radios, espaciado, motion), tipografía y componentes
  Features/        Root (sidebar + toast), Dashboard, Devices, Rooms, Remotes, Scenes, Automations, Settings
  Core/
    Models/        Device, Room, HomeScene, Command, Capability, DeviceState, ACSettings, TVKey
    Store/         AppStore (@Observable), StoreFile (JSON), LegacyCodesImporter, DemoData
    CommandBus/    Cola por dispositivo, timeout de 3 s, un reintento con reconexión, feedback
    Support/       Log (os.Logger por subsistema), errores para el usuario, withTimeout
  Drivers/         DeviceDriver, IRCodeResolver, MockDriver, DriverRegistry
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
