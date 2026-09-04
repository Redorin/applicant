/// Name/text normalization applied once, just before a record is saved, so
/// "DELA CRUZ", "dela cruz ", and "Dela  Cruz" all land in the database as
/// the same person-shaped value.
library;

import '../../models/master_data.dart';

/// Filipino/Spanish name particles that stay lowercase mid-name
/// ("Juan dela Cruz", "Maria de la Peña") — unless the whole name is
/// nothing but particles, in which case we title-case normally.
const _particles = {
  'de', 'dela', 'del', 'delos', 'delas', 'la', 'las', 'los',
  'y', 'da', 'di', 'van', 'von', 'dos',
};

/// Trims, collapses runs of whitespace, and title-cases each token.
/// Capitals also follow hyphens and apostrophes (Mary-Ann, O'Neil).
String toTitleCase(String input) {
  final collapsed = input.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (collapsed.isEmpty) return '';

  final words = collapsed.split(' ');
  final allParticles =
      words.every((w) => _particles.contains(w.toLowerCase()));

  String capToken(String token) {
    // Capitalize the first letter and any letter following - or '.
    final lower = token.toLowerCase();
    final out = StringBuffer();
    var capNext = true;
    for (final rune in lower.runes) {
      final ch = String.fromCharCode(rune);
      if (ch == '-' || ch == "'") {
        out.write(ch);
        capNext = true;
      } else {
        out.write(capNext ? ch.toUpperCase() : ch);
        capNext = false;
      }
    }
    return out.toString();
  }

  return words.map((w) {
    final lower = w.toLowerCase();
    if (!allParticles && _particles.contains(lower)) return lower;
    return capToken(w);
  }).join(' ');
}

/// Normalizes a draft in place right before it is serialized for save:
/// names and barangay become Title Case, every other free-text field is
/// trimmed. The composed [MasterDataDraft.address] is only trimmed — never
/// recomposed here — to protect legacy free-text addresses.
void normalizeDraftForSave(MasterDataDraft d) {
  d.surname = toTitleCase(d.surname);
  d.firstname = toTitleCase(d.firstname);
  d.midname = toTitleCase(d.midname);
  d.barangay = toTitleCase(d.barangay);
  d.street = toTitleCase(d.street);
  d.subdivision = toTitleCase(d.subdivision);

  d.ext = d.ext.trim();
  d.contact = d.contact.trim();
  d.contact2 = d.contact2.trim();
  d.address = d.address.trim();
  d.houseNo = d.houseNo.trim();
  d.district = d.district.trim();
  d.experience = d.experience.trim();
  d.skills = d.skills.trim();
  d.notes = d.notes.trim();
  d.lenofservice = d.lenofservice.trim();
  d.training = d.training.trim();
  d.municipality = d.municipality?.trim();
  d.province = d.province?.trim();
}
