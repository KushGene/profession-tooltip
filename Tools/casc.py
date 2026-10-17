"""Minimaler Leser für den lokalen CASC-Speicher von World of Warcraft.

Liest Dateien per FileDataID aus einer lokalen Installation (Data/-Verzeichnis), ohne
externe Abhängigkeiten. Unterstützt nur, was zum Auslesen von DB2-Tabellen nötig ist:
lokale Indizes, BLTE (unkomprimiert/zlib), Encoding- und Root-Datei (MFST).
Verschlüsselte BLTE-Blöcke (Salsa20) werden mit bekannten TACT-Keys entschlüsselt; Blöcke mit
unbekanntem Schlüssel werden – wie bei anderen Tools üblich – mit Nullen gefüllt.
"""
import bisect
import os
import struct
import zlib

LOCALE_ENUS = 0x2
CONTENT_LOW_VIOLENCE = 0x80
CONTENT_NO_NAME_HASH = 0x10000000


def _hex_path(base, key_hex):
    return os.path.join(base, key_hex[0:2], key_hex[2:4], key_hex)


def _salsa20_xor(key, nonce, data):
    """Salsa20/20 mit 128-Bit-Schlüssel (so verschlüsselt Blizzard BLTE-Blöcke)."""
    constants = struct.unpack("<4I", b"expand 16-byte k")
    k = struct.unpack("<4I", key)
    n = struct.unpack("<2I", nonce)
    mask = 0xFFFFFFFF

    def rotl(v, c):
        return ((v << c) & mask) | (v >> (32 - c))

    out = bytearray(len(data))
    for block_index in range((len(data) + 63) // 64):
        state = [constants[0], k[0], k[1], k[2], k[3], constants[1], n[0], n[1],
                 block_index & mask, block_index >> 32, constants[2], k[0], k[1], k[2], k[3], constants[3]]
        x = state[:]
        for _ in range(10):
            # Spalten
            x[4] ^= rotl((x[0] + x[12]) & mask, 7); x[8] ^= rotl((x[4] + x[0]) & mask, 9)
            x[12] ^= rotl((x[8] + x[4]) & mask, 13); x[0] ^= rotl((x[12] + x[8]) & mask, 18)
            x[9] ^= rotl((x[5] + x[1]) & mask, 7); x[13] ^= rotl((x[9] + x[5]) & mask, 9)
            x[1] ^= rotl((x[13] + x[9]) & mask, 13); x[5] ^= rotl((x[1] + x[13]) & mask, 18)
            x[14] ^= rotl((x[10] + x[6]) & mask, 7); x[2] ^= rotl((x[14] + x[10]) & mask, 9)
            x[6] ^= rotl((x[2] + x[14]) & mask, 13); x[10] ^= rotl((x[6] + x[2]) & mask, 18)
            x[3] ^= rotl((x[15] + x[11]) & mask, 7); x[7] ^= rotl((x[3] + x[15]) & mask, 9)
            x[11] ^= rotl((x[7] + x[3]) & mask, 13); x[15] ^= rotl((x[11] + x[7]) & mask, 18)
            # Zeilen
            x[1] ^= rotl((x[0] + x[3]) & mask, 7); x[2] ^= rotl((x[1] + x[0]) & mask, 9)
            x[3] ^= rotl((x[2] + x[1]) & mask, 13); x[0] ^= rotl((x[3] + x[2]) & mask, 18)
            x[6] ^= rotl((x[5] + x[4]) & mask, 7); x[7] ^= rotl((x[6] + x[5]) & mask, 9)
            x[4] ^= rotl((x[7] + x[6]) & mask, 13); x[5] ^= rotl((x[4] + x[7]) & mask, 18)
            x[11] ^= rotl((x[10] + x[9]) & mask, 7); x[8] ^= rotl((x[11] + x[10]) & mask, 9)
            x[9] ^= rotl((x[8] + x[11]) & mask, 13); x[10] ^= rotl((x[9] + x[8]) & mask, 18)
            x[12] ^= rotl((x[15] + x[14]) & mask, 7); x[13] ^= rotl((x[12] + x[15]) & mask, 9)
            x[14] ^= rotl((x[13] + x[12]) & mask, 13); x[15] ^= rotl((x[14] + x[13]) & mask, 18)
        stream = struct.pack("<16I", *[(x[i] + state[i]) & mask for i in range(16)])
        start = block_index * 64
        chunk = data[start:start + 64]
        out[start:start + len(chunk)] = bytes(a ^ b for a, b in zip(chunk, stream))
    return bytes(out)


def read_blte(data, keys=None):
    """Dekodiert einen BLTE-Container. keys: {Schlüsselname (Hex, groß): 16-Byte-Schlüssel}"""
    if data[:4] != b"BLTE":
        raise ValueError("kein BLTE")
    header_size = struct.unpack(">I", data[4:8])[0]
    if header_size == 0:
        return _decode_chunk(data[8:], 0, None, keys)
    chunk_count = int.from_bytes(data[9:12], "big")
    pos, chunks = 12, []
    for _ in range(chunk_count):
        comp_size, decomp_size = struct.unpack(">II", data[pos:pos + 8])
        chunks.append((comp_size, decomp_size))
        pos += 24
    out = bytearray()
    pos = header_size
    for index, (comp_size, decomp_size) in enumerate(chunks):
        out += _decode_chunk(data[pos:pos + comp_size], index, decomp_size, keys)
        pos += comp_size
    return bytes(out)


def _decode_chunk(chunk, index, decomp_size, keys):
    mode = chunk[:1]
    if mode == b"N":
        return chunk[1:]
    if mode == b"Z":
        return zlib.decompress(chunk[1:])
    if mode == b"F":
        return read_blte(chunk[1:], keys)
    if mode == b"E":
        key_name_size = chunk[1]
        key_name = chunk[2:2 + key_name_size][::-1].hex().upper()
        pos = 2 + key_name_size
        iv_size = chunk[pos]
        iv = bytearray(chunk[pos + 1:pos + 1 + iv_size])
        pos += 1 + iv_size
        if chunk[pos:pos + 1] != b"S":
            raise ValueError("nur Salsa20 wird unterstützt")
        key = (keys or {}).get(key_name)
        if key is None:
            if decomp_size is None:
                raise ValueError("unbekannter Schlüssel " + key_name)
            return bytes(decomp_size)  # Inhalt nicht lesbar -> Nullen
        for i in range(4):  # Blockindex fließt in den IV ein
            iv[i] ^= (index >> (8 * i)) & 0xFF
        decrypted = _salsa20_xor(key, bytes(iv) + bytes(8 - len(iv)), chunk[pos + 1:])
        return _decode_chunk(decrypted, index, decomp_size, keys)
    raise ValueError(f"unbekannter BLTE-Modus {mode!r}")


def load_tact_keys(path):
    """Liest eine TACT-Keys-Liste im Format 'NAME SCHLÜSSEL' (wowdev/TACTKeys)."""
    keys = {}
    with open(path, encoding="utf8") as f:
        for line in f:
            parts = line.split()
            if len(parts) >= 2 and len(parts[0]) == 16 and len(parts[1]) == 32:
                keys[parts[0].upper()] = bytes.fromhex(parts[1])
    return keys


class LocalStorage:
    """Zugriff auf die Archive data.### über die lokalen .idx-Dateien."""

    def __init__(self, data_dir, keys=None):
        self.data_dir = data_dir
        self.keys = keys
        self.index = {}  # 9-Byte-EKey-Präfix -> (archiv, offset, größe)
        latest = {}
        for name in os.listdir(data_dir):
            if name.endswith(".idx") and len(name) == 14:
                bucket, version = int(name[0:2], 16), int(name[2:10], 16)
                if bucket not in latest or version > latest[bucket][0]:
                    latest[bucket] = (version, name)
        for _, name in latest.values():
            self._load_index(os.path.join(data_dir, name))

    def _load_index(self, path):
        with open(path, "rb") as f:
            data = f.read()
        header_size = struct.unpack("<I", data[0:4])[0]
        key_size = data[14]  # version(2) bucket(1) extra(1) sizeBytes(1) offsetBytes(1) keyBytes(1)
        pos = (8 + header_size + 0x0F) & ~0x0F  # Header wird auf 16 Byte aufgefüllt
        block_size = struct.unpack("<I", data[pos:pos + 4])[0]
        pos += 8
        end = pos + block_size
        entry_size = key_size + 5 + 4
        while pos + entry_size <= end:
            key = data[pos:pos + key_size]
            location = int.from_bytes(data[pos + key_size:pos + key_size + 5], "big")
            size = struct.unpack("<I", data[pos + key_size + 5:pos + entry_size])[0]
            if key not in self.index:
                self.index[key] = (location >> 30, location & 0x3FFFFFFF, size)
            pos += entry_size

    def read_ekey(self, ekey):
        entry = self.index.get(ekey[:9])
        if entry is None:
            raise KeyError("EKey nicht im lokalen Speicher: " + ekey.hex())
        archive, offset, size = entry
        with open(os.path.join(self.data_dir, f"data.{archive:03d}"), "rb") as f:
            f.seek(offset + 30)  # 30-Byte-Header vor jedem Eintrag
            return read_blte(f.read(size - 30), self.keys)


class Encoding:
    """CKey -> EKey über die Encoding-Datei (seitenweise, mit Binärsuche)."""

    def __init__(self, data):
        if data[:2] != b"EN":
            raise ValueError("keine Encoding-Datei")
        ckey_size, ekey_size = data[3], data[4]
        page_kb = struct.unpack(">H", data[5:7])[0]
        page_count = struct.unpack(">I", data[9:13])[0]
        espec_size = struct.unpack(">I", data[18:22])[0]
        pos = 22 + espec_size
        self.first_keys = []
        for _ in range(page_count):
            self.first_keys.append(data[pos:pos + ckey_size])
            pos += ckey_size + 16
        self.pages_start = pos
        self.page_size = page_kb * 1024
        self.data, self.ckey_size, self.ekey_size = data, ckey_size, ekey_size

    def lookup(self, ckey):
        page = bisect.bisect_right(self.first_keys, ckey) - 1
        if page < 0:
            return None
        pos = self.pages_start + page * self.page_size
        end = pos + self.page_size
        while pos < end:
            key_count = self.data[pos]
            if key_count == 0:
                break
            entry_ckey = self.data[pos + 6:pos + 6 + self.ckey_size]
            if entry_ckey == ckey:
                start = pos + 6 + self.ckey_size
                return self.data[start:start + self.ekey_size]
            pos += 6 + self.ckey_size + key_count * self.ekey_size
        return None


def parse_root(data):
    """FileDataID -> CKey (bevorzugt enUS, ohne Low-Violence-Varianten)."""
    result, priority = {}, {}
    pos = 0
    if data[:4] == b"TSFM":
        header_size, version = struct.unpack("<II", data[4:12])
        if header_size in (0x18, 0x14) and version in (1, 2):
            pos = header_size
        else:  # altes MFST ohne Header-Größe
            version = 0
            pos = 12
    else:
        version = -1  # Root ohne Magic (sehr alt)
    while pos < len(data):
        if version == 2:
            count, locale, unk1, unk2, unk3 = struct.unpack("<IIIIB", data[pos:pos + 17])
            content = unk1 | unk2 | (unk3 << 17)
            pos += 17
        else:
            count, content, locale = struct.unpack("<III", data[pos:pos + 12])
            pos += 12
        deltas = struct.unpack(f"<{count}i", data[pos:pos + 4 * count])
        pos += 4 * count
        ckeys_pos = pos
        pos += 16 * count
        if version == -1 or not (content & CONTENT_NO_NAME_HASH):
            pos += 8 * count
        if content & CONTENT_LOW_VIOLENCE:
            continue
        rank = 2 if locale & LOCALE_ENUS else (1 if locale else 0)
        fdid = -1
        for i, delta in enumerate(deltas):
            fdid += delta + 1
            if rank > priority.get(fdid, -1):
                priority[fdid] = rank
                result[fdid] = data[ckeys_pos + 16 * i:ckeys_pos + 16 * (i + 1)]
    return result


class Casc:
    """Öffnet einen Build (Build-Key aus .build.info) und liefert Dateien per FileDataID."""

    def __init__(self, wow_dir, product, keys=None):
        self.wow_dir = wow_dir
        self.build = self._find_build(product)
        config = self._read_config(self.build["Build Key"])
        self.build_name = config.get("build-name", [""])[0]
        self.storage = LocalStorage(os.path.join(wow_dir, "Data", "data"), keys)
        self.encoding = Encoding(self.storage.read_ekey(bytes.fromhex(config["encoding"][1])))
        self.root = parse_root(self.read_ckey(bytes.fromhex(config["root"][0])))

    def _find_build(self, product):
        with open(os.path.join(self.wow_dir, ".build.info"), encoding="utf8") as f:
            lines = [line.rstrip("\n") for line in f if line.strip()]
        header = [column.split("!")[0] for column in lines[0].split("|")]
        for line in lines[1:]:
            row = dict(zip(header, line.split("|")))
            if row.get("Product") == product:
                return row
        raise KeyError(f"Produkt {product} nicht in .build.info")

    def _read_config(self, key):
        config = {}
        with open(_hex_path(os.path.join(self.wow_dir, "Data", "config"), key), encoding="utf8") as f:
            for line in f:
                if " = " in line:
                    name, value = line.strip().split(" = ", 1)
                    config[name] = value.split()
        return config

    def read_ckey(self, ckey):
        ekey = self.encoding.lookup(ckey)
        if ekey is None:
            raise KeyError("CKey nicht in Encoding: " + ckey.hex())
        return self.storage.read_ekey(ekey)

    def read_fdid(self, fdid):
        ckey = self.root.get(fdid)
        if ckey is None:
            raise KeyError(f"FileDataID {fdid} nicht im Root")
        return self.read_ckey(ckey)
