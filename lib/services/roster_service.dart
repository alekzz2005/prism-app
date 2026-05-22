import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';

class StudentRoster {
  final String id;
  final String firstName;
  final String lastName;
  final String email;

  StudentRoster({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
  });

  factory StudentRoster.fromMap(String id, Map<String, dynamic> data) {
    return StudentRoster(
      id: id,
      firstName: data['firstName'] ?? '',
      lastName: data['lastName'] ?? '',
      email: data['email'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
    };
  }
}

class RosterService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Fetches the roster for a specific instructor.
  Stream<List<StudentRoster>> watchRoster(String instructorId) {
    return _db
        .collection('instructor_roster')
        .doc(instructorId)
        .collection('students')
        .orderBy('lastName')
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => StudentRoster.fromMap(doc.id, doc.data()))
            .toList());
  }

  /// Parses CSV bytes and uploads them to the instructor's roster in Firestore.
  /// Expects columns: [First Name, Last Name, Email] (in any order, checks headers).
  Future<void> importCsv(String instructorId, Uint8List fileBytes) async {
    try {
      final csvString = utf8.decode(fileBytes);
      final List<List<dynamic>> rowsAsListOfValues =
          const CsvDecoder().convert(csvString);

      if (rowsAsListOfValues.isEmpty) return;

      final headers = rowsAsListOfValues.first.map((e) => e.toString().toLowerCase().trim()).toList();
      
      int firstNameIdx = headers.indexWhere((h) => h.contains('first'));
      int lastNameIdx = headers.indexWhere((h) => h.contains('last'));
      int emailIdx = headers.indexWhere((h) => h.contains('email'));

      // Fallbacks if no exact header match
      if (firstNameIdx == -1) firstNameIdx = 0;
      if (lastNameIdx == -1) lastNameIdx = 1;
      if (emailIdx == -1) emailIdx = 2;

      final batch = _db.batch();
      final collRef = _db
          .collection('instructor_roster')
          .doc(instructorId)
          .collection('students');

      // Delete existing roster to avoid duplicates (optional, but good for simple imports)
      final existing = await collRef.get();
      for (var doc in existing.docs) {
        batch.delete(doc.reference);
      }

      for (int i = 1; i < rowsAsListOfValues.length; i++) {
        final row = rowsAsListOfValues[i];
        if (row.length <= emailIdx) continue; // skip malformed rows

        final docRef = collRef.doc(); // auto-ID
        batch.set(docRef, {
          'firstName': row[firstNameIdx].toString().trim(),
          'lastName': row[lastNameIdx].toString().trim(),
          'email': row[emailIdx].toString().trim(),
        });
      }

      await batch.commit();
    } catch (e) {
      debugPrint('Error importing CSV: $e');
      rethrow;
    }
  }

  /// Adds a single mock student for testing purposes.
  Future<void> addMockStudent(String instructorId) async {
    final docRef = _db
        .collection('instructor_roster')
        .doc(instructorId)
        .collection('students')
        .doc();

    await docRef.set({
      'firstName': 'Test',
      'lastName': 'Student',
      'email': 'test.student@example.com',
    });
  }
}
