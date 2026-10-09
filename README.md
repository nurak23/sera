# SERA-802.15.4 companion repository
Companion material for the paper on security overhead per byte / joule / airtime in IEEE 802.15.4-based stacks.

## Contents
- `paper/` LaTeX source (elsarticle) and bibliography
- `data/anonymized/` three Zigbee PRO captures, EUI-64s replaced, network key removed (see `anonymization/ANONYMIZATION.md`)
- `anonymization/` script, example map, method note
- `scripts/` spectrogram scripts, Octave analysis scripts, prototype O-QPSK receiver
- `figures/` coexistence spectrograms generated from the IQ recordings

## Evidence status
- Measured (this work): Zigbee frame lengths and header/security/payload byte split from the pcaps; coexistence spectrogram statistics.
- Specification-derived: PHY airtime T(L)=192+32L us; Matter PASE/CASE payload sizes.
- Literature-cited: Wi-SUN and TI mesh figures, Z-Wave parameters.
- Unresolved: `scripts/oqpsk_demod.m` is an UNVALIDATED prototype. On the 71 Zigbee IQ records it recovered 0 of 68 frames' preamble+SFD, so no demodulation result is claimed. The origin of the wideband coexistence burst is not attributed.
- Not included: raw IQ and CatSniffer captures (raw IQ can leak device identifiers); available on request.

## Licence
MIT.
