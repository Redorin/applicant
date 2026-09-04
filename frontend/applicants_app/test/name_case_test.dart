import 'package:applicants_app/core/text/name_case.dart';
import 'package:applicants_app/models/master_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('toTitleCase', () {
    test('plain names', () {
      expect(toTitleCase('juan'), 'Juan');
      expect(toTitleCase('SANTOS'), 'Santos');
      expect(toTitleCase('gArCiA'), 'Garcia');
    });

    test('trims and collapses whitespace', () {
      expect(toTitleCase('  juan   carlos  '), 'Juan Carlos');
      expect(toTitleCase(''), '');
      expect(toTitleCase('   '), '');
    });

    test('particles stay lowercase mid-name', () {
      expect(toTitleCase('DELA CRUZ'), 'dela Cruz');
      expect(toTitleCase('de la peña'), 'de la Peña');
      expect(toTitleCase('DELOS SANTOS'), 'delos Santos');
      expect(toTitleCase('juan y garcia'), 'Juan y Garcia');
    });

    test('all-particle names title-case normally', () {
      // "Dela" alone is a real surname — don't leave it lowercase.
      expect(toTitleCase('dela'), 'Dela');
      expect(toTitleCase('DE LA'), 'De La');
    });

    test('capitals after hyphen and apostrophe', () {
      expect(toTitleCase('mary-ann'), 'Mary-Ann');
      expect(toTitleCase("o'neil"), "O'Neil");
      expect(toTitleCase('anne-marie dela cruz'), 'Anne-Marie dela Cruz');
    });

    test('ñ is preserved and capitalized correctly', () {
      expect(toTitleCase('peña'), 'Peña');
      expect(toTitleCase('ÑOLA'), 'Ñola');
    });
  });

  group('normalizeDraftForSave', () {
    test('title-cases names and barangay, trims the rest', () {
      final d = MasterDataDraft(
        surname: '  DELA CRUZ ',
        firstname: 'juan',
        midname: 'SANTOS',
        barangay: 'poblacion  west',
        ext: ' Jr. ',
        contact: ' 0912 345 6789 ',
        address: '  12 Rizal St, Lingayen, Pangasinan ',
        notes: ' walk-in ',
        municipality: ' Lingayen ',
        province: ' Pangasinan ',
      );
      normalizeDraftForSave(d);
      expect(d.surname, 'dela Cruz');
      expect(d.firstname, 'Juan');
      expect(d.midname, 'Santos');
      expect(d.barangay, 'Poblacion West');
      expect(d.ext, 'Jr.');
      expect(d.contact, '0912 345 6789');
      // Address is trimmed but never recomposed or re-cased.
      expect(d.address, '12 Rizal St, Lingayen, Pangasinan');
      expect(d.notes, 'walk-in');
      expect(d.municipality, 'Lingayen');
      expect(d.province, 'Pangasinan');
    });
  });
}
