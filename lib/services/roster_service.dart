import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as xl;
import 'package:flutter/foundation.dart';

class StudentRoster {
  final String id;
  final String firstName;
  final String lastName;
  final String middleInitial;
  final String email;

  StudentRoster({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.middleInitial = '',
    required this.email,
  });

  factory StudentRoster.fromMap(String id, Map<String, dynamic> data) {
    return StudentRoster(
      id: id,
      firstName: data['firstName'] ?? '',
      lastName: data['lastName'] ?? '',
      middleInitial: data['middleInitial'] ?? '',
      email: data['email'] ?? '',
    );
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s.split(' ').map((word) {
      if (word.isEmpty) return '';
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  String get formattedFullName {
    final last = _capitalize(lastName);
    final first = _capitalize(firstName);
    String mi = middleInitial.trim().toUpperCase();
    if (mi.isNotEmpty) {
      if (!mi.endsWith('.')) {
        mi = '$mi.';
      }
      return '$last, $first $mi';
    }
    return '$last, $first';
  }

  Map<String, dynamic> toMap() {
    return {
      'firstName': firstName,
      'lastName': lastName,
      'middleInitial': middleInitial,
      'email': email,
    };
  }
}

class RosterService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Watches all sections for an instructor.
  Stream<List<String>> watchSections(String instructorId) {
    return _db
        .collection('instructor_roster')
        .doc(instructorId)
        .collection('sections')
        .orderBy('name')
        .snapshots()
        .map((snap) => snap.docs.map((doc) => doc.id).toList());
  }

  /// Creates a new section.
  Future<void> createSection(String instructorId, String sectionName) async {
    final cleanName = sectionName.trim();
    if (cleanName.isEmpty) return;
    await _db
        .collection('instructor_roster')
        .doc(instructorId)
        .collection('sections')
        .doc(cleanName)
        .set({'name': cleanName, 'createdAt': FieldValue.serverTimestamp()});
  }

  /// Fetches the roster for a specific section.
  Stream<List<StudentRoster>> watchRoster(String instructorId, String sectionName) {
    return _db
        .collection('instructor_roster')
        .doc(instructorId)
        .collection('sections')
        .doc(sectionName)
        .collection('students')
        .orderBy('lastName')
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => StudentRoster.fromMap(doc.id, doc.data()))
            .toList());
  }

  /// Parses a spreadsheet file (CSV, XLSX, XLS) and uploads to the section's roster.
  Future<void> importRoster(String instructorId, String sectionName, Uint8List fileBytes, String fileName) async {
    try {
      final ext = fileName.split('.').last.toLowerCase();
      List<List<String>> rows;

      if (ext == 'csv') {
        final csvString = utf8.decode(fileBytes);
        rows = const CsvDecoder()
            .convert(csvString)
            .map((r) => r.map((e) => e.toString()).toList())
            .toList();
      } else if (ext == 'xlsx' || ext == 'xls') {
        final excel = xl.Excel.decodeBytes(fileBytes);
        final sheet = excel.tables[excel.tables.keys.first]!;
        rows = sheet.rows
            .map((r) => r.map((c) => c?.value?.toString() ?? '').toList())
            .toList();
      } else {
        throw Exception('Unsupported file format. Please use CSV, XLSX, or XLS.');
      }

      if (rows.isEmpty) return;

      final headers = rows.first.map((e) => e.toLowerCase().trim()).toList();

      int firstNameIdx = headers.indexWhere((h) => h.contains('first'));
      int lastNameIdx = headers.indexWhere((h) => h.contains('last'));
      int middleIdx = headers.indexWhere((h) =>
          h.contains('middle initial') || h.contains('middle') || h.contains('initial') ||
          h == 'm.i.' || h == 'mi' || h == 'm.i');
      int emailIdx = headers.indexWhere((h) => h.contains('email'));

      // Fallbacks if no exact header match
      if (firstNameIdx == -1) firstNameIdx = 0;
      if (lastNameIdx == -1) lastNameIdx = (middleIdx != -1) ? 2 : 1;
      if (emailIdx == -1) emailIdx = (middleIdx != -1) ? 3 : 2;

      final batch = _db.batch();
      final collRef = _db
          .collection('instructor_roster')
          .doc(instructorId)
          .collection('sections')
          .doc(sectionName)
          .collection('students');

      // Delete existing roster to avoid duplicates
      final existing = await collRef.get();
      for (var doc in existing.docs) {
        batch.delete(doc.reference);
      }

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.length <= emailIdx) continue; // skip malformed rows
        if (row[firstNameIdx].trim().isEmpty && row[lastNameIdx].trim().isEmpty) continue; // skip empty rows

        String mi = middleIdx != -1 && row.length > middleIdx ? row[middleIdx].trim() : '';

        final docRef = collRef.doc(); // auto-ID
        batch.set(docRef, {
          'firstName': row[firstNameIdx].trim(),
          'lastName': row[lastNameIdx].trim(),
          'middleInitial': mi,
          'email': row[emailIdx].trim().toLowerCase(), // Force lowercase for reliable querying
        });
      }

      await batch.commit();
    } catch (e) {
      debugPrint('Error importing roster: $e');
      rethrow;
    }
  }
}
