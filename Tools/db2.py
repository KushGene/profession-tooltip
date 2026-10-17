"""Reader for DB2 tables in WDC5 format with column names from WoWDBDefs (.dbd).

Usage:
    table = read_table(db2_bytes, dbd_text)
    for row in table.values():   # {ID: {"column": value, ...}}
        ...
Arrays are returned as lists. Sections whose content was encrypted and not readable
(filled with zeros) are skipped.
"""
import re
import struct

STORAGE_NONE, STORAGE_BITPACKED, STORAGE_COMMON, STORAGE_PALLET, STORAGE_PALLET_ARRAY, STORAGE_BITPACKED_SIGNED = range(6)


# ----------------------------------------------------------------------------
# DBD (WoWDBDefs)
# ----------------------------------------------------------------------------
class Column:
    def __init__(self, name, type_, bits, signed, array, inline, is_id):
        self.name, self.type, self.bits, self.signed = name, type_, bits, signed
        self.array, self.inline, self.is_id = array, inline, is_id


def parse_dbd(text, layout_hash):
    """Columns (in record order) for the matching LAYOUT block."""
    column_types = {}
    blocks = text.replace("\r", "").split("\n\n")
    for line in blocks[0].splitlines()[1:]:
        match = re.match(r"(\w+)(?:<[^>]*>)?\s+(\w+)", line)
        if match:
            column_types[match[2].rstrip("?")] = match[1]
    wanted = f"{layout_hash:08X}"
    for block in blocks[1:]:
        lines = block.strip().splitlines()
        layouts = [line for line in lines if line.startswith("LAYOUT")]
        if not any(wanted in line for line in layouts):
            continue
        columns = []
        for line in lines:
            if line.startswith(("LAYOUT", "BUILD", "COMMENT")):
                continue
            match = re.match(r"(?:\$([^$]*)\$)?(\w+)(?:<(u?)(\d+)>)?(?:\[(\d+)\])?", line)
            annotations = (match[1] or "").split(",")
            name = match[2]
            columns.append(Column(
                name=name,
                type_=column_types.get(name, "int"),
                bits=int(match[4]) if match[4] else 32,
                signed=match[3] != "u",
                array=int(match[5]) if match[5] else 1,
                inline="noninline" not in annotations,
                is_id="id" in annotations,
            ))
        return columns
    raise KeyError(f"Layout {wanted} nicht in der DBD-Definition")


# ----------------------------------------------------------------------------
# WDC5
# ----------------------------------------------------------------------------
def _read_bits(data, bit_offset, bit_count):
    start = bit_offset >> 3
    end = (bit_offset + bit_count + 7) >> 3
    value = int.from_bytes(data[start:end], "little")
    return (value >> (bit_offset & 7)) & ((1 << bit_count) - 1)


def _signed(value, bits):
    return value - (1 << bits) if value & (1 << (bits - 1)) else value


def read_table(data, dbd_text):
    if data[:4] != b"WDC5":
        raise ValueError("nur WDC5 wird unterstützt")
    (record_count, field_count, record_size, string_table_size, _table_hash, layout_hash,
     _min_id, _max_id, _locale, flags, id_index, _total_fields, _bitpacked_offset,
     _lookup_columns, storage_info_size, common_size, pallet_size, section_count
     ) = struct.unpack("<9IHH7I", data[136:204])
    columns = [c for c in parse_dbd(dbd_text, layout_hash) if c.inline]
    if len(columns) != field_count:
        raise ValueError(f"DBD hat {len(columns)} Felder, Datei {field_count}")
    id_column = next((c for c in parse_dbd(dbd_text, layout_hash) if c.is_id), None)

    pos = 204
    sections = []
    for _ in range(section_count):
        sections.append(struct.unpack("<Q8I", data[pos:pos + 40]))
        pos += 40
    pos += 4 * field_count  # field_structure (size/position) – also in storage_info

    storage = []
    for _ in range(storage_info_size // 24):
        storage.append(struct.unpack("<HHII3I", data[pos:pos + 24]))
        pos += 24
    pallet_start = pos
    common_start = pallet_start + pallet_size

    # Extra data offsets per field (pallet or common data)
    pallet_offsets, common_maps = [], []
    pallet_pos, common_pos = pallet_start, common_start
    for (_, _, extra_size, storage_type, val1, _, _) in storage:
        pallet_offsets.append(pallet_pos)
        common = {}
        if storage_type in (STORAGE_PALLET, STORAGE_PALLET_ARRAY):
            pallet_pos += extra_size
        elif storage_type == STORAGE_COMMON:
            for i in range(extra_size // 8):
                key, value = struct.unpack("<II", data[common_pos + 8 * i:common_pos + 8 * i + 8])
                common[key] = value
            common_pos += extra_size
        common_maps.append(common)

    sparse = bool(flags & 1)
    # For strings: virtual position of all record blocks, followed by all string tables
    total_record_bytes = sum(s[2] * record_size for s in sections)
    string_tables, virtual_string = [], total_record_bytes
    for s in sections:
        string_tables.append((virtual_string, s[1] + s[2] * record_size, s[3]))
        virtual_string += s[3]

    rows = {}
    virtual_record = 0
    for index, (key_hash, file_offset, count, string_size, records_end, id_list_size,
                relationship_size, offset_map_count, copy_count) in enumerate(sections):
        pos = file_offset
        if sparse:
            records_blob_end = records_end
        else:
            records_blob_end = pos + count * record_size + string_size
        record_area = pos
        pos = records_blob_end
        ids = list(struct.unpack(f"<{id_list_size // 4}I", data[pos:pos + id_list_size]))
        pos += id_list_size
        copies = [struct.unpack("<II", data[pos + 8 * i:pos + 8 * i + 8]) for i in range(copy_count)]
        pos += 8 * copy_count
        offset_map = [struct.unpack("<IH", data[pos + 6 * i:pos + 6 * i + 6]) for i in range(offset_map_count)]
        pos += 6 * offset_map_count
        relation = {}
        if relationship_size:
            entries = struct.unpack("<I", data[pos:pos + 4])[0]
            rel_pos = pos + 12
            for i in range(entries):
                foreign, record_index = struct.unpack("<II", data[rel_pos + 8 * i:rel_pos + 8 * i + 8])
                relation[record_index] = foreign
            pos += relationship_size
        sparse_ids = list(struct.unpack(f"<{offset_map_count}I", data[pos:pos + 4 * offset_map_count]))

        # Encrypted, unreadable section -> completely zeroed
        if key_hash and not any(data[record_area:records_blob_end]):
            virtual_record += count * record_size
            continue

        for record_index in range(count):
            if sparse:
                record_offset, _size = offset_map[record_index]
                record_id = sparse_ids[record_index]
            else:
                record_offset = record_area + record_index * record_size
                record_id = ids[record_index] if ids else None
            record = data[record_offset:record_offset + (record_size if not sparse else _size)]
            if record_id is None:  # ID is in the record (id_index) – read it before common data fields
                id_offset_bits, id_size_bits, _, id_storage = storage[id_index][:4]
                if id_storage == STORAGE_NONE:
                    record_id = int.from_bytes(record[id_offset_bits >> 3:(id_offset_bits >> 3) + 4], "little")
                else:
                    record_id = _read_bits(record, id_offset_bits, id_size_bits)
            if sparse:
                row = _read_sparse_record(data, record_offset, columns)
                if id_column is not None:
                    row[id_column.name] = record_id
                rows[record_id] = row
                continue
            row = {}
            for field, column in enumerate(columns):
                field_offset_bits, field_size_bits, _, storage_type, val1, val2, val3 = storage[field]
                if column.type in ("string", "locstring"):
                    raw = struct.unpack("<I", record[field_offset_bits >> 3:(field_offset_bits >> 3) + 4])[0]
                    virtual = virtual_record + record_index * record_size + (field_offset_bits >> 3) + raw
                    row[column.name] = _string_at(data, string_tables, virtual)
                    continue
                values = []
                for element in range(column.array):
                    if storage_type == STORAGE_NONE:
                        size = column.bits // 8
                        start = (field_offset_bits >> 3) + element * size
                        value = int.from_bytes(record[start:start + size], "little")
                        if column.signed:
                            value = _signed(value, column.bits)
                    elif storage_type in (STORAGE_BITPACKED, STORAGE_BITPACKED_SIGNED):
                        value = _read_bits(record, field_offset_bits, field_size_bits)
                        if storage_type == STORAGE_BITPACKED_SIGNED:
                            value = _signed(value, field_size_bits)
                    elif storage_type == STORAGE_COMMON:
                        value = common_maps[field].get(record_id, val1)
                    elif storage_type == STORAGE_PALLET:
                        pallet_index = _read_bits(record, field_offset_bits, field_size_bits)
                        offset = pallet_offsets[field] + 4 * pallet_index
                        value = struct.unpack("<I", data[offset:offset + 4])[0]
                    else:  # STORAGE_PALLET_ARRAY
                        pallet_index = _read_bits(record, field_offset_bits, field_size_bits)
                        offset = pallet_offsets[field] + 4 * (pallet_index * val3 + element)
                        value = struct.unpack("<I", data[offset:offset + 4])[0]
                    if column.type == "float":
                        value = struct.unpack("<f", struct.pack("<I", value & 0xFFFFFFFF))[0]
                    values.append(value)
                row[column.name] = values if column.array > 1 else values[0]
            if id_column is not None:
                row[id_column.name] = record_id
            if record_index in relation:
                for column in parse_dbd(dbd_text, layout_hash):
                    if not column.inline and not column.is_id:
                        row[column.name] = relation[record_index]
            rows[record_id] = row
        for new_id, old_id in copies:
            if old_id in rows:
                copy = dict(rows[old_id])
                if id_column is not None:
                    copy[id_column.name] = new_id
                rows[new_id] = copy
        virtual_record += count * record_size
    return rows


def _read_sparse_record(data, offset, columns):
    """Sparse tables (e.g. ItemSparse): fields are stored uncompressed one after another,
    strings are embedded directly – so read sequentially."""
    row = {}
    pos = offset
    for column in columns:
        if column.type in ("string", "locstring"):
            end = data.index(b"\0", pos)
            row[column.name] = data[pos:end].decode("utf8", "replace")
            pos = end + 1
            continue
        size = column.bits // 8
        values = []
        for _ in range(column.array):
            value = int.from_bytes(data[pos:pos + size], "little")
            if column.type == "float":
                value = struct.unpack("<f", struct.pack("<I", value))[0]
            elif column.signed:
                value = _signed(value, column.bits)
            values.append(value)
            pos += size
        row[column.name] = values if column.array > 1 else values[0]
    return row


def _read_cstring(data, offset):
    end = data.index(b"\0", offset)
    return data[offset:end].decode("utf8", "replace")


def _string_at(data, string_tables, virtual):
    for virtual_start, file_start, size in string_tables:
        if virtual_start <= virtual < virtual_start + size:
            return _read_cstring(data, file_start + (virtual - virtual_start))
    return ""
