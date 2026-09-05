#!/usr/bin/env python3
"""lb-saphira-dicom-synth - generate a minimal synthetic DICOM object.

Copyright (c) 2026 AKADATA. MIT licensed.

Emits a valid DICOM Part-10 file (Implicit VR Little Endian, Secondary
Capture, 2x2 px) containing ONLY synthetic healthcheck data to stdout.
Used by lb.saphira.dicom.store / dicom.stow. No upstream sample files.
"""

import struct
import sys


def elem(group, element, value):
    if len(value) % 2:
        value += b"\x00"
    return struct.pack("<HH", group, element) + struct.pack("<I", len(value)) + value


def synth():
    preamble = b"\x00" * 128
    meta = b"".join([
        elem(0x0002, 0x0002, b"1.2.840.10008.5.1.4.1.1.7"),    # MediaStorageSOPClassUID (SC)
        elem(0x0002, 0x0003, b"1.2.826.0.1.3680043.10.1337.1.1"),  # synthetic SOPInstanceUID
        elem(0x0002, 0x0010, b"1.2.840.10008.1.2"),            # Implicit VR LE
        elem(0x0002, 0x0012, b"1.2.826.0.1.3680043.10.1337"),  # ImplementationClassUID
    ])
    out = preamble + b"DICM" + elem(0x0002, 0x0000, meta)
    dataset = b"".join([
        elem(0x0008, 0x0016, b"1.2.840.10008.5.1.4.1.1.7"),    # SOPClassUID
        elem(0x0008, 0x0018, b"1.2.826.0.1.3680043.10.1337.1.1"),
        elem(0x0010, 0x0010, b"SAPHIRA^SYNTHETIC^HEALTHCHECK"),  # synthetic, non-patient
        elem(0x0028, 0x0002, b"\x01\x00"),                     # SamplesPerPixel
        elem(0x0028, 0x0004, b"MONOCHROME2"),
        elem(0x0028, 0x0010, b"\x02\x00"),                     # Rows
        elem(0x0028, 0x0011, b"\x02\x00"),                     # Columns
        elem(0x0028, 0x0100, b"\x08"),                         # BitsAllocated
        elem(0x0028, 0x0101, b"\x08"),
        elem(0x0028, 0x0102, b"\x07"),
        elem(0x0028, 0x0103, b"\x00"),
        elem(0x7FE0, 0x0010, b"\x10\x20\x30\x40"),             # 4 px pixel data
    ])
    return out + dataset


if __name__ == "__main__":
    sys.stdout.buffer.write(synth())
