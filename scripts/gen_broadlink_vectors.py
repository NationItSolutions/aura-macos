#!/usr/bin/env python3
"""Genera vectores de prueba del protocolo Broadlink con python-broadlink (solo desarrollo).

Usa la librería de referencia (github.com/mjg59/python-broadlink, v0.19.0) con clave,
ID de sesión, contador, MAC y fecha fijos, y captura los bytes exactos que enviaría por UDP.
El resultado es AuraTests/BroadlinkVectors.swift: los tests en Swift tienen que producir
exactamente los mismos bytes.

Uso:
    python3 -m venv .venv && . .venv/bin/activate
    pip install broadlink==0.19.0
    python3 scripts/gen_broadlink_vectors.py > AuraTests/BroadlinkVectors.swift
"""
import datetime as dt
import socket
import struct
import sys

import broadlink
from broadlink import device as bl_device
from broadlink import remote as bl_remote
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

INIT_KEY = bytes.fromhex("097628343fe99e23765c1513accf8b02")
IV = bytes.fromhex("562e17996d093d28ddb3ba695a2e6f58")
MAC = bytes.fromhex("a043b0123456")           # orden natural (como lo muestra la app)
HOST = ("192.0.2.10", 80)
SESSION_ID = 0x0000A1B2
SESSION_KEY = bytes.fromhex("00112233445566778899aabbccddeeff")
COUNT = 0x8A21
IR_CODE = bytes.fromhex(
    "26004800000123941212121212371212121212121212121212371237123712121237"
    "123712371212121212121212123712121212121212371237123712371212123712"
    "000d050000000000"
)
RF_CODE = bytes.fromhex("b2001a00" + "0f0f" * 12 + "000d05")


def aes(key):
    return Cipher(algorithms.AES(key), modes.CBC(IV))


def encrypt(key, data):
    data = bytes(data) + bytes((16 - len(data)) % 16)
    enc = aes(key).encryptor()
    return enc.update(data) + enc.finalize()


def response(key, plain, error=0):
    """Respuesta de dispositivo válida: header de 0x38 bytes + payload cifrado + checksum."""
    packet = bytearray(0x38)
    packet[0:8] = bytes.fromhex("5aa5aa555aa5aa55")
    packet[0x22:0x24] = struct.pack("<h", error)
    packet.extend(encrypt(key, plain))
    checksum = sum(packet, 0xBEAF) & 0xFFFF
    packet[0x20:0x22] = checksum.to_bytes(2, "little")
    return bytes(packet)


class FakeSocket:
    queue = []
    sent = []

    def __init__(self, *args, **kwargs):
        pass

    def setsockopt(self, *args):
        pass

    def settimeout(self, *args):
        pass

    def bind(self, addr):
        pass

    def getsockname(self):
        return ("192.168.1.10", 54321)

    def sendto(self, data, addr):
        FakeSocket.sent.append(bytes(data))

    def recvfrom(self, size):
        if not FakeSocket.queue:
            raise socket.timeout()
        return FakeSocket.queue.pop(0), HOST

    def close(self):
        pass

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False


socket.socket = FakeSocket
FIXED_NOW = dt.datetime(2026, 11, 19, 15, 30, tzinfo=dt.timezone(dt.timedelta(hours=-3)))
bl_device.Datetime.now = staticmethod(lambda: FIXED_NOW)


def capture(action, *responses):
    FakeSocket.sent = []
    FakeSocket.queue = list(responses)
    result = action()
    return FakeSocket.sent[0], result


def make(cls, devtype):
    dev = cls(HOST, MAC, devtype)
    dev.count = COUNT
    return dev


def with_session(dev):
    dev.id = SESSION_ID
    dev.update_aes(SESSION_KEY)
    return dev


vectors = {}

# Checksum
vectors["checksumInput"] = bytes(range(0, 64))
vectors["checksumValue"] = (sum(bytes(range(0, 64)), 0xBEAF) & 0xFFFF).to_bytes(2, "little")

# Hello / descubrimiento
hello_resp = bytearray(0x80)
hello_resp[0x34:0x36] = (0x6539).to_bytes(2, "little")
hello_resp[0x3A:0x40] = MAC[::-1]
hello_resp[0x40:0x48] = b"RM4 mini"
locked_resp = bytearray(hello_resp)
locked_resp[0x7F] = 1
sent, found = capture(lambda: next(bl_device.scan(timeout=0.05, local_ip_address="192.168.1.10")), bytes(hello_resp))
vectors["helloRequest"] = sent
vectors["helloResponse"] = bytes(hello_resp)
vectors["helloResponseLocked"] = bytes(locked_resp)
assert found[0] == 0x6539 and found[2] == MAC and found[3] == "RM4 mini" and found[4] is False

# Autenticación (RM4 mini, devtype 0x6539)
auth_plain = SESSION_ID.to_bytes(4, "little") + SESSION_KEY
auth_resp = response(INIT_KEY, auth_plain)
dev = make(bl_remote.rm4mini, 0x6539)
sent, _ = capture(dev.auth, auth_resp)
assert dev.id == SESSION_ID and dev.count == ((COUNT + 1) | 0x8000) & 0xFFFF
vectors["authRequest"] = sent
vectors["authResponse"] = auth_resp

# RM4: send_data / enter_learning / check_data (prefijo de longitud)
ack_rm4 = response(SESSION_KEY, struct.pack("<HI", 4, 0x02))
dev = with_session(make(bl_remote.rm4mini, 0x6539))
vectors["rm4SendData"], _ = capture(lambda: dev.send_data(IR_CODE), ack_rm4)
dev = with_session(make(bl_remote.rm4mini, 0x6539))
vectors["rm4EnterLearning"], _ = capture(dev.enter_learning, response(SESSION_KEY, struct.pack("<HI", 4, 0x03)))
dev = with_session(make(bl_remote.rm4mini, 0x6539))
learned_rm4 = response(SESSION_KEY, struct.pack("<HI", len(IR_CODE) + 4, 0x04) + IR_CODE)
vectors["rm4CheckData"], data = capture(dev.check_data, learned_rm4)
vectors["rm4CheckDataResponse"] = learned_rm4
assert data[:len(IR_CODE)] == IR_CODE  # rmmini devuelve también el relleno AES
vectors["rm4CheckDataEmptyResponse"] = response(SESSION_KEY, struct.pack("<HI", 4, 0x04), error=-10)

# RM mini 3 clásico (sin prefijo de longitud)
dev = with_session(make(bl_remote.rmmini, 0x2737))
vectors["rmSendData"], _ = capture(lambda: dev.send_data(IR_CODE), response(SESSION_KEY, struct.pack("<I", 0x02)))
dev = with_session(make(bl_remote.rmmini, 0x2737))
learned_rm = response(SESSION_KEY, struct.pack("<I", 0x04) + IR_CODE)
vectors["rmCheckData"], data = capture(dev.check_data, learned_rm)
vectors["rmCheckDataResponse"] = learned_rm
assert data[:len(IR_CODE)] == IR_CODE  # rmmini devuelve también el relleno AES

# RM4 pro: RF
dev = with_session(make(bl_remote.rm4pro, 0x520B))
vectors["rm4ProSweep"], _ = capture(dev.sweep_frequency, response(SESSION_KEY, struct.pack("<HI", 4, 0x19)))
dev = with_session(make(bl_remote.rm4pro, 0x520B))
freq_resp = response(SESSION_KEY, struct.pack("<HI", 9, 0x1A) + b"\x01" + struct.pack("<I", 433920))
vectors["rm4ProCheckFrequency"], result = capture(dev.check_frequency, freq_resp)
vectors["rm4ProCheckFrequencyResponse"] = freq_resp
assert result == (True, 433.92)
dev = with_session(make(bl_remote.rm4pro, 0x520B))
vectors["rm4ProFindRF"], _ = capture(lambda: dev.find_rf_packet(433.92), response(SESSION_KEY, struct.pack("<HI", 4, 0x1B)))
dev = with_session(make(bl_remote.rm4pro, 0x520B))
vectors["rm4ProCancelSweep"], _ = capture(dev.cancel_sweep_frequency, response(SESSION_KEY, struct.pack("<HI", 4, 0x1E)))
dev = with_session(make(bl_remote.rm4pro, 0x520B))
vectors["rm4ProSendRF"], _ = capture(lambda: dev.send_data(RF_CODE), response(SESSION_KEY, struct.pack("<HI", 4, 0x02)))

# Error del dispositivo (-7: clave vencida)
vectors["errorResponse"] = response(SESSION_KEY, struct.pack("<HI", 4, 0x02), error=-7)

# Pulsos ↔ paquete IR
pulses = [9000, 4500, 560, 560, 560, 1690, 560, 40000]
vectors["pulsesPacket"] = bl_remote.pulses_to_data(pulses)

consts = {
    "initKey": INIT_KEY, "iv": IV, "mac": MAC, "sessionKey": SESSION_KEY, "irCode": IR_CODE, "rfCode": RF_CODE,
}

out = sys.stdout
out.write("// Generado por scripts/gen_broadlink_vectors.py con python-broadlink "
          f"{getattr(broadlink, '__version__', '0.19.0')}. NO EDITAR A MANO.\n")
out.write("// swiftlint:disable all\n\n")
out.write("enum BroadlinkVectors {\n")
out.write(f"    static let sessionID: UInt32 = 0x{SESSION_ID:08X}\n")
out.write(f"    static let count: UInt16 = 0x{COUNT:04X}\n")
out.write("    static let localIP = \"192.168.1.10\"\n")
out.write("    static let localPort: UInt16 = 54321\n")
out.write("    static let pulses: [Int] = " + repr(pulses) + "\n")
out.write("    static let helloDate = (year: 2026, month: 11, day: 19, hour: 15, minute: 30, utcOffsetHours: -3)\n\n")
for name, value in {**consts, **vectors}.items():
    out.write(f"    static let {name} = \"{bytes(value).hex()}\"\n")
out.write("}\n")
